using Microsoft.Win32;

namespace ShoevSwitcher.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        if (args.Contains("--self-test")) return SelfTest.Run();
        using var mutex = new Mutex(true, "ShoevSwitcher.Windows.SingleInstance", out var created);
        if (!created) return 0;
        Application.Run(new SwitcherApplication(!args.Contains("--background")));
        return 0;
    }
}

internal static class SelfTest
{
    internal static int Run()
    {
        using var lexicon = new Lexicon();
        return LayoutConverter.Convert("ghbdtn") == "привет"
            && LayoutConverter.Convert("руддщ") == "hello"
            && lexicon.Score("привет", Language.Russian) is > 0
            && lexicon.Score("hello", Language.English) is > 0 ? 0 : 1;
    }
}

internal sealed class SwitcherApplication : ApplicationContext
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private readonly NotifyIcon tray;
    private readonly KeyboardHook hook;
    private readonly Icon appIcon;
    private readonly JournalStore journal;
    private readonly SwitcherEngine engine;
    private readonly LayoutIndicator indicator;

    internal SwitcherApplication(bool showWindow)
    {
        appIcon = Branding.LoadIcon();
        journal = new JournalStore();
        engine = new SwitcherEngine(new Lexicon());
        indicator = new LayoutIndicator();
        hook = new KeyboardHook(engine.HandleKey);
        var enabled = CheckItem("Включено", "Enabled", true);
        var automatic = CheckItem("Автоматическое исправление", "Automatic", true);
        var manual = CheckItem("Двойной правый Shift", "Manual", true);
        var notification = CheckItem("Показывать уведомления", "Notifications", true);
        var startup = new ToolStripMenuItem("Запускать вместе с Windows") { CheckOnClick = true, Checked = IsStartupEnabled() };
        startup.CheckedChanged += (_, _) => SetStartup(startup.Checked);
        var menu = new ContextMenuStrip();
        menu.Items.AddRange([enabled, automatic, manual, notification, new ToolStripSeparator(), startup,
            new ToolStripSeparator(),
            new ToolStripMenuItem("Настройки…", null, (_, _) => OpenSettings()),
            new ToolStripMenuItem("Дневник и правила…", null, (_, _) => OpenJournal()),
            new ToolStripSeparator(), new ToolStripMenuItem("О Shoev Switcher", null, (_, _) => MessageBox.Show(
                "Shoev Switcher для Windows\n\nАвтоматически исправляет текст, набранный в неверной русской или английской раскладке.\nВсё работает локально.",
                "Shoev Switcher", MessageBoxButtons.OK, MessageBoxIcon.Information)),
            new ToolStripMenuItem("Выход", null, (_, _) => ExitThread())]);
        tray = new NotifyIcon { Text = "Shoev Switcher", Icon = appIcon, Visible = true, ContextMenuStrip = menu };
        engine.Corrected += (before, after) =>
        {
            journal.Record(before, after, NativeMethods.ProcessName(), "Исправление");
            if (!SettingsStore.GetBool("Notifications", true)) return;
            tray.BalloonTipTitle = "Shoev Switcher";
            tray.BalloonTipText = $"{before} → {after}";
            tray.ShowBalloonTip(1800);
        };
        engine.Completed += (word, language) => journal.RecordCompleted(word, language, NativeMethods.ProcessName());
        tray.DoubleClick += (_, _) => OpenSettings();
        hook.Start();
        indicator.Start();
        if (showWindow)
        {
            var opener = new System.Windows.Forms.Timer { Interval = 250 };
            opener.Tick += (_, _) => { opener.Stop(); opener.Dispose(); OpenSettings(); };
            opener.Start();
        }
    }

    private void OpenSettings()
    {
        using var window = new SettingsForm(appIcon);
        window.ShowDialog();
        indicator.RefreshVisibility();
    }

    private void OpenJournal()
    {
        using var window = new JournalForm(appIcon, journal);
        window.ShowDialog();
    }

    private static ToolStripMenuItem CheckItem(string title, string key, bool fallback)
    {
        var item = new ToolStripMenuItem(title) { CheckOnClick = true, Checked = SettingsStore.GetBool(key, fallback) };
        item.CheckedChanged += (_, _) => SettingsStore.SetBool(key, item.Checked);
        return item;
    }
    protected override void ExitThreadCore() { hook.Dispose(); indicator.Dispose(); tray.Visible = false; tray.Dispose(); base.ExitThreadCore(); }
    private static bool IsStartupEnabled() { using var key = Registry.CurrentUser.OpenSubKey(RunKey); return key?.GetValue("Shoev Switcher") is string; }
    private static void SetStartup(bool value)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (value) key.SetValue("Shoev Switcher", $"\"{Environment.ProcessPath}\" --background"); else key.DeleteValue("Shoev Switcher", false);
    }
}

internal static class SettingsStore
{
    internal static readonly string Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Shoev Switcher");
    private static readonly string Pathname = Path.Combine(Folder, "settings.json");
    private static Dictionary<string, bool>? values;
    private static readonly Dictionary<string, string> strings = new(StringComparer.OrdinalIgnoreCase);
    private static string[]? exclusionsCache;
    internal static bool GetBool(string key, bool fallback) { Load(); return values!.TryGetValue(key, out var value) ? value : fallback; }
    internal static void SetBool(string key, bool value) { Load(); values![key] = value; Directory.CreateDirectory(Folder); File.WriteAllText(Pathname, System.Text.Json.JsonSerializer.Serialize(values)); }
    internal static string GetString(string key, string fallback)
    {
        if (strings.TryGetValue(key, out var cached)) return cached;
        try
        {
            var path = Path.Combine(Folder, key + ".txt");
            var value = File.Exists(path) ? File.ReadAllText(path).Trim() : fallback;
            strings[key] = value; return value;
        }
        catch { return fallback; }
    }
    internal static void SetString(string key, string value) { strings[key] = value; Directory.CreateDirectory(Folder); File.WriteAllText(Path.Combine(Folder, key + ".txt"), value); }
    internal static string[] GetExclusions()
    {
        if (exclusionsCache is not null) return exclusionsCache;
        try { exclusionsCache = File.ReadAllLines(Path.Combine(Folder, "exclusions.txt")).Select(x => x.Trim()).Where(x => x.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(); }
        catch { exclusionsCache = []; }
        return exclusionsCache;
    }
    internal static void SetExclusions(IEnumerable<string> values)
    {
        exclusionsCache = values.Select(x => x.Trim()).Where(x => x.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        Directory.CreateDirectory(Folder); File.WriteAllLines(Path.Combine(Folder, "exclusions.txt"), exclusionsCache);
    }
    private static void Load()
    {
        if (values is not null) return;
        try { values = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, bool>>(File.ReadAllText(Pathname)); } catch { values = []; }
        values ??= [];
    }
}
