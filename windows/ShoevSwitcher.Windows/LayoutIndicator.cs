using System.Runtime.InteropServices;

namespace ShoevSwitcher.Windows;

internal sealed class LayoutIndicator : IDisposable
{
    private readonly Form window;
    private readonly Label label;
    private readonly System.Windows.Forms.Timer timer;

    internal LayoutIndicator()
    {
        label = new Label { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter, Font = new Font("Segoe UI Emoji", 13), BackColor = Color.FromArgb(235, 255, 255, 255) };
        window = new IndicatorWindow { FormBorderStyle = FormBorderStyle.None, ShowInTaskbar = false, TopMost = true, Size = new Size(42, 34), StartPosition = FormStartPosition.Manual, BackColor = Color.White, Opacity = 0.92 };
        window.Controls.Add(label);
        timer = new System.Windows.Forms.Timer { Interval = 250 };
        timer.Tick += (_, _) => Update();
    }
    internal void Start() { timer.Start(); RefreshVisibility(); }
    internal void RefreshVisibility() { if (!SettingsStore.GetBool("HoverIndicator", true)) window.Hide(); }
    private void Update()
    {
        if (!SettingsStore.GetBool("Enabled", true) || !SettingsStore.GetBool("HoverIndicator", true)
            || NativeMethods.ProcessName().StartsWith("Shoev Switcher", StringComparison.OrdinalIgnoreCase)
            || !NativeMethods.HasFocusedTextInput()) { window.Hide(); return; }
        NativeMethods.GetWindowThreadProcessId(NativeMethods.GetForegroundWindow(), out _);
        var point = Cursor.Position; window.Location = new Point(point.X + 18, point.Y + 20);
        label.Text = NativeMethods.CurrentLanguage() == Language.Russian ? "🇷🇺" : "🇬🇧";
        if (!window.Visible) window.Show();
    }
    public void Dispose() { timer.Stop(); timer.Dispose(); window.Dispose(); }

    private sealed class IndicatorWindow : Form
    {
        protected override bool ShowWithoutActivation => true;
        protected override CreateParams CreateParams
        {
            get { var value = base.CreateParams; value.ExStyle |= 0x08000000 | 0x00000080; return value; }
        }
    }
}
