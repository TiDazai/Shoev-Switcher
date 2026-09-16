namespace ShoevSwitcher.Windows;

internal static class InputSelfTest
{
    internal static int Run()
    {
        var result = 1;
        using var lexicon = new Lexicon();
        var engine = new SwitcherEngine(lexicon, testMode: true);
        using var hook = new KeyboardHook(engine.HandleKey);
        using var form = new Form { Text = "Shoev Switcher input test", Size = new Size(360, 90), StartPosition = FormStartPosition.CenterScreen, ShowInTaskbar = false, TopMost = true };
        var field = new TextBox { Dock = DockStyle.Fill, Font = new Font("Segoe UI", 14) };
        form.Controls.Add(field);
        var send = new System.Windows.Forms.Timer { Interval = 200 };
        var verify = new System.Windows.Forms.Timer { Interval = 1200 };
        send.Tick += (_, _) => { send.Stop(); form.Activate(); form.BringToFront(); NativeMethods.SetForegroundWindow(form.Handle); field.Focus(); NativeMethods.SendTestText("ghbdtn "); verify.Start(); };
        verify.Tick += (_, _) => { verify.Stop(); File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "input-test-result.txt"), field.Text); result = field.Text == "привет " ? 0 : 1; form.Close(); };
        form.Shown += (_, _) => { hook.Start(); field.Focus(); send.Start(); };
        Application.Run(form);
        send.Dispose(); verify.Dispose();
        return result;
    }
}
