namespace ShoevSwitcher.Windows;

internal enum Language { English, Russian }

internal sealed class SwitcherEngine
{
    private static readonly HashSet<string> Excluded = new(StringComparer.OrdinalIgnoreCase) { "Shoev Spell", "Shoev Switcher", "WindowsTerminal", "powershell", "pwsh", "cmd", "Code", "devenv", "KeePass", "1Password" };
    private static readonly HashSet<uint> ResetKeys = [0x08, 0x2E, 0x25, 0x26, 0x27, 0x28, 0x09, 0x1B];
    private readonly Lexicon lexicon;
    private string word = "";
    private nint window;
    private DateTime lastShift;
    private readonly Queue<Language> recentLanguages = new();
    private readonly Dictionary<string, (int English, int Russian)> applicationLanguages = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, Language> lastApplicationLayout = new(StringComparer.OrdinalIgnoreCase);
    private LastCorrection? lastCorrection;
    private readonly bool testMode;
    internal event Action<string, string>? Corrected;
    internal event Action<string, Language>? Completed;
    internal SwitcherEngine(Lexicon lexicon, bool testMode = false) { this.lexicon = lexicon; this.testMode = testMode; }

    internal bool HandleKey(KeyEvent key)
    {
        if (key.FromShoevSpell) { ObserveExternal(key); return false; }
        var foreground = NativeMethods.GetForegroundWindow();
        var process = NativeMethods.ProcessName();
        if (window != foreground)
        {
            word = ""; window = foreground;
            if (SettingsStore.GetBool("RememberLayout", false) && lastApplicationLayout.TryGetValue(process, out var remembered)) NativeMethods.SwitchLayout(remembered);
        }
        if (!(testMode || SettingsStore.GetBool("Enabled", true)) || (!testMode && (Excluded.Contains(process)
            || SettingsStore.GetExclusions().Contains(process, StringComparer.OrdinalIgnoreCase)))
            || NativeMethods.IsPasswordField()) { word = ""; return false; }

        var manualKey = SettingsStore.GetString("ManualSide", "Right") == "Left" ? 0xA0u : 0xA1u;
        if (key.VirtualKey == manualKey)
        {
            var now = DateTime.UtcNow;
            if (SettingsStore.GetBool("Manual", true) && word.Length > 0 && now - lastShift < TimeSpan.FromMilliseconds(450))
            {
                var original = word; var converted = LayoutConverter.Convert(original); var language = LayoutConverter.Detect(converted);
                if (!NativeMethods.Replace(original.Length, converted, "")) { lastShift = default; return false; }
                NativeMethods.SwitchLayout(language);
                if (SettingsStore.GetBool("Learning", true)) PersonalRules.RecordManual(original, converted);
                RegisterLanguage(language, process); Corrected?.Invoke(original, converted); word = converted; lastShift = default; return false;
            }
            lastShift = now; return false;
        }
        if ((Control.ModifierKeys & (Keys.Control | Keys.Alt)) != 0 || key.VirtualKey is 0x5B or 0x5C) { word = ""; return false; }
        if (key.VirtualKey == 0x08 && SettingsStore.GetBool("Undo", true) && lastCorrection is { } previous
            && previous.Window == foreground && DateTime.UtcNow - previous.Time < TimeSpan.FromSeconds(5))
        {
            if (!NativeMethods.Replace(previous.Alternative.Length + previous.Delimiter.Length, previous.Original, previous.Delimiter)) return false;
            NativeMethods.SwitchLayout(previous.Source); Corrected?.Invoke(previous.Alternative, previous.Original); lastCorrection = null; word = ""; return true;
        }
        if (ResetKeys.Contains(key.VirtualKey)) { word = ""; return false; }
        var text = key.Text();
        if (text.Length == 0) return false;
        if (text.All(char.IsLetter)) { word += text; if (word.Length > 64) word = ""; return false; }
        if (text is " " or "\r" or "\n" || text.All(c => ",.;:!?…".Contains(c))) return Complete(text);
        word = ""; return false;
    }

