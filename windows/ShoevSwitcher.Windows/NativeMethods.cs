using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace ShoevSwitcher.Windows;

internal static class NativeMethods
{
    internal const int WhKeyboardLl = 13, WmKeyDown = 0x0100, WmSysKeyDown = 0x0104;
    internal const uint LlkhfInjected = 0x10, InputKeyboard = 1, KeyeventfKeyup = 2, KeyeventfUnicode = 4, WmInputLangChangeRequest = 0x0050, EmGetPasswordChar = 0x00D2, SmtoAbortIfHung = 0x0002;
    internal const ushort VkBack = 0x08;
    internal static readonly nuint SelfInputMarker = unchecked((nuint)0x53484F4556535749UL);
    internal delegate nint HookProc(int code, nint message, nint data);
    [StructLayout(LayoutKind.Sequential)] internal struct KbdLlHookStruct { internal uint vkCode, scanCode, flags, time; internal nuint extraInfo; }
    [StructLayout(LayoutKind.Sequential)] internal struct Input { internal uint type; internal InputUnion data; }
    [StructLayout(LayoutKind.Explicit)] internal struct InputUnion { [FieldOffset(0)] internal KeybdInput keyboard; }
    [StructLayout(LayoutKind.Sequential)] internal struct KeybdInput { internal ushort virtualKey, scanCode; internal uint flags, time; internal nuint extraInfo; }
    [StructLayout(LayoutKind.Sequential)] internal struct GuiThreadInfo { internal uint size, flags; internal nint active, focus, capture, menuOwner, moveSize, caret; internal int left, top, right, bottom; }

    [DllImport("user32.dll", SetLastError = true)] internal static extern nint SetWindowsHookEx(int id, HookProc proc, nint module, uint threadId);
    [DllImport("user32.dll")] internal static extern bool UnhookWindowsHookEx(nint hook);
    [DllImport("user32.dll")] internal static extern nint CallNextHookEx(nint hook, int code, nint message, nint data);
    [DllImport("kernel32.dll")] internal static extern nint GetModuleHandle(string? name);
    [DllImport("user32.dll")] internal static extern bool GetKeyboardState(byte[] state);
    [DllImport("user32.dll")] internal static extern nint GetKeyboardLayout(uint threadId);
    [DllImport("user32.dll")] internal static extern int ToUnicodeEx(uint vk, uint scan, byte[] state, [Out] StringBuilder buffer, int capacity, uint flags, nint layout);
    [DllImport("user32.dll")] internal static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(nint window, out uint processId);
    [DllImport("user32.dll", SetLastError = true)] internal static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] internal static extern bool GetGUIThreadInfo(uint threadId, ref GuiThreadInfo info);
    [DllImport("user32.dll", SetLastError = true)] internal static extern nint SendMessageTimeout(nint window, uint message, nint wParam, nint lParam, uint flags, uint timeout, out nint result);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern nint LoadKeyboardLayout(string id, uint flags);
    [DllImport("user32.dll")] internal static extern bool PostMessage(nint window, uint message, nint wParam, nint lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern int GetClassName(nint window, StringBuilder value, int maximum);

    internal static bool IsPasswordField()
    {
        var info = new GuiThreadInfo { size = (uint)Marshal.SizeOf<GuiThreadInfo>() };
        return GetGUIThreadInfo(0, ref info) && info.focus != 0
            && SendMessageTimeout(info.focus, EmGetPasswordChar, 0, 0, SmtoAbortIfHung, 50, out var result) != 0 && result != 0;
    }
    internal static bool HasFocusedTextInput()
    {
        var info = new GuiThreadInfo { size = (uint)Marshal.SizeOf<GuiThreadInfo>() };
        if (!GetGUIThreadInfo(0, ref info) || info.focus == 0) return false;
        var value = new StringBuilder(128); GetClassName(info.focus, value, value.Capacity);
        var name = value.ToString();
        return name.Contains("Edit", StringComparison.OrdinalIgnoreCase)
            || name.Contains("Rich", StringComparison.OrdinalIgnoreCase)
            || name.Contains("Scintilla", StringComparison.OrdinalIgnoreCase)
            || name.Contains("RenderWidget", StringComparison.OrdinalIgnoreCase);
    }
    internal static string ProcessName()
    {
        GetWindowThreadProcessId(GetForegroundWindow(), out var pid);
        try { return Process.GetProcessById((int)pid).ProcessName; } catch { return ""; }
    }
    internal static void SwitchLayout(Language language)
    {
        var layout = LoadKeyboardLayout(language == Language.English ? "00000409" : "00000419", 1);
        if (layout != 0) PostMessage(GetForegroundWindow(), WmInputLangChangeRequest, 0, layout);
    }
    internal static Language CurrentLanguage()
    {
        var thread = GetWindowThreadProcessId(GetForegroundWindow(), out _);
        var languageId = (ushort)((long)GetKeyboardLayout(thread) & 0xFFFF);
        return languageId == 0x0419 ? Language.Russian : Language.English;
    }
    internal static void Replace(int deleteUnits, string replacement, string delimiter)
    {
        var inputs = new List<Input>();
        for (var i = 0; i < deleteUnits; i++) AddKey(inputs, VkBack);
        foreach (var c in (replacement + delimiter).AsSpan()) AddUnicode(inputs, c);
        if (inputs.Count > 0) SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf<Input>());
    }
    private static void AddKey(List<Input> list, ushort key) { list.Add(Create(key, 0, 0)); list.Add(Create(key, 0, KeyeventfKeyup)); }
    private static void AddUnicode(List<Input> list, char c) { list.Add(Create(0, c, KeyeventfUnicode)); list.Add(Create(0, c, KeyeventfUnicode | KeyeventfKeyup)); }
    private static Input Create(ushort key, ushort scan, uint flags) => new() { type = InputKeyboard, data = new InputUnion { keyboard = new KeybdInput { virtualKey = key, scanCode = scan, flags = flags, extraInfo = SelfInputMarker } } };
}

