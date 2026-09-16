using System.Text.Json;

namespace ShoevSwitcher.Windows;

internal sealed record JournalEntry(DateTime Time, string Application, string Original, string? Replacement, string Kind, string? Language);

internal sealed class JournalStore
{
    private readonly string path = Path.Combine(SettingsStore.Folder, "journal.jsonl");
    private readonly object gate = new();

    internal void Record(string original, string replacement, string application, string kind)
    {
        if (!SettingsStore.GetBool("Journal", true)) return;
        Append(new JournalEntry(DateTime.Now, application, original, replacement, kind, null));
    }

    internal void RecordCompleted(string word, Language language, string application)
    {
        if (!SettingsStore.GetBool("Journal", true) || !SettingsStore.GetBool("FullDiary", false)) return;
        Append(new JournalEntry(DateTime.Now, application, word, null, "Набрано", language == Language.Russian ? "Русский" : "English"));
    }

    private void Append(JournalEntry entry)
    {
        lock (gate)
        {
            Directory.CreateDirectory(SettingsStore.Folder);
            File.AppendAllText(path, JsonSerializer.Serialize(entry) + Environment.NewLine);
        }
    }

    internal List<JournalEntry> Read()
    {
        lock (gate)
        {
            if (!File.Exists(path)) return [];
            return File.ReadLines(path).Select(x => { try { return JsonSerializer.Deserialize<JournalEntry>(x); } catch { return null; } })
                .Where(x => x is not null).Cast<JournalEntry>().Reverse().Take(5000).ToList();
        }
    }
    internal void Clear() { lock (gate) { if (File.Exists(path)) File.Delete(path); } }
}