    private void ObserveExternal(KeyEvent key)
    {
        if (ResetKeys.Contains(key.VirtualKey)) { word = ""; return; }
        var text = key.Text();
        if (text.Length == 0) return;
        if (text.All(char.IsLetter))
        {
            word += text;
            if (word.Length > 64) word = "";
            return;
        }
        if (text is " " or "\r" or "\n" || text.All(c => ",.;:!?…".Contains(c))) { word = ""; return; }
        word = "";
    }

    private bool Complete(string delimiter)
    {
        if (word.Length == 0) return false;
        var original = word; word = "";
        if (!(testMode || SettingsStore.GetBool("Automatic", true))) { var language = LayoutConverter.Detect(original); RegisterLanguage(language, NativeMethods.ProcessName()); Completed?.Invoke(original, language); return false; }
        var source = LayoutConverter.Detect(original); var target = source == Language.English ? Language.Russian : Language.English;
        var alternative = LayoutConverter.Convert(original);
        if (!ShouldConvert(original, alternative, source, target, NativeMethods.ProcessName())) { RegisterLanguage(source, NativeMethods.ProcessName()); Completed?.Invoke(original, source); return false; }
        if (!NativeMethods.Replace(original.Length, alternative, delimiter)) { RegisterLanguage(source, NativeMethods.ProcessName()); Completed?.Invoke(original, source); return false; }
        NativeMethods.SwitchLayout(target);
        lastCorrection = new LastCorrection(original, alternative, delimiter, source, NativeMethods.GetForegroundWindow(), DateTime.UtcNow);
        RegisterLanguage(target, NativeMethods.ProcessName()); Completed?.Invoke(alternative, target);
        Corrected?.Invoke(original, alternative);
        return true;
    }

    private bool ShouldConvert(string original, string alternative, Language source, Language target, string process)
    {
        if (original.Length > 64 || original.Any(char.IsDigit)) return false;
        if (PersonalRules.ShouldConvert(original, alternative)) return true;
        var sourceScore = lexicon.Score(original.ToLowerInvariant(), source);
        var targetScore = lexicon.Score(alternative.ToLowerInvariant(), target);
        if (targetScore is null) return false;
        var sourceValue = sourceScore ?? 2.0;
        var targetValue = targetScore.Value;
        if (SettingsStore.GetBool("PhraseContext", true) && recentLanguages.Count > 0)
            targetValue += Math.Min(recentLanguages.Count(x => x == target) * 0.12, 0.48);
        if (SettingsStore.GetBool("ApplicationContext", true) && applicationLanguages.TryGetValue(process, out var counts))
        {
            var dominant = counts.Russian > counts.English ? Language.Russian : Language.English;
            if (dominant == target) targetValue += 0.28;
        }
        var margin = original.Length switch { 1 => 1.65, 2 => 1.15, _ => 0.75 };
        if (lexicon.ProtectsOriginal(original.ToLowerInvariant(), source) && original.Length > 1) { sourceValue = Math.Max(sourceValue, 3.5); margin += 0.65; }
        return targetValue - sourceValue >= margin;
    }

    private void RegisterLanguage(Language language, string process)
    {
        recentLanguages.Enqueue(language); while (recentLanguages.Count > 5) recentLanguages.Dequeue();
        applicationLanguages.TryGetValue(process, out var counts);
        applicationLanguages[process] = language == Language.English ? (counts.English + 1, counts.Russian) : (counts.English, counts.Russian + 1);
        lastApplicationLayout[process] = language;
    }

    private sealed record LastCorrection(string Original, string Alternative, string Delimiter, Language Source, nint Window, DateTime Time);
}

internal static class LayoutConverter
{
    private const string English = "`qwertyuiop[]asdfghjkl;'zxcvbnm,.";
    private const string Russian = "ёйцукенгшщзхъфывапролджэячсмитьбю";
    internal static Language Detect(string value) => value.Any(c => c is >= 'А' and <= 'я' or 'Ё' or 'ё') ? Language.Russian : Language.English;
    internal static string Convert(string value)
    {
        var source = Detect(value); var from = source == Language.English ? English : Russian; var to = source == Language.English ? Russian : English;
        return string.Concat(value.Select(c =>
        {
            var lower = char.ToLowerInvariant(c); var index = from.IndexOf(lower);
            if (index < 0) return c;
            var mapped = to[index]; return char.IsUpper(c) ? char.ToUpperInvariant(mapped) : mapped;
        }));
    }
}
