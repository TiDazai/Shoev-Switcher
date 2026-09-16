namespace ShoevSwitcher.Windows;

internal sealed class SettingsForm : Form
{
    private readonly Dictionary<string, CheckBox> options = new();
    private readonly ComboBox shortcut = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 240 };
    private readonly TextBox exclusions = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font("Consolas", 10) };

    internal SettingsForm(Icon icon)
    {
        Text = "Настройки Shoev Switcher"; Icon = icon; StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(760, 650); Size = new Size(820, 700); BackColor = Color.White;
        Controls.Add(BuildTabs()); Controls.Add(BuildBottom()); Controls.Add(BuildHeader());
        LoadValues();
    }

    private Control BuildHeader()
    {
        var header = new Panel { Dock = DockStyle.Top, Height = 112, BackColor = Branding.Burgundy };
        var logo = new PictureBox { Image = Image.FromFile(Path.Combine(AppContext.BaseDirectory, "app-icon.png")), SizeMode = PictureBoxSizeMode.Zoom, Bounds = new Rectangle(18, 10, 88, 88) };
        var title = new Label { Text = "Shoev Switcher", ForeColor = Branding.Platinum, Font = new Font("Segoe UI", 22, FontStyle.Bold), AutoSize = true, Location = new Point(122, 20) };
        var subtitle = new Label { Text = "Русская и английская раскладки под контролем", ForeColor = Color.FromArgb(225, 210, 215), Font = new Font("Segoe UI", 10), AutoSize = true, Location = new Point(125, 65) };
        header.Controls.AddRange([logo, title, subtitle]); return header;
    }
    private Control BuildTabs()
    {
        var tabs = new TabControl { Dock = DockStyle.Fill, Padding = new Point(14, 7) };
        tabs.TabPages.Add(BehaviorTab()); tabs.TabPages.Add(InterfaceTab()); tabs.TabPages.Add(PrivacyTab()); tabs.TabPages.Add(AboutTab()); return tabs;
    }
    private Control BuildBottom()
    {
        var panel = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 62, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(12) };
        var save = new Button { Text = "Сохранить", Width = 120, Height = 34, BackColor = Branding.Burgundy, ForeColor = Color.White, FlatStyle = FlatStyle.Flat };
        var cancel = new Button { Text = "Отмена", Width = 100, Height = 34 };
        save.Click += (_, _) => { Save(); DialogResult = DialogResult.OK; Close(); }; cancel.Click += (_, _) => Close(); panel.Controls.AddRange([save, cancel]); return panel;
    }
    private TabPage BehaviorTab()
    {
        var page = Page("Поведение"); var stack = Stack(); stack.Controls.Add(Section("Автоматическая работа"));
        stack.Controls.AddRange([Option("Enabled", "Shoev Switcher включён"), Option("Automatic", "Исправлять неверную раскладку автоматически"), Option("PhraseContext", "Учитывать предыдущие слова и язык фразы"), Option("ApplicationContext", "Учитывать привычный язык текущей программы"), Option("RememberLayout", "Запоминать раскладку отдельно для каждой программы")]);
        stack.Controls.Add(Section("Ручная конвертация")); stack.Controls.Add(Option("Manual", "Конвертировать текущее слово двойным Shift"));
        shortcut.Items.AddRange(["Двойной правый Shift", "Двойной левый Shift"]); stack.Controls.Add(shortcut);
        stack.Controls.Add(Option("Undo", "Отменять последнее автоисправление клавишей Backspace")); page.Controls.Add(stack); return page;
    }
    private TabPage InterfaceTab()
    {
        var page = Page("Интерфейс и обучение"); var stack = Stack(); stack.Controls.Add(Section("Интерфейс"));
        stack.Controls.AddRange([Option("HoverIndicator", "Показывать флаг активной раскладки рядом с курсором"), Option("Notifications", "Показывать уведомление «было → стало»")]);
        stack.Controls.Add(Section("Обучение")); stack.Controls.Add(Option("Learning", "Запоминать повторяющиеся ручные исправления"));
        stack.Controls.Add(Help("Словарь и все настройки находятся на этом компьютере. Подключение к интернету для работы не требуется.")); page.Controls.Add(stack); return page;
    }
    private TabPage PrivacyTab()
    {
        var page = Page("Дневник и исключения"); var table = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(22), RowCount = 7, ColumnCount = 1 };
        table.RowStyles.Add(new RowStyle(SizeType.AutoSize)); table.RowStyles.Add(new RowStyle(SizeType.AutoSize)); table.RowStyles.Add(new RowStyle(SizeType.AutoSize)); table.RowStyles.Add(new RowStyle(SizeType.AutoSize)); table.RowStyles.Add(new RowStyle(SizeType.AutoSize)); table.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        table.Controls.Add(Section("Локальный дневник")); table.Controls.Add(Option("Journal", "Сохранять исправления")); table.Controls.Add(Option("FullDiary", "Сохранять все завершённые слова"));
        table.Controls.Add(Section("Исключённые программы")); table.Controls.Add(Help("Имена процессов по одному в строке. Парольные поля всегда пропускаются.")); table.Controls.Add(exclusions); page.Controls.Add(table); return page;
    }
    private static TabPage AboutTab()
    {
        var page = Page("О программе"); var stack = Stack(); stack.Controls.Add(Section("Shoev Switcher"));
        stack.Controls.Add(Help("Shoev Switcher использует общий локальный словарь на 7,1 млн русских и английских слов.\n\nАвтоматическая и ручная конвертация • смена системной раскладки • локальная обработка.\n\nВерсия 0.5.2-alpha")); page.Controls.Add(stack); return page;
    }
    private CheckBox Option(string key, string text)
    {
        var value = new CheckBox { Text = text, AutoSize = true, Font = new Font("Segoe UI", 10), Margin = new Padding(4, 7, 4, 7) }; options[key] = value; return value;
    }
    private void LoadValues()
    {
        var defaults = new Dictionary<string, bool> { ["Enabled"] = true, ["Automatic"] = true, ["PhraseContext"] = true, ["ApplicationContext"] = true, ["RememberLayout"] = false, ["Manual"] = true, ["Undo"] = true, ["HoverIndicator"] = true, ["Notifications"] = true, ["Learning"] = true, ["Journal"] = true, ["FullDiary"] = false };
        foreach (var pair in options) pair.Value.Checked = SettingsStore.GetBool(pair.Key, defaults[pair.Key]);
        shortcut.SelectedIndex = SettingsStore.GetString("ManualSide", "Right") == "Left" ? 1 : 0; exclusions.Lines = SettingsStore.GetExclusions();
    }
    private void Save()
    {
        foreach (var pair in options) SettingsStore.SetBool(pair.Key, pair.Value.Checked);
        SettingsStore.SetString("ManualSide", shortcut.SelectedIndex == 1 ? "Left" : "Right"); SettingsStore.SetExclusions(exclusions.Lines);
    }
    private static Label Section(string text) => new() { Text = text, AutoSize = true, Font = new Font("Segoe UI Semibold", 13), ForeColor = Branding.BurgundyDark, Margin = new Padding(3, 10, 3, 11) };
    private static Label Help(string text) => new() { Text = text, AutoSize = true, MaximumSize = new Size(690, 0), Font = new Font("Segoe UI", 9), ForeColor = Color.DimGray, Margin = new Padding(4, 9, 4, 9) };
    private static FlowLayoutPanel Stack() => new() { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(22) };
    private static TabPage Page(string title) => new(title) { BackColor = Color.White, Padding = new Padding(8) };
}

