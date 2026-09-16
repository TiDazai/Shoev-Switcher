using System.Text.Json;

namespace ShoevSwitcher.Windows;

internal sealed record LearningRule(string Original, string Replacement, int Count, bool Learned);

internal static class PersonalRules
{
    private static readonly string Pathname = Path.Combine(SettingsStore.Folder, "learning.json");
    private static readonly object Gate = new();

    internal static void RecordManual(string original, string replacement)
    {
        lock (Gate)
        {
            var rules = ReadInternal(); var key = original.ToLowerInvariant();
            var current = rules.FirstOrDefault(x => x.Original.Equals(key, StringComparison.OrdinalIgnoreCase) && x.Replacement.Equals(replacement, StringComparison.OrdinalIgnoreCase));
            if (current is not null) rules.Remove(current);
            var count = (current?.Count ?? 0) + 1; rules.Add(new LearningRule(key, replacement.ToLowerInvariant(), count, count >= 2)); Save(rules);
        }
    }
    internal static bool ShouldConvert(string original, string replacement)
    {
        lock (Gate) return ReadInternal().Any(x => x.Learned && x.Original.Equals(original, StringComparison.OrdinalIgnoreCase) && x.Replacement.Equals(replacement, StringComparison.OrdinalIgnoreCase));
    }
    internal static List<LearningRule> Read() { lock (Gate) return ReadInternal(); }
    internal static void Clear() { lock (Gate) { if (File.Exists(Pathname)) File.Delete(Pathname); } }
    private static List<LearningRule> ReadInternal()
    {
        try { return JsonSerializer.Deserialize<List<LearningRule>>(File.ReadAllText(Pathname)) ?? []; } catch { return []; }
    }
    private static void Save(List<LearningRule> values) { Directory.CreateDirectory(SettingsStore.Folder); File.WriteAllText(Pathname, JsonSerializer.Serialize(values)); }
}
