using System.Drawing.Drawing2D;

namespace ShoevSwitcher.Windows;

internal static class Branding
{
    internal static readonly Color Burgundy = Color.FromArgb(124, 0, 42);
    internal static readonly Color BurgundyDark = Color.FromArgb(82, 0, 28);
    internal static readonly Color Platinum = Color.FromArgb(238, 234, 226);

    internal static Icon LoadIcon()
    {
        try
        {
            using var source = Image.FromFile(Path.Combine(AppContext.BaseDirectory, "app-icon.png"));
            using var bitmap = new Bitmap(64, 64);
            using (var graphics = Graphics.FromImage(bitmap))
            {
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.DrawImage(source, 0, 0, 64, 64);
            }
            return Icon.FromHandle(bitmap.GetHicon());
        }
        catch { return SystemIcons.Application; }
    }
}