internal sealed class JournalForm : Form
{
    internal JournalForm(Icon icon, JournalStore store)
    {
        Text = "Дневник и правила Shoev Switcher"; Icon = icon; StartPosition = FormStartPosition.CenterScreen; Size = new Size(940, 570); BackColor = Color.White;
        var title = new Label { Text = "Дневник и обучение", Dock = DockStyle.Top, Height = 52, Padding = new Padding(16, 14, 0, 0), Font = new Font("Segoe UI Semibold", 16), ForeColor = Branding.BurgundyDark };
        var tabs = new TabControl { Dock = DockStyle.Fill };
        var grid = new DataGridView { Dock = DockStyle.Fill, ReadOnly = true, AutoGenerateColumns = true, AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill, BackgroundColor = Color.White, BorderStyle = BorderStyle.None };
        grid.DataSource = store.Read().Select(x => new { Время = x.Time.ToString("g"), Приложение = x.Application, Было = x.Original, Стало = x.Replacement ?? "—", Событие = x.Kind, Язык = x.Language ?? "—" }).ToList();
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 56, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(10) };
        var clear = new Button { Text = "Очистить дневник", Width = 145, Height = 32 };
        clear.Click += (_, _) => { if (MessageBox.Show("Удалить все записи?", "Shoev Switcher", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes) { store.Clear(); grid.DataSource = null; } };
        buttons.Controls.Add(clear);
        var journalPage = new TabPage("Дневник") { BackColor = Color.White }; journalPage.Controls.Add(grid); journalPage.Controls.Add(buttons);
        var learningGrid = new DataGridView { Dock = DockStyle.Fill, ReadOnly = true, AutoGenerateColumns = true, AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill, BackgroundColor = Color.White, BorderStyle = BorderStyle.None };
        learningGrid.DataSource = PersonalRules.Read().Select(x => new { Было = x.Original, Стало = x.Replacement, Повторов = x.Count, Состояние = x.Learned ? "Выучено" : "Наблюдение" }).ToList();
        var learningButtons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 56, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(10) };
        var clearLearning = new Button { Text = "Очистить обучение", Width = 155, Height = 32 };
        clearLearning.Click += (_, _) => { if (MessageBox.Show("Удалить все выученные правила?", "Shoev Switcher", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes) { PersonalRules.Clear(); learningGrid.DataSource = null; } };
        learningButtons.Controls.Add(clearLearning);
        var learningPage = new TabPage("Обучение") { BackColor = Color.White }; learningPage.Controls.Add(learningGrid); learningPage.Controls.Add(learningButtons);
        tabs.TabPages.Add(journalPage); tabs.TabPages.Add(learningPage); Controls.Add(tabs); Controls.Add(title);
    }
}