internal sealed class KeyboardHook : IDisposable
{
    private readonly Func<KeyEvent, bool> handler; private readonly NativeMethods.HookProc callback; private nint hook;
    internal KeyboardHook(Func<KeyEvent, bool> handler) { this.handler = handler; callback = Callback; }
    internal void Start()
    {
        using var process = Process.GetCurrentProcess(); using var module = process.MainModule!;
        hook = NativeMethods.SetWindowsHookEx(NativeMethods.WhKeyboardLl, callback, NativeMethods.GetModuleHandle(module.ModuleName), 0);
        if (hook == 0) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    private nint Callback(int code, nint message, nint data)
    {
        if (code >= 0 && (message == NativeMethods.WmKeyDown || message == NativeMethods.WmSysKeyDown))
        {
            var raw = Marshal.PtrToStructure<NativeMethods.KbdLlHookStruct>(data);
            if (raw.extraInfo != NativeMethods.SelfInputMarker && handler(new KeyEvent(raw.vkCode, raw.scanCode))) return 1;
        }
        return NativeMethods.CallNextHookEx(hook, code, message, data);
    }
    public void Dispose() { if (hook != 0) NativeMethods.UnhookWindowsHookEx(hook); hook = 0; }
}

internal readonly record struct KeyEvent(uint VirtualKey, uint ScanCode)
{
    internal string Text()
    {
        var state = new byte[256]; if (!NativeMethods.GetKeyboardState(state)) return "";
        var thread = NativeMethods.GetWindowThreadProcessId(NativeMethods.GetForegroundWindow(), out _);
        var value = new StringBuilder(8); var count = NativeMethods.ToUnicodeEx(VirtualKey, ScanCode, state, value, value.Capacity, 0, NativeMethods.GetKeyboardLayout(thread));
        return count > 0 ? value.ToString(0, count) : "";
    }
}
