using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace ShoevSwitcher.Windows;

internal sealed class Lexicon : IDisposable
{
    private const string ExpectedHash = "493B2B9E1AC83D755A77B24D031AFFB6A0BA05AC5CFEEA0C9AFF16AD054A4025";
    private nint database, scoreQuery, protectionQuery;
    internal Lexicon()
    {
        try
        {
            var path = Prepare(); if (Sqlite.sqlite3_open_v2(Utf8(path), out database, 1, 0) != 0) return;
            Sqlite.sqlite3_prepare_v2(database, Utf8("SELECT score FROM words WHERE language=?1 AND word=?2"), -1, out scoreQuery, 0);
            Sqlite.sqlite3_prepare_v2(database, Utf8("SELECT protects_original FROM words WHERE language=?1 AND word=?2"), -1, out protectionQuery, 0);
        }
        catch { database = scoreQuery = protectionQuery = 0; }
    }
    internal double? Score(string word, Language language)
    {
        var score = Query(scoreQuery, word, language); return score is null ? null : score.Value / 100.0;
    }
    internal bool ProtectsOriginal(string word, Language language) => Query(protectionQuery, word, language) is > 0;
    private int? Query(nint query, string word, Language language)
    {
        if (query == 0) return null;
        lock (this)
        {
            Sqlite.sqlite3_reset(query); Sqlite.sqlite3_clear_bindings(query); Sqlite.sqlite3_bind_int(query, 1, language == Language.English ? 0 : 1);
            var value = Utf8(word); Sqlite.sqlite3_bind_text(query, 2, value, value.Length - 1, new nint(-1));
            return Sqlite.sqlite3_step(query) == 100 ? Sqlite.sqlite3_column_int(query, 0) : null;
        }
    }
    private static string Prepare()
    {
        var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Shoev Switcher");
        var target = Path.Combine(folder, "lexicon.sqlite3"); if (File.Exists(target)) return target;
        Directory.CreateDirectory(folder); var archive = Path.Combine(AppContext.BaseDirectory, "lexicon.sqlite3.gz");
        using (var stream = File.OpenRead(archive)) if (!Convert.ToHexString(SHA256.HashData(stream)).Equals(ExpectedHash, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Повреждён словарь");
        var temporary = target + ".tmp"; using (var source = new GZipStream(File.OpenRead(archive), CompressionMode.Decompress)) using (var output = File.Create(temporary)) source.CopyTo(output);
        File.Move(temporary, target, true); return target;
    }
    private static byte[] Utf8(string value) => Encoding.UTF8.GetBytes(value + '\0');
    public void Dispose() { if (scoreQuery != 0) Sqlite.sqlite3_finalize(scoreQuery); if (protectionQuery != 0) Sqlite.sqlite3_finalize(protectionQuery); if (database != 0) Sqlite.sqlite3_close(database); }
    private static class Sqlite
    {
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_open_v2(byte[] name, out nint db, int flags, nint vfs);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_prepare_v2(nint db, byte[] sql, int length, out nint statement, nint tail);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_bind_int(nint statement, int index, int value);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_bind_text(nint statement, int index, byte[] value, int length, nint destructor);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_step(nint statement);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_column_int(nint statement, int column);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_reset(nint statement);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_clear_bindings(nint statement);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_finalize(nint statement);
        [DllImport("winsqlite3.dll")] internal static extern int sqlite3_close(nint db);
    }
}
