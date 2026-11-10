// VU3INI Android TV Cleaner - the wizard.
// Guides through CleanYourTV (https://github.com/Gathin23/cleanyourtv) from start to finish, offline:
//   1 Prepare the TV   2 Set up tools   3 Connect   4 Brand & model   5 What to keep
//   6 Clean the TV     7 Home screen    8 Finish & secure        + Maintenance & undo
// Everything runs the repo's own scripts with the bundled Python, JDK 17, Android SDK 34 and Gradle;
// nobody has to edit a file.
//
// C# 5 (the compiler built into Windows): no $"", ?. , nameof, expression bodies.
// Author: Sasanka Boruah, VU3INI  <hamvu3ini@gmail.com>

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("VU3INI Android TV Cleaner")]
[assembly: System.Reflection.AssemblyProduct("VU3INI Android TV Cleaner")]
[assembly: System.Reflection.AssemblyCompany("VU3INI")]
[assembly: System.Reflection.AssemblyCopyright("Sasanka Boruah, VU3INI")]
[assembly: System.Reflection.AssemblyVersion("2.0.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("2.0.0.0")]

namespace Vu3ini.AndroidTvCleaner
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            bool fromInstaller = false;
            foreach (string a in args) { if (a == "--setup") fromInstaller = true; }
            Application.Run(new MainForm(fromInstaller));
        }
    }

    internal sealed class CheckResult
    {
        public bool Ok;
        public string Detail;
        public CheckResult(bool ok, string detail) { Ok = ok; Detail = detail; }
    }

    internal sealed class BrandItem
    {
        public string Name;
        public int Count;
        public BrandItem(string n, int c) { Name = n; Count = c; }
        public override string ToString() { return Name + "  (" + Count + (Count == 1 ? " tested TV)" : " tested TVs)"); }
    }

    internal delegate bool Work();

    internal sealed class MainForm : Form
    {
        public const string AppName = "VU3INI Android TV Cleaner";
        public const string AppVersion = "2.0";
        public const string Email = "hamvu3ini@gmail.com";

        private const int P_PREP = 0, P_SETUP = 1, P_CONNECT = 2, P_MODEL = 3, P_KEEP = 4, P_CLEAN = 5, P_HOME = 6, P_FINISH = 7, P_MAINT = 8;
        private const int WizardSteps = 8;
        private static readonly string[] NavNames = new string[] {
            "Prepare the TV", "Set up tools", "Connect to the TV", "Brand and model", "What to keep",
            "Clean the TV", "New home screen", "Finish and secure", "Maintenance and undo", "About" };

        private static readonly Color Navy = Color.FromArgb(18, 53, 91);
        private static readonly Color Blue = Color.FromArgb(0, 102, 204);
        private static readonly Color Green = Color.FromArgb(0, 128, 60);
        private static readonly Color Red = Color.FromArgb(190, 30, 30);
        private static readonly Color Orange = Color.FromArgb(200, 110, 0);
        private static readonly Color Muted = Color.FromArgb(100, 100, 100);

        // Installed folder layout (the builder creates exactly this).
        private readonly string appDir, pyBase, jdk, sdk, gradleHome, repo, wheels, venvDir, venvPy, launcherDir, marker;
        private readonly string dataDir, listsDir, themeOut;
        private readonly Settings st;
        private readonly bool fromInstaller;

        // State
        private List<ExampleInfo> examples = new List<ExampleInfo>();
        private TvInfo tv;
        private ExampleInfo chosenExample;
        private string chosenSource = "";      // full path of the tested (or audit) list the user picked
        private string chosenLabel = "";
        private List<ListEntry> entries;
        private readonly bool[] done = new bool[WizardSteps];
        private int current = -1;
        private volatile bool busy;
        private bool setupAutoRan;
        private bool suppressEvents;

        // Shell
        private ListBox nav;
        private Panel host;
        private readonly Control[] pages = new Control[9];
        private Button btnBack, btnNext;
        private RichTextBox log;
        private ProgressBar busyBar;
        private Label statusLbl;
        private readonly List<Control> wraps = new List<Control>();

        // Step 1
        private CheckBox p1Dev, p1Usb, p1Net, p1Privacy, p1Confirm;
        private TextBox p1Ip;
        private Label p1PingResult;
        // Step 2
        private ListView checks;
        private Button btnSetup;
        private Label p2Result;
        // Step 3
        private Label p3Ip, p3Result;
        private ListView p3Info;
        // Step 4
        private ComboBox p4Brand, p4Variant;
        private ListView p4Models;
        private Label p4Suggest, p4Using;
        private Button p4UseSuggestion;
        private TextBox p4Notes;
        private ExampleInfo suggested;
        // Step 5
        private ListView p5List;
        private CheckBox p5HideMissing;
        private readonly List<CheckBox> p5Keep = new List<CheckBox>();
        private Label p5Summary, p5Title;
        // Step 6
        private Label p6Summary, p6Result;
        private Button p6Run;
        // Step 7
        private CheckBox p7Install, p7InputKey, p7HomeKey;
        private ComboBox p7LiveTv, p7Theme;
        private NumericUpDown p7Columns;
        private TextBox p7Greeting;
        private CheckedListBox p7Dock;
        private PictureBox p7Preview;
        private Label p7Result;
        // Step 8
        private CheckBox p8Off, p8Reboot;
        private Label p8Result;
        // Maintenance
        private TextBox pmIp;
        private Label pmList, pmResult;
        private readonly List<Button> pmNeedsList = new List<Button>();

        private static readonly string[] CheckNames = new string[] {
            "Bundled Python 3", "Eclipse Temurin JDK (17-22)", "Android SDK Platform 34", "Android SDK Build-Tools 34",
            "Android SDK Platform-Tools (adb)", "Android SDK licences", "CleanYourTV repository", "Gradle 8.9 distribution",
            "Gradle offline dependency cache", "launcher\\local.properties (sdk.dir)", "Python venv + adb-shell, rsa, cryptography" };

        public MainForm(bool fromInstaller)
        {
            this.fromInstaller = fromInstaller;
            appDir = Path.GetFullPath(Application.StartupPath);
            pyBase = Path.Combine(appDir, @"python\python.exe");
            jdk = Path.Combine(appDir, "jdk");
            sdk = Path.Combine(appDir, "android-sdk");
            gradleHome = Path.Combine(appDir, "gradle-home");
            repo = Path.Combine(appDir, "cleanyourtv");
            wheels = Path.Combine(appDir, "wheels");
            venvDir = Path.Combine(repo, @"tools\venv");
            venvPy = Path.Combine(venvDir, @"Scripts\python.exe");
            launcherDir = Path.Combine(repo, "launcher");
            marker = Path.Combine(appDir, "setup-done.txt");
            dataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), @"VU3INI\AndroidTVCleaner");
            listsDir = Path.Combine(dataDir, "lists");
            themeOut = Path.Combine(dataDir, "theme");
            st = new Settings(Path.Combine(dataDir, "settings.txt"));
            BuildShell();
        }

        private string TvIp { get { return st.Get("tv_ip"); } }

        // ================================================================== shell

        private void BuildShell()
        {
            Text = AppName;
            Font = new Font("Segoe UI", 9.75f);
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(1180, 800);
            MinimumSize = new Size(980, 680);
            BackColor = Color.White;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            Panel header = new Panel();
            header.Dock = DockStyle.Top;
            header.Height = 100;
            header.BackColor = Navy;
            // The VU3INI logo, top-left on every screen, on a white card (the artwork has a white background).
            Panel logoCard = new Panel();
            logoCard.BackColor = Color.White;
            logoCard.Size = new Size(88, 88);
            logoCard.Location = new Point(8, 6);
            logoCard.Paint += delegate (object s, PaintEventArgs pe)
            {
                pe.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                using (Pen p = new Pen(Color.FromArgb(120, 170, 220), 2)) pe.Graphics.DrawRectangle(p, 1, 1, logoCard.Width - 3, logoCard.Height - 3);
            };
            PictureBox logo = new PictureBox();
            logo.SizeMode = PictureBoxSizeMode.Zoom;
            logo.Size = new Size(80, 80);
            logo.Location = new Point(4, 4);
            logo.BackColor = Color.White;
            logo.Image = LoadLogo();
            logo.Cursor = Cursors.Hand;
            logo.Click += delegate { ShowAbout(); };
            logoCard.Controls.Add(logo);
            Label title = new Label();
            title.Text = AppName;
            title.ForeColor = Color.White;
            title.Font = new Font("Segoe UI Semibold", 18f);
            title.AutoSize = true;
            title.Location = new Point(108, 14);
            Label sub = new Label();
            sub.Text = "Clean the ads, tracking and clutter off your Android TV, step by step. Everything runs offline; nothing is uninstalled.";
            sub.ForeColor = Color.FromArgb(200, 220, 240);
            sub.AutoSize = true;
            sub.Location = new Point(111, 56);
            header.Controls.Add(logoCard);
            header.Controls.Add(title);
            header.Controls.Add(sub);

            nav = new ListBox();
            nav.Dock = DockStyle.Left;
            nav.Width = 250;
            nav.BorderStyle = BorderStyle.None;
            nav.BackColor = Color.FromArgb(243, 246, 250);
            nav.DrawMode = DrawMode.OwnerDrawFixed;
            nav.ItemHeight = 38;
            nav.IntegralHeight = false;
            nav.Font = new Font("Segoe UI", 10f);
            foreach (string n in NavNames) nav.Items.Add(n);
            nav.DrawItem += NavDraw;
            nav.MouseDown += NavClick;

            host = new Panel();
            host.Dock = DockStyle.Fill;
            host.BackColor = Color.White;

            log = new RichTextBox();
            log.ReadOnly = true;
            log.Dock = DockStyle.Fill;
            log.Font = new Font("Consolas", 9f);
            log.BackColor = Color.FromArgb(250, 250, 250);
            log.BorderStyle = BorderStyle.None;
            log.WordWrap = false;

            SplitContainer split = new SplitContainer();
            split.Dock = DockStyle.Fill;
            split.Orientation = Orientation.Horizontal;
            split.Panel1.Controls.Add(host);
            Label logTitle = new Label();
            logTitle.Text = "  Activity log";
            logTitle.Dock = DockStyle.Top;
            logTitle.Height = 20;
            logTitle.ForeColor = Muted;
            logTitle.BackColor = Color.FromArgb(240, 240, 240);
            split.Panel2.Controls.Add(log);
            split.Panel2.Controls.Add(logTitle);
            split.FixedPanel = FixedPanel.Panel2;

            Panel footer = new Panel();
            footer.Dock = DockStyle.Bottom;
            footer.Height = 50;
            footer.BackColor = Color.FromArgb(243, 246, 250);
            btnBack = new Button();
            btnBack.Text = "< Back";
            btnBack.Size = new Size(110, 32);
            btnBack.Anchor = AnchorStyles.Right | AnchorStyles.Top;
            btnNext = new Button();
            btnNext.Text = "Next >";
            btnNext.Size = new Size(150, 32);
            btnNext.Anchor = AnchorStyles.Right | AnchorStyles.Top;
            StylePrimary(btnNext);
            btnBack.Click += delegate { GoBack(); };
            btnNext.Click += delegate { GoNext(); };
            busyBar = new ProgressBar();
            busyBar.Style = ProgressBarStyle.Marquee;
            busyBar.MarqueeAnimationSpeed = 0;
            busyBar.Size = new Size(160, 10);
            busyBar.Location = new Point(14, 20);
            busyBar.Visible = false;
            statusLbl = new Label();
            statusLbl.AutoSize = true;
            statusLbl.Location = new Point(184, 16);
            statusLbl.ForeColor = Muted;
            footer.Controls.Add(busyBar);
            footer.Controls.Add(statusLbl);
            footer.Controls.Add(btnBack);
            footer.Controls.Add(btnNext);
            footer.Resize += delegate
            {
                btnNext.Location = new Point(footer.ClientSize.Width - btnNext.Width - 14, 9);
                btnBack.Location = new Point(btnNext.Left - btnBack.Width - 8, 9);
            };

            Controls.Add(split);
            Controls.Add(footer);
            Controls.Add(nav);
            Controls.Add(header);

            pages[P_PREP] = BuildPrep();
            pages[P_SETUP] = BuildSetup();
            pages[P_CONNECT] = BuildConnect();
            pages[P_MODEL] = BuildModel();
            pages[P_KEEP] = BuildKeep();
            pages[P_CLEAN] = BuildClean();
            pages[P_HOME] = BuildHome();
            pages[P_FINISH] = BuildFinish();
            pages[P_MAINT] = BuildMaint();
            foreach (Control p in pages) { p.Visible = false; host.Controls.Add(p); }

            Shown += delegate
            {
                try { split.SplitterDistance = Math.Max(300, split.Height - 150); } catch { }
                OnFirstShown();
            };
        }

        private void NavDraw(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            Graphics g = e.Graphics;
            bool isCurrent = e.Index == current;
            bool reachable = CanOpen(e.Index);
            Color back = isCurrent ? Color.FromArgb(214, 230, 248) : nav.BackColor;
            using (Brush b = new SolidBrush(back)) g.FillRectangle(b, e.Bounds);
            if (isCurrent) using (Brush b = new SolidBrush(Blue)) g.FillRectangle(b, e.Bounds.X, e.Bounds.Y, 4, e.Bounds.Height);
            if (e.Index == P_MAINT)
                using (Pen p = new Pen(Color.FromArgb(210, 215, 222))) g.DrawLine(p, e.Bounds.X + 12, e.Bounds.Y + 1, e.Bounds.Right - 12, e.Bounds.Y + 1);
            string badge;
            Color badgeColor;
            if (e.Index < WizardSteps)
            {
                badge = done[e.Index] ? "\u2713" : (e.Index + 1).ToString();
                badgeColor = done[e.Index] ? Green : (reachable ? Blue : Color.FromArgb(170, 170, 170));
            }
            else
            {
                badge = e.Index == P_MAINT ? "\u2692" : "i";
                badgeColor = Navy;
            }
            Rectangle circle = new Rectangle(e.Bounds.X + 14, e.Bounds.Y + 8, 22, 22);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Brush b = new SolidBrush(badgeColor)) g.FillEllipse(b, circle);
            using (Font f = new Font("Segoe UI Semibold", 9f))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                g.DrawString(badge, f, Brushes.White, circle, sf);
            }
            Color fore = reachable ? Color.FromArgb(30, 30, 30) : Color.FromArgb(160, 160, 160);
            using (Font f = new Font("Segoe UI", 10f, isCurrent ? FontStyle.Bold : FontStyle.Regular))
            using (Brush b = new SolidBrush(fore))
                g.DrawString(nav.Items[e.Index].ToString(), f, b, e.Bounds.X + 46, e.Bounds.Y + 10);
        }

        private void NavClick(object sender, MouseEventArgs e)
        {
            if (busy) return;
            int i = nav.IndexFromPoint(e.Location);
            if (i < 0) return;
            if (i == NavNames.Length - 1) { ShowAbout(); return; }
            if (!CanOpen(i))
            {
                SetStatus("Finish the earlier steps first.");
                return;
            }
            ShowPage(i);
        }

        private bool CanOpen(int i)
        {
            if (i >= P_MAINT) return true;
            for (int k = 0; k < i; k++) if (!done[k]) return false;
            return true;
        }

        private void ShowPage(int i)
        {
            if (current == P_KEEP && i != P_KEEP && entries != null && Core.CountDisable(entries) > 0) SaveChoicesAndGenerate();
            if (current >= 0 && current < pages.Length) pages[current].Visible = false;
            current = i;
            pages[i].Visible = true;
            pages[i].BringToFront();
            FitWraps();
            OnEnter(i);
            FitWraps();
            RefreshNav();
        }

        private void RefreshNav()
        {
            nav.Invalidate();
            btnBack.Visible = current > 0 && current < P_MAINT;
            btnNext.Visible = current < P_MAINT;
            if (current >= 0 && current < WizardSteps)
            {
                btnNext.Text = current == P_FINISH ? "Finish" : (current == P_KEEP ? "Save choices  >" : "Next  >");
                btnNext.Enabled = !busy && done[current];
            }
            btnBack.Enabled = !busy;
        }

        private void GoBack()
        {
            if (busy || current <= 0) return;
            ShowPage(current - 1);
        }

        private void GoNext()
        {
            if (busy || current < 0 || current >= WizardSteps || !done[current]) return;
            if (current == P_KEEP && !SaveChoicesAndGenerate()) return;
            if (current == P_FINISH)
            {
                st.SetBool("finished", true);
                MessageBox.Show(this, "All done. Your TV is clean and secure.\r\n\r\nKeep this app: 'Maintenance and undo' re-applies your choices after a TV firmware update, and can put everything back if you ever want.",
                    AppName, MessageBoxButtons.OK, MessageBoxIcon.Information);
                ShowPage(P_MAINT);
                return;
            }
            ShowPage(current + 1);
        }

        private void MarkDone(int step, bool value)
        {
            done[step] = value;
            UI(delegate { RefreshNav(); });
        }

        // ================================================================== page helpers

        private TableLayoutPanel NewPage(string title, string intro)
        {
            TableLayoutPanel t = new TableLayoutPanel();
            t.Dock = DockStyle.Fill;
            t.ColumnCount = 1;
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            t.Padding = new Padding(22, 14, 22, 10);
            t.AutoScroll = true;
            t.GrowStyle = TableLayoutPanelGrowStyle.AddRows;
            Label h = new Label();
            h.Text = title;
            h.Font = new Font("Segoe UI Semibold", 15f);
            h.ForeColor = Navy;
            h.AutoSize = true;
            h.Margin = new Padding(0, 0, 0, 6);
            AddRow(t, h);
            if (!string.IsNullOrEmpty(intro)) AddRow(t, Wrap(intro, Color.FromArgb(40, 40, 40)));
            t.Resize += delegate { FitWraps(); };
            return t;
        }

        private static void AddRow(TableLayoutPanel t, Control c)
        {
            t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            t.Controls.Add(c, 0, t.RowStyles.Count - 1);
        }

        private static void AddFillRow(TableLayoutPanel t, Control c)
        {
            t.AutoScroll = false;
            c.Dock = DockStyle.Fill;
            t.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            t.Controls.Add(c, 0, t.RowStyles.Count - 1);
        }

        private Label Wrap(string text, Color color)
        {
            Label l = new Label();
            l.Text = text;
            l.AutoSize = true;
            l.ForeColor = color;
            l.Margin = new Padding(0, 3, 0, 6);
            l.UseMnemonic = false;
            wraps.Add(l);
            return l;
        }

        private CheckBox WrapCheck(string text, bool bold)
        {
            CheckBox c = new CheckBox();
            c.Text = text;
            c.AutoSize = true;
            c.Margin = new Padding(0, 6, 0, 6);
            if (bold) c.Font = new Font("Segoe UI Semibold", 10.5f);
            c.UseMnemonic = false;
            c.TextAlign = ContentAlignment.TopLeft;
            c.CheckAlign = ContentAlignment.TopLeft;
            wraps.Add(c);
            return c;
        }

        private void FitWraps()
        {
            foreach (Control c in wraps)
            {
                Control page = c.Parent;
                while (page != null && page.Parent != host) page = page.Parent;
                if (page == null || !page.Visible) continue;
                int w = Math.Max(320, page.ClientSize.Width - 70);
                bool box = c is CheckBox;
                Size m = TextRenderer.MeasureText(c.Text.Length == 0 ? " " : c.Text, c.Font, new Size(w - (box ? 26 : 4), 0),
                    TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
                c.AutoSize = false;
                c.Size = new Size(w, m.Height + (box ? 8 : 4));
            }
        }

        private static Button Btn(string text)
        {
            Button b = new Button();
            b.Text = text;
            b.AutoSize = true;
            b.Padding = new Padding(8, 3, 8, 3);
            b.Margin = new Padding(0, 4, 8, 4);
            return b;
        }

        private static void StylePrimary(Button b)
        {
            b.BackColor = Blue;
            b.ForeColor = Color.White;
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderSize = 0;
            b.Font = new Font("Segoe UI Semibold", 10f);
        }

        private static FlowLayoutPanel Row(params Control[] cs)
        {
            FlowLayoutPanel f = new FlowLayoutPanel();
            f.AutoSize = true;
            f.WrapContents = true;
            f.Margin = new Padding(0, 2, 0, 2);
            f.Dock = DockStyle.Top;
            foreach (Control c in cs) f.Controls.Add(c);
            return f;
        }

        private static Label Lbl(string text)
        {
            Label l = new Label();
            l.Text = text;
            l.AutoSize = true;
            l.Margin = new Padding(0, 9, 6, 3);
            l.UseMnemonic = false;
            return l;
        }

        private void SetResult(Label l, string text, Color c)
        {
            l.Text = text;
            l.ForeColor = c;
            if (wraps.Contains(l)) FitWraps();
        }

        private Image LoadLogo()
        {
            string p = Path.Combine(appDir, @"assets\vu3ini-logo.png");
            try
            {
                if (File.Exists(p)) using (Image src = Image.FromFile(p)) { return new Bitmap(src); }
            }
            catch { }
            Bitmap bmp = new Bitmap(152, 152);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (Brush b = new SolidBrush(Blue)) g.FillEllipse(b, 4, 4, 144, 144);
                using (Pen pen = new Pen(Color.White, 5)) g.DrawEllipse(pen, 8, 8, 136, 136);
                using (Font f = new Font("Segoe UI Black", 25f, FontStyle.Bold))
                using (StringFormat sf = new StringFormat())
                {
                    sf.Alignment = StringAlignment.Center;
                    sf.LineAlignment = StringAlignment.Center;
                    g.DrawString("VU3INI", f, Brushes.White, new RectangleF(0, 0, 152, 152), sf);
                }
            }
            return bmp;
        }

        private static Image LoadImageCopy(string path)
        {
            try
            {
                if (File.Exists(path)) using (Image src = Image.FromFile(path)) { return new Bitmap(src); }
            }
            catch { }
            return null;
        }

        // ================================================================== Step 1: prepare the TV

        private Control BuildPrep()
        {
            TableLayoutPanel t = NewPage("Step 1 - Prepare your TV",
                "Do these on the TV with its remote, then tick each one. Nothing on the TV is changed until step 6, and everything can be undone later.");
            p1Dev = WrapCheck("1.  Turn on Developer options: Settings > Device Preferences > About. Move to 'Build' and press OK seven times, until the TV says you are now a developer.", false);
            p1Usb = WrapCheck("2.  Turn on USB debugging: go back to Settings > Device Preferences > Developer options and switch on 'USB debugging'. On OnePlus and most Android TVs this alone allows the PC to connect over the network; no cable is needed.", false);
            p1Net = WrapCheck("3.  The TV and this PC are on the same home network (Wi-Fi or LAN cable), and the TV stays switched on.", false);
            p1Privacy = WrapCheck("Optional, recommended now: turn off 'Usage & diagnostics' and reset or opt out of the advertising ID (Settings > Device Preferences > About or Google > Ads). On some TVs these pages disappear after cleaning.", false);
            p1Privacy.ForeColor = Muted;
            AddRow(t, p1Dev);
            AddRow(t, p1Usb);
            AddRow(t, p1Net);
            AddRow(t, p1Privacy);
            AddRow(t, Wrap("4.  Type the TV's IP address. Find it on the TV under Settings > Network & Internet > (your network), for example 192.168.1.50.", Color.Black));
            p1Ip = new TextBox();
            p1Ip.Width = 170;
            p1Ip.Margin = new Padding(0, 5, 8, 3);
            p1Ip.Font = new Font("Segoe UI", 11f);
            Button ping = Btn("Check the TV is reachable");
            p1PingResult = Lbl("");
            AddRow(t, Row(Lbl("TV IP address:"), p1Ip, ping, p1PingResult));
            AddRow(t, Wrap("When the PC first connects (step 3), the TV shows 'Allow USB debugging?'. Tick 'Always allow from this computer' and press OK.", Muted));
            p1Confirm = WrapCheck("I have completed Step 1 on my TV - go ahead to the next step", true);
            p1Confirm.ForeColor = Navy;
            AddRow(t, p1Confirm);

            p1Dev.Checked = st.GetBool("s1_dev");
            p1Usb.Checked = st.GetBool("s1_usb");
            p1Net.Checked = st.GetBool("s1_net");
            p1Privacy.Checked = st.GetBool("s1_privacy");
            p1Ip.Text = TvIp;
            p1Confirm.Checked = st.GetBool("step1_done");
            EventHandler changed = delegate { Step1Changed(); };
            p1Dev.CheckedChanged += changed;
            p1Usb.CheckedChanged += changed;
            p1Net.CheckedChanged += changed;
            p1Privacy.CheckedChanged += changed;
            p1Confirm.CheckedChanged += changed;
            p1Ip.TextChanged += changed;
            ping.Click += delegate { PingTv(); };
            UpdateStep1Done();
            return t;
        }

        private static bool ValidIp(string ip)
        {
            IPAddress a;
            string[] parts = ip.Split('.');
            return parts.Length == 4 && IPAddress.TryParse(ip, out a) && a.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork;
        }

        private void Step1Changed()
        {
            if (suppressEvents) return;
            st.SetBool("s1_dev", p1Dev.Checked);
            st.SetBool("s1_usb", p1Usb.Checked);
            st.SetBool("s1_net", p1Net.Checked);
            st.SetBool("s1_privacy", p1Privacy.Checked);
            string ip = p1Ip.Text.Trim();
            if (ValidIp(ip) && ip != TvIp)
            {
                st.Set("tv_ip", ip);
                tv = null;
                done[P_CONNECT] = false;
                if (pmIp != null) pmIp.Text = ip;
            }
            p1Ip.BackColor = ip.Length == 0 || ValidIp(ip) ? SystemColors.Window : Color.FromArgb(255, 230, 230);
            if (p1Confirm.Checked && !(p1Dev.Checked && p1Usb.Checked && p1Net.Checked && ValidIp(ip)))
            {
                SetStatus("Tick steps 1 to 3 and type a valid IP address first.");
                suppressEvents = true;
                p1Confirm.Checked = false;
                suppressEvents = false;
            }
            st.SetBool("step1_done", p1Confirm.Checked);
            UpdateStep1Done();
            RefreshNav();
        }

        private void UpdateStep1Done()
        {
            done[P_PREP] = p1Confirm.Checked && p1Dev.Checked && p1Usb.Checked && p1Net.Checked && ValidIp(p1Ip.Text.Trim());
        }

        private void PingTv()
        {
            string ip = p1Ip.Text.Trim();
            if (!ValidIp(ip)) { SetResult(p1PingResult, "Type a valid IP address first.", Red); return; }
            SetResult(p1PingResult, "Checking...", Muted);
            Thread th = new Thread(delegate ()
            {
                string text;
                Color color;
                try
                {
                    using (Ping p = new Ping())
                    {
                        PingReply r = p.Send(ip, 2000);
                        if (r.Status == IPStatus.Success) { text = "Reachable (" + r.RoundtripTime + " ms)."; color = Green; }
                        else { text = "No reply. That is normal for some TVs; step 3 tests the real connection."; color = Orange; }
                    }
                }
                catch (Exception ex) { text = "Could not check: " + ex.Message; color = Orange; }
                UI(delegate { SetResult(p1PingResult, text, color); });
            });
            th.IsBackground = true;
            th.Start();
        }

        // ================================================================== Step 2: tools

        private Control BuildSetup()
        {
            TableLayoutPanel t = NewPage("Step 2 - Set up the tools",
                "Everything needed is already inside this app's folder: Python, the Java JDK 17, the Android SDK 34, Gradle and CleanYourTV with its tested lists. This step checks each part and finishes the setup. No internet is used.");
            checks = new ListView();
            checks.View = View.Details;
            checks.FullRowSelect = true;
            checks.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            checks.Columns.Add("Component", 300);
            checks.Columns.Add("Status", 80);
            checks.Columns.Add("Details", 460);
            checks.Height = 270;
            checks.Dock = DockStyle.Top;
            foreach (string n in CheckNames)
            {
                ListViewItem it = new ListViewItem(n);
                it.SubItems.Add("...");
                it.SubItems.Add("");
                checks.Items.Add(it);
            }
            AddRow(t, checks);
            btnSetup = Btn("Run the setup again");
            Button recheck = Btn("Re-check");
            Button build = Btn("Optional: offline test build of the home screen");
            btnSetup.Click += delegate { RunAsync("Setting up the tools", delegate { return DoSetup(); }, null); };
            recheck.Click += delegate { RunAsync("Checking", delegate { return RecheckAll(); }, null); };
            build.Click += delegate { RunAsync("Building the home screen offline", delegate { return TestBuild(); }, null); };
            AddRow(t, Row(btnSetup, recheck, build));
            p2Result = Wrap("", Muted);
            p2Result.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, p2Result);
            if (appDir.IndexOf(' ') >= 0)
                AddRow(t, Wrap("Warning: this app is installed in a folder whose path has spaces. Gradle and the Android SDK prefer a path without spaces; reinstall to C:\\VU3INI\\ATVCleaner if the setup fails.", Orange));
            return t;
        }

        // ================================================================== Step 3: connect

        private Control BuildConnect()
        {
            TableLayoutPanel t = NewPage("Step 3 - Connect to the TV",
                "The app connects to the TV over your network and reads its model and installed apps. Nothing on the TV is changed.");
            p3Ip = Lbl("");
            p3Ip.Font = new Font("Segoe UI Semibold", 10.5f);
            Button change = Btn("Change IP");
            change.Click += delegate { ShowPage(P_PREP); };
            AddRow(t, Row(Lbl("TV IP address:"), p3Ip, change));
            Button connect = Btn("Connect to the TV");
            StylePrimary(connect);
            connect.Click += delegate { ConnectTv(); };
            AddRow(t, Row(connect));
            AddRow(t, Wrap("Watch the TV: when it asks 'Allow USB debugging?', tick 'Always allow from this computer' and press OK. If the question timed out, press Connect again.", Orange));
            p3Result = Wrap("", Muted);
            p3Result.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, p3Result);
            p3Info = new ListView();
            p3Info.View = View.Details;
            p3Info.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            p3Info.FullRowSelect = true;
            p3Info.Columns.Add("Your TV", 220);
            p3Info.Columns.Add("", 520);
            AddFillRow(t, p3Info);
            return t;
        }

        private void ConnectTv()
        {
            string ip = TvIp;
            if (!ValidIp(ip)) { ShowPage(P_PREP); return; }
            if (!File.Exists(venvPy)) { MessageBox.Show(this, "Finish step 2 first.", AppName); return; }
            SetResult(p3Result, "Connecting to " + ip + " ... look at the TV and allow the connection.", Orange);
            TvInfo found = null;
            RunAsync("Connecting to the TV", delegate
            {
                StringBuilder outp = new StringBuilder();
                string cmds = string.Join("\n", Core.ProbeCommands) + "\n";
                Log("Reading the TV (model, installed apps). Nothing is changed.", Navy);
                int rc = Run(venvPy, "-I tools\\tv.py --batch", repo, 180, outp, false, cmds);
                if (rc != 0)
                {
                    Log(outp.ToString().Trim(), Red);
                    return false;
                }
                found = Core.ParseProbe(outp.ToString());
                return found.Model.Length > 0 || found.HasPackages;
            }, delegate (bool ok)
            {
                if (!ok || found == null)
                {
                    SetResult(p3Result, "Could not connect. Check: TV switched on and awake, same network, USB debugging on, IP correct; then press Connect again and allow the prompt on the TV.", Red);
                    MarkDone(P_CONNECT, false);
                    return;
                }
                tv = found;
                st.Set("tv_model", tv.Model);
                st.Set("tv_device", tv.Device);
                st.Set("tv_manufacturer", tv.Manufacturer);
                foreach (string s in Core.KnownStockLaunchers)
                    if (tv.HomePackage == s) st.Set("stock_launcher", s);
                if (tv.HomePackage == Core.LauncherPackage) st.SetBool("launcher_installed", true);
                ShowTvInfo();
                SetResult(p3Result, "Connected to " + (tv.Manufacturer + " " + tv.Model).Trim() + ". Press Next.", Green);
                Log("Connected: " + tv.Manufacturer + " " + tv.Model + " (" + tv.Device + "), Android " + tv.Android + ", " + tv.Installed.Count + " apps.", Green);
                MarkDone(P_CONNECT, true);
            });
        }

        private void ShowTvInfo()
        {
            p3Info.Items.Clear();
            if (tv == null) return;
            AddInfo("Manufacturer", tv.Manufacturer);
            AddInfo("Model", tv.Model);
            AddInfo("Device codename", tv.Device);
            AddInfo("Android version", tv.Android + (tv.Sdk.Length > 0 ? "  (API " + tv.Sdk + ")" : ""));
            AddInfo("Firmware", tv.Firmware);
            AddInfo("Current home screen app", tv.HomePackage);
            AddInfo("Installed apps and services", tv.Installed.Count.ToString());
            AddInfo("Already disabled", tv.Disabled.Count.ToString());
            AddInfo("Apps with a TV launcher icon", tv.Leanback.Count.ToString());
        }

        private void AddInfo(string k, string v)
        {
            ListViewItem it = new ListViewItem(k);
            it.SubItems.Add(v);
            p3Info.Items.Add(it);
        }

        // ================================================================== Step 4: brand and model

        private Control BuildModel()
        {
            TableLayoutPanel t = NewPage("Step 4 - Choose your TV's brand and model",
                "CleanYourTV has lists tested on hundreds of TVs. Pick the one for your TV; the app suggests it from what it read in step 3.");
            p4Suggest = Lbl("");
            p4Suggest.ForeColor = Green;
            p4UseSuggestion = Btn("Use the suggestion");
            p4UseSuggestion.Click += delegate { if (suggested != null) SelectExample(suggested, true); };
            AddRow(t, Row(p4Suggest, p4UseSuggestion));
            p4Brand = new ComboBox();
            p4Brand.DropDownStyle = ComboBoxStyle.DropDownList;
            p4Brand.Width = 320;
            p4Brand.MaxDropDownItems = 25;
            p4Brand.Margin = new Padding(0, 5, 8, 3);
            p4Brand.SelectedIndexChanged += delegate { if (!suppressEvents) FillModels(null); };
            AddRow(t, Row(Lbl("Brand:"), p4Brand));
            p4Models = new ListView();
            p4Models.View = View.Details;
            p4Models.FullRowSelect = true;
            p4Models.HideSelection = false;
            p4Models.MultiSelect = false;
            p4Models.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            p4Models.Columns.Add("Tested TV model", 560);
            p4Models.Columns.Add("Software", 200);
            p4Models.Columns.Add("Lists", 60);
            p4Models.SelectedIndexChanged += delegate
            {
                if (suppressEvents || p4Models.SelectedItems.Count == 0) return;
                SelectExample(p4Models.SelectedItems[0].Tag as ExampleInfo, false);
            };
            p4Variant = new ComboBox();
            p4Variant.DropDownStyle = ComboBoxStyle.DropDownList;
            p4Variant.Width = 320;
            p4Variant.Margin = new Padding(0, 5, 8, 3);
            p4Variant.SelectedIndexChanged += delegate
            {
                if (suppressEvents || chosenExample == null || p4Variant.SelectedItem == null) return;
                ChooseSource(chosenExample, p4Variant.SelectedItem.ToString());
            };
            p4Notes = new TextBox();
            p4Notes.Multiline = true;
            p4Notes.ReadOnly = true;
            p4Notes.ScrollBars = ScrollBars.Vertical;
            p4Notes.Height = 96;
            p4Notes.Dock = DockStyle.Top;
            p4Notes.BackColor = Color.FromArgb(250, 250, 250);
            p4Using = Lbl("");
            p4Using.Font = new Font("Segoe UI Semibold", 10f);

            Button audit = Btn("My TV is not listed: build a list from a privacy audit of my TV");
            audit.Click += delegate { BuildAuditList(); };

            TableLayoutPanel lower = new TableLayoutPanel();
            lower.ColumnCount = 1;
            lower.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            lower.AutoSize = true;
            lower.Dock = DockStyle.Bottom;
            AddRow(lower, Row(Lbl("List version:"), p4Variant));
            AddRow(lower, Lbl("What the tested list does on that TV:"));
            AddRow(lower, p4Notes);
            AddRow(lower, p4Using);
            AddRow(lower, Row(audit));

            Panel mid = new Panel();
            mid.Controls.Add(p4Models);
            mid.Controls.Add(lower);
            p4Models.Dock = DockStyle.Fill;
            AddFillRow(t, mid);
            return t;
        }

        private void FillBrands()
        {
            suppressEvents = true;
            p4Brand.Items.Clear();
            foreach (KeyValuePair<string, int> kv in Core.Brands(examples)) p4Brand.Items.Add(new BrandItem(kv.Key, kv.Value));
            suppressEvents = false;
        }

        private void SelectBrand(string brand)
        {
            for (int i = 0; i < p4Brand.Items.Count; i++)
            {
                if (string.Equals(((BrandItem)p4Brand.Items[i]).Name, brand, StringComparison.OrdinalIgnoreCase))
                {
                    suppressEvents = true;
                    p4Brand.SelectedIndex = i;
                    suppressEvents = false;
                    return;
                }
            }
        }

        private void FillModels(ExampleInfo select)
        {
            BrandItem b = p4Brand.SelectedItem as BrandItem;
            suppressEvents = true;
            p4Models.BeginUpdate();
            p4Models.Items.Clear();
            if (b != null)
            {
                foreach (ExampleInfo e in examples)
                {
                    if (!string.Equals(e.Brand, b.Name, StringComparison.OrdinalIgnoreCase)) continue;
                    ListViewItem it = new ListViewItem(e.Tv + (e == suggested ? "    \u2190 suggested for your TV" : ""));
                    it.SubItems.Add(e.Os);
                    it.SubItems.Add(e.Lists.Count.ToString());
                    it.Tag = e;
                    if (e == suggested) it.ForeColor = Green;
                    p4Models.Items.Add(it);
                    if (e == select) { it.Selected = true; it.EnsureVisible(); }
                }
            }
            p4Models.EndUpdate();
            suppressEvents = false;
        }

        private void SelectExample(ExampleInfo e, bool showInList)
        {
            if (e == null) return;
            if (showInList) { SelectBrand(e.Brand); FillModels(e); }
            suppressEvents = true;
            p4Variant.Items.Clear();
            foreach (string l in e.Lists) p4Variant.Items.Add(l);
            string savedVariant = st.Get("example") == e.Folder ? st.Get("list_file") : "";
            int vi = Math.Max(0, p4Variant.Items.IndexOf(savedVariant));
            p4Variant.SelectedIndex = vi;
            p4Variant.Enabled = e.Lists.Count > 1;
            suppressEvents = false;
            p4Notes.Text = (e.Notes.Replace("`", "") + (e.HasConfig ? "\r\n\r\nThis TV also has a tested home screen setup (dock, Live TV app, remote keys) that step 7 uses." : "")).Trim();
            ChooseSource(e, p4Variant.Items[vi].ToString());
        }

        private void ChooseSource(ExampleInfo e, string listFile)
        {
            chosenExample = e;
            chosenSource = Path.Combine(e.Dir, listFile);
            chosenLabel = "examples\\" + e.Folder + "\\" + listFile;
            st.Set("example", e.Folder);
            st.Set("list_file", listFile);
            st.Set("source", "example");
            entries = null;
            MarkDone(P_KEEP, false);
            int n = 0;
            try { n = Core.CountDisable(Core.ParseList(chosenSource)); } catch { }
            SetResult(p4Using, "Using: " + e.Tv + "  -  " + listFile + "  (" + n + " apps to disable by default). Press Next.", Green);
            MarkDone(P_MODEL, true);
        }

        private void BuildAuditList()
        {
            if (!done[P_CONNECT]) { ShowPage(P_CONNECT); return; }
            if (MessageBox.Show(this, "The app will ask the TV which apps do voice, ACR (content recognition) and telemetry, and build a list of those for you to review in the next step.\r\n\r\nUse this only when no tested list fits your TV. Continue?",
                AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            string dir = Path.Combine(listsDir, "privacy-audit");
            string file = Path.Combine(dir, "audit-source.txt");
            RunAsync("Running the privacy audit", delegate
            {
                Directory.CreateDirectory(dir);
                if (File.Exists(file)) File.Delete(file);
                int rc = Run(venvPy, "-I tools\\privacy.py --write \"" + file + "\"", repo, 300, null, true, null);
                return rc == 0 && File.Exists(file);
            }, delegate (bool ok)
            {
                if (!ok) { SetResult(p4Using, "The privacy audit did not produce a list (see the log).", Red); return; }
                chosenExample = null;
                chosenSource = file;
                chosenLabel = "privacy audit of this TV";
                st.Set("source", "audit");
                entries = null;
                p4Notes.Text = "A list built by CleanYourTV's privacy audit (tools\\privacy.py) from what your TV runs for voice, ACR and telemetry. It was not tested on your model, so review it carefully in the next step.";
                SetResult(p4Using, "Using: privacy audit list (" + Core.CountDisable(Core.ParseList(file)) + " apps). Press Next.", Green);
                MarkDone(P_MODEL, true);
            });
        }

        // ================================================================== Step 5: what to keep

        private Control BuildKeep()
        {
            TableLayoutPanel t = NewPage("Step 5 - Choose what to keep", null);
            p5Title = Wrap("", Color.FromArgb(40, 40, 40));
            AddRow(t, p5Title);
            AddRow(t, Wrap("Ticked apps will be disabled (not uninstalled; Undo puts them back). Untick anything you use. Grey entries are protected and are never touched.", Color.FromArgb(40, 40, 40)));
            FlowLayoutPanel keepRow = Row(Lbl("Keep everything for:"));
            foreach (KeepCategory c in Core.KeepCategories)
            {
                CheckBox cb = new CheckBox();
                cb.Text = c.Name;
                cb.AutoSize = true;
                cb.Tag = c;
                cb.Margin = new Padding(0, 8, 14, 3);
                cb.CheckedChanged += delegate (object s, EventArgs ev) { if (!suppressEvents) KeepCategoryChanged((CheckBox)s); };
                p5Keep.Add(cb);
                keepRow.Controls.Add(cb);
            }
            AddRow(t, keepRow);
            Button reset = Btn("Reset to the tested list");
            Button none = Btn("Untick all");
            Button all = Btn("Tick all");
            p5HideMissing = new CheckBox();
            p5HideMissing.Text = "Hide apps that are not on my TV";
            p5HideMissing.AutoSize = true;
            p5HideMissing.Checked = true;
            p5HideMissing.Margin = new Padding(6, 9, 3, 3);
            reset.Click += delegate { SetAll(null); };
            none.Click += delegate { SetAll(false); };
            all.Click += delegate { SetAll(true); };
            p5HideMissing.CheckedChanged += delegate { FillKeepList(); };
            AddRow(t, Row(reset, none, all, p5HideMissing));
            p5List = new ListView();
            p5List.View = View.Details;
            p5List.CheckBoxes = true;
            p5List.FullRowSelect = true;
            p5List.ShowGroups = true;
            p5List.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            p5List.Columns.Add("Disable  /  app", 300);
            p5List.Columns.Add("What it is (from the tested list)", 450);
            p5List.Columns.Add("On your TV", 130);
            p5List.ItemCheck += delegate (object s, ItemCheckEventArgs ev)
            {
                ListEntry e = p5List.Items[ev.Index].Tag as ListEntry;
                if (e != null && e.Locked) ev.NewValue = CheckState.Unchecked;
            };
            p5List.ItemChecked += delegate (object s, ItemCheckedEventArgs ev)
            {
                if (suppressEvents) return;
                ListEntry e = ev.Item.Tag as ListEntry;
                if (e == null || e.Locked) return;
                e.Disable = ev.Item.Checked;
                UpdateKeepSummary();
            };
            AddFillRow(t, p5List);
            p5Summary = Lbl("");
            p5Summary.Font = new Font("Segoe UI Semibold", 10f);
            AddRow(t, p5Summary);
            return t;
        }

        private string ChoiceKey()
        {
            return "choice:" + (chosenExample != null ? chosenExample.Folder + "/" + Path.GetFileName(chosenSource) : "audit");
        }

        private void LoadEntries()
        {
            entries = Core.ParseList(chosenSource);
            Core.ApplyStatus(entries, tv);
            // Saved choices: "+pkg" disabled, "-pkg" kept, relative to the tested list.
            string saved = st.Get(ChoiceKey());
            if (saved.Length > 0)
            {
                Dictionary<string, bool> diff = new Dictionary<string, bool>();
                foreach (string part in saved.Split(','))
                    if (part.Length > 1) diff[part.Substring(1)] = part[0] == '+';
                foreach (ListEntry e in entries)
                {
                    bool v;
                    if (!e.Locked && diff.TryGetValue(e.Package, out v)) e.Disable = v;
                }
            }
            suppressEvents = true;
            string cats = st.Get(ChoiceKey() + ":keep");
            foreach (CheckBox cb in p5Keep) cb.Checked = ("|" + cats + "|").Contains("|" + cb.Text + "|");
            suppressEvents = false;
            p5Title.Text = "List: " + chosenLabel + (tv != null ? "   -   TV: " + (tv.Manufacturer + " " + tv.Model).Trim() : "");
            FillKeepList();
        }

        private void FillKeepList()
        {
            if (entries == null) return;
            suppressEvents = true;
            p5List.BeginUpdate();
            p5List.Items.Clear();
            p5List.Groups.Clear();
            Dictionary<string, ListViewGroup> groups = new Dictionary<string, ListViewGroup>();
            foreach (ListEntry e in entries)
            {
                if (p5HideMissing.Checked && e.Status == "not installed") continue;
                ListViewGroup g;
                if (!groups.TryGetValue(e.Section, out g))
                {
                    g = new ListViewGroup(e.Section, e.Section);
                    groups[e.Section] = g;
                    p5List.Groups.Add(g);
                }
                ListViewItem it = new ListViewItem(e.Package, g);
                string what = e.Comment;
                if (!e.DefaultDisable && !e.Locked) what = "[kept by the list's testers] " + what;
                it.SubItems.Add(what);
                it.SubItems.Add(e.Locked ? "protected" : (e.Status.Length > 0 ? e.Status : "unknown"));
                it.Tag = e;
                it.Checked = e.Disable && !e.Locked;
                if (e.Locked) it.ForeColor = Color.Gray;
                else if (e.Status == "not installed") it.ForeColor = Color.FromArgb(150, 150, 150);
                else if (!e.DefaultDisable) it.ForeColor = Navy;
                p5List.Items.Add(it);
            }
            p5List.EndUpdate();
            suppressEvents = false;
            UpdateKeepSummary();
        }

        private void UpdateKeepSummary()
        {
            if (entries == null) return;
            int dis = 0, onTv = 0, hidden = 0;
            foreach (ListEntry e in entries)
            {
                if (e.Disable && !e.Locked)
                {
                    dis++;
                    if (e.Status == "enabled") onTv++;
                }
                if (p5HideMissing.Checked && e.Status == "not installed") hidden++;
            }
            string s = dis + " of " + entries.Count + " will be disabled";
            if (tv != null && tv.HasPackages) s += " (" + onTv + " of them are currently enabled on your TV)";
            if (hidden > 0) s += ";  " + hidden + " apps not on your TV are hidden";
            p5Summary.Text = s + ".";
            p5Summary.ForeColor = dis > 0 ? Navy : Red;
            done[P_KEEP] = dis > 0;
            RefreshNav();
        }

        private void KeepCategoryChanged(CheckBox cb)
        {
            if (entries == null) return;
            KeepCategory c = (KeepCategory)cb.Tag;
            int n = 0;
            foreach (ListEntry e in entries)
            {
                if (e.Locked || !c.Matches(e)) continue;
                // Keep: untick. Untick the switch: back to what the tested list says, unless another keep switch still covers it.
                bool keepByOther = false;
                foreach (CheckBox other in p5Keep)
                    if (other != cb && other.Checked && ((KeepCategory)other.Tag).Matches(e)) keepByOther = true;
                e.Disable = cb.Checked ? false : (keepByOther ? false : e.DefaultDisable);
                n++;
            }
            Log((cb.Checked ? "Keeping " : "Back to the tested choice for ") + n + " apps: " + c.Name, Navy);
            FillKeepList();
        }

        private void SetAll(object value)
        {
            if (entries == null) return;
            suppressEvents = true;
            foreach (CheckBox cb in p5Keep) cb.Checked = false;
            suppressEvents = false;
            foreach (ListEntry e in entries)
            {
                if (e.Locked) continue;
                if (value == null) e.Disable = e.DefaultDisable;
                else if (!p5HideMissing.Checked || e.Status != "not installed" || !(bool)value) e.Disable = (bool)value;
            }
            FillKeepList();
        }

        private string GeneratedListPath()
        {
            string folder = chosenExample != null ? chosenExample.Folder : "privacy-audit";
            string file = chosenExample != null ? Path.GetFileName(chosenSource) : "debloat.txt";
            return Path.Combine(Path.Combine(listsDir, folder), file);
        }

        private bool SaveChoicesAndGenerate()
        {
            if (entries == null || chosenSource.Length == 0) return false;
            if (Core.CountDisable(entries) == 0)
            {
                MessageBox.Show(this, "Nothing is ticked, so there is nothing to clean. Tick at least one app.", AppName);
                return false;
            }
            List<string> diff = new List<string>();
            foreach (ListEntry e in entries)
                if (!e.Locked && e.Disable != e.DefaultDisable) diff.Add((e.Disable ? "+" : "-") + e.Package);
            st.Set(ChoiceKey(), string.Join(",", diff.ToArray()));
            List<string> cats = new List<string>();
            foreach (CheckBox cb in p5Keep) if (cb.Checked) cats.Add(cb.Text);
            st.Set(ChoiceKey() + ":keep", string.Join("|", cats.ToArray()));
            string path = GeneratedListPath();
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                File.WriteAllText(path, Core.BuildList(chosenSource, entries, chosenLabel), new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Could not save your list: " + ex.Message, AppName);
                return false;
            }
            st.Set("generated_list", path);
            Log("Saved your choices: " + Core.CountDisable(entries) + " apps to disable -> " + path, Green);
            return true;
        }

        // ================================================================== Step 6: clean

        private Control BuildClean()
        {
            TableLayoutPanel t = NewPage("Step 6 - Clean the TV",
                "The app now disables the apps you ticked, using CleanYourTV's own script. Before the first change it saves a record of how the TV is now, so that 'Undo' (in Maintenance) can put everything back exactly.");
            p6Summary = Wrap("", Color.Black);
            p6Summary.Font = new Font("Segoe UI", 10.5f);
            AddRow(t, p6Summary);
            Button view = Btn("View the list that will be applied");
            view.Click += delegate
            {
                string p = st.Get("generated_list");
                if (File.Exists(p)) ShowText("Your list", File.ReadAllText(p));
            };
            AddRow(t, Row(view));
            p6Run = Btn("Clean my TV now");
            StylePrimary(p6Run);
            p6Run.Padding = new Padding(16, 8, 16, 8);
            p6Run.Click += delegate { CleanTv(); };
            AddRow(t, Row(p6Run));
            AddRow(t, Wrap("The TV's stock home screen app is skipped on this first run on purpose: there must always be a home screen. It is handled in step 7, once the new home screen is installed (or stays, if you skip step 7).", Muted));
            p6Result = Wrap("", Muted);
            p6Result.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, p6Result);
            return t;
        }

        private void CleanTv()
        {
            string list = st.Get("generated_list");
            if (!File.Exists(list) || !done[P_KEEP]) { ShowPage(P_KEEP); return; }
            int n = Core.CountDisable(Core.ParseList(list));
            if (MessageBox.Show(this, "Disable " + n + " apps on the TV at " + TvIp + " now?\r\n\r\nNothing is uninstalled, and Maintenance > Undo puts everything back.",
                AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            SetResult(p6Result, "Cleaning... keep the TV on.", Orange);
            RunAsync("Cleaning the TV", delegate
            {
                return RunPs("tools\\disable.ps1", "-TvHost " + TvIp + " " + Q(list), 900) == 0;
            }, delegate (bool ok)
            {
                if (ok)
                {
                    st.Set("cleaned_list", list);
                    st.Set("cleaned_ip", TvIp);
                    SetResult(p6Result, "Done. The apps are disabled. Press Next for the new home screen.", Green);
                    MarkDone(P_CLEAN, true);
                    UpdateMaint();
                }
                else SetResult(p6Result, "The cleaning stopped with an error (see the activity log below). Nothing after the error was changed; you can run it again.", Red);
            });
        }

        private void UpdateCleanSummary()
        {
            string list = st.Get("generated_list");
            int n = 0;
            try { if (File.Exists(list)) n = Core.CountDisable(Core.ParseList(list)); } catch { }
            p6Summary.Text = "TV:   " + (tv != null ? (tv.Manufacturer + " " + tv.Model).Trim() + "  at " : "") + TvIp +
                "\r\nList:   " + chosenLabel + "\r\nApps to disable:   " + n;
            p6Run.Text = "Clean my TV now  (disable " + n + " apps)";
            if (st.Get("cleaned_list") == list && list.Length > 0 && !done[P_CLEAN])
            {
                SetResult(p6Result, "This list was already applied on " + st.Get("cleaned_ip") + ". You can run it again or press Next.", Green);
                MarkDone(P_CLEAN, true);
            }
        }

        // ================================================================== Step 7: home screen

        private Control BuildHome()
        {
            TableLayoutPanel t = NewPage("Step 7 - New home screen",
                "Replace the stock home screen and its ad rows with CleanYourTV's small, fast home screen. It is built here, offline, and installed on the TV. If anything goes wrong, Home goes back to the stock one by itself.");
            p7Install = WrapCheck("Install the new home screen (recommended)", true);
            p7Install.Checked = true;
            AddRow(t, p7Install);

            TableLayoutPanel grid = new TableLayoutPanel();
            grid.ColumnCount = 3;
            grid.AutoSize = true;
            grid.Dock = DockStyle.Top;
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

            p7LiveTv = new ComboBox();
            p7LiveTv.DropDownStyle = ComboBoxStyle.DropDown;
            p7LiveTv.Width = 300;
            p7Theme = new ComboBox();
            p7Theme.DropDownStyle = ComboBoxStyle.DropDownList;
            p7Theme.Width = 300;
            p7Theme.MaxDropDownItems = 20;
            p7Theme.SelectedIndexChanged += delegate { ShowThemePreview(); };
            p7Columns = new NumericUpDown();
            p7Columns.Minimum = 3;
            p7Columns.Maximum = 10;
            p7Columns.Value = 6;
            p7Columns.Width = 70;
            p7Greeting = new TextBox();
            p7Greeting.Width = 300;
            p7Greeting.Text = st.Get("greeting");
            p7Preview = new PictureBox();
            p7Preview.Size = new Size(256, 144);
            p7Preview.SizeMode = PictureBoxSizeMode.Zoom;
            p7Preview.BorderStyle = BorderStyle.FixedSingle;
            p7Preview.BackColor = Color.Black;

            p7Dock = new CheckedListBox();
            p7Dock.CheckOnClick = true;
            p7Dock.Size = new Size(300, 150);
            Button up = Btn("Up");
            Button down = Btn("Down");
            up.Click += delegate { MoveDock(-1); };
            down.Click += delegate { MoveDock(1); };
            FlowLayoutPanel dockButtons = new FlowLayoutPanel();
            dockButtons.FlowDirection = FlowDirection.TopDown;
            dockButtons.AutoSize = true;
            dockButtons.Controls.Add(up);
            dockButtons.Controls.Add(down);

            AddGrid(grid, "Live TV app (for HDMI and Inputs):", p7LiveTv, null);
            AddGrid(grid, "Look (theme):", p7Theme, p7Preview);
            AddGrid(grid, "Apps per row:", p7Columns, null);
            AddGrid(grid, "Greeting name (optional):", p7Greeting, null);
            AddGrid(grid, "Dock apps (ticked, in order):", p7Dock, dockButtons);
            AddRow(t, grid);

            p7InputKey = WrapCheck("The remote's Input button should open the input list (needed on some Google TV remotes)", false);
            p7HomeKey = WrapCheck("The remote's Home button sends 'All apps' instead of Home (some Xiaomi sticks)", false);
            AddRow(t, p7InputKey);
            AddRow(t, p7HomeKey);

            Button install = Btn("Install the home screen and finish cleaning");
            StylePrimary(install);
            install.Padding = new Padding(16, 8, 16, 8);
            install.Click += delegate { InstallHome(); };
            Button themeOnly = Btn("Apply look and dock only");
            themeOnly.Click += delegate { PushThemeOnly(); };
            Button skip = Btn("Skip - keep the stock home screen");
            skip.Click += delegate
            {
                st.SetBool("launcher_skipped", true);
                SetResult(p7Result, "Skipped. The stock home screen stays. Press Next.", Green);
                MarkDone(P_HOME, true);
            };
            AddRow(t, Row(install, themeOnly, skip));
            p7Result = Wrap("", Muted);
            p7Result.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, p7Result);
            p7Install.CheckedChanged += delegate { grid.Enabled = p7Install.Checked; p7InputKey.Enabled = p7Install.Checked; p7HomeKey.Enabled = p7Install.Checked; };
            return t;
        }

        private static void AddGrid(TableLayoutPanel g, string label, Control c, Control extra)
        {
            int r = g.RowStyles.Count;
            g.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Label l = Lbl(label);
            l.Margin = new Padding(0, 8, 10, 3);
            g.Controls.Add(l, 0, r);
            c.Margin = new Padding(0, 5, 8, 3);
            g.Controls.Add(c, 1, r);
            if (extra != null) g.Controls.Add(extra, 2, r);
        }

        private void MoveDock(int dir)
        {
            int i = p7Dock.SelectedIndex;
            int j = i + dir;
            if (i < 0 || j < 0 || j >= p7Dock.Items.Count) return;
            object item = p7Dock.Items[i];
            bool chk = p7Dock.GetItemChecked(i);
            p7Dock.Items.RemoveAt(i);
            p7Dock.Items.Insert(j, item);
            p7Dock.SetItemChecked(j, chk);
            p7Dock.SelectedIndex = j;
        }

        private Dictionary<string, object> ExampleConfig()
        {
            if (chosenExample == null || !chosenExample.HasConfig) return null;
            return Core.ReadJson(Path.Combine(chosenExample.Dir, "config.json"));
        }

        private void PrepareHomePage()
        {
            Dictionary<string, object> cfg = ExampleConfig();
            // Live TV app
            p7LiveTv.Items.Clear();
            List<string> live = new List<string>();
            string fromCfg = Core.JsonString(cfg, "live_tv_package");
            if (fromCfg.Length > 0) live.Add(fromCfg);
            foreach (string p in Core.KnownLiveTv)
                if (tv != null && tv.Installed.Contains(p) && !live.Contains(p)) live.Add(p);
            if (tv != null)
                foreach (string p in tv.Installed)
                    if ((p.Contains("livetv") || p.Contains("tvcenter") || p.Contains("tvplayer")) && !live.Contains(p)) live.Add(p);
            foreach (string p in live) p7LiveTv.Items.Add(p);
            string savedLive = st.Get("live_tv");
            p7LiveTv.Text = savedLive.Length > 0 ? savedLive : (live.Count > 0 ? live[0] : "");

            // Themes
            p7Theme.Items.Clear();
            p7Theme.Items.Add("(plain, no theme)");
            string themes = Path.Combine(repo, "themes");
            if (Directory.Exists(themes))
            {
                List<string> names = new List<string>();
                foreach (string d in Directory.GetDirectories(themes))
                    if (File.Exists(Path.Combine(d, "config.json"))) names.Add(Path.GetFileName(d));
                names.Sort(StringComparer.OrdinalIgnoreCase);
                foreach (string n in names) p7Theme.Items.Add(n);
            }
            string savedTheme = st.Get("theme");
            int ti = p7Theme.Items.IndexOf(savedTheme.Length > 0 ? savedTheme : "default");
            p7Theme.SelectedIndex = ti >= 0 ? ti : 0;

            // Columns
            string cols = st.Get("columns");
            if (cols.Length == 0) cols = Core.JsonString(cfg, "columns");
            int c;
            if (int.TryParse(cols, out c) && c >= 3 && c <= 10) p7Columns.Value = c;

            // Dock
            p7Dock.Items.Clear();
            List<string> order = new List<string>();
            string savedDock = st.Get("dock");
            List<string> dock = savedDock.Length > 0 ? new List<string>(savedDock.Split(',')) : Core.JsonStringList(cfg, "dock_apps");
            foreach (string p in dock) if (p.Length > 0 && !order.Contains(p) && (tv == null || !tv.HasPackages || tv.Installed.Contains(p))) order.Add(p);
            if (tv != null)
            {
                foreach (string p in tv.Leanback) if (!order.Contains(p) && p != Core.LauncherPackage) order.Add(p);
                foreach (string p in tv.ThirdParty) if (!order.Contains(p) && p != Core.LauncherPackage) order.Add(p);
            }
            bool noDock = dock.Count == 0;
            for (int i = 0; i < order.Count; i++)
            {
                p7Dock.Items.Add(order[i]);
                bool chk = dock.Contains(order[i]) || (noDock && i < 6 && tv != null && tv.Leanback.Contains(order[i]));
                p7Dock.SetItemChecked(i, chk);
            }

            // Remote keys: from the saved choice, else from what the tested list's notes say.
            string notes = chosenExample != null ? chosenExample.Notes : "";
            p7InputKey.Checked = st.Get("input_key").Length > 0 ? st.GetBool("input_key") : notes.Contains("InputKeyService");
            p7HomeKey.Checked = st.Get("home_key").Length > 0 ? st.GetBool("home_key") : notes.Contains("HomeKeyService");

            if (st.GetBool("launcher_installed")) { SetResult(p7Result, "The new home screen is installed. You can change its look and dock, or press Next.", Green); done[P_HOME] = true; }
            else if (st.GetBool("launcher_skipped")) { done[P_HOME] = true; }
            RefreshNav();
        }

        private void ShowThemePreview()
        {
            Image old = p7Preview.Image;
            p7Preview.Image = null;
            if (old != null) old.Dispose();
            string name = p7Theme.SelectedItem == null ? "" : p7Theme.SelectedItem.ToString();
            if (name.StartsWith("(")) return;
            p7Preview.Image = LoadImageCopy(Path.Combine(repo, "themes\\" + name + "\\screenshot.jpg"));
        }

        private string SaveHomeChoices()
        {
            string themeName = p7Theme.SelectedItem == null ? "" : p7Theme.SelectedItem.ToString();
            st.Set("theme", themeName);
            st.Set("columns", ((int)p7Columns.Value).ToString());
            st.Set("greeting", p7Greeting.Text.Trim());
            st.Set("live_tv", p7LiveTv.Text.Trim());
            st.SetBool("input_key", p7InputKey.Checked);
            st.SetBool("home_key", p7HomeKey.Checked);
            List<string> dock = new List<string>();
            foreach (object o in p7Dock.CheckedItems) dock.Add(o.ToString());
            st.Set("dock", string.Join(",", dock.ToArray()));

            Dictionary<string, object> ov = new Dictionary<string, object>();
            ov["columns"] = (int)p7Columns.Value;
            if (dock.Count > 0) ov["dock_apps"] = dock.ToArray();
            string live = p7LiveTv.Text.Trim();
            if (live.Length > 0 && Core.PkgRe.IsMatch(live)) ov["live_tv_package"] = live;
            string g = p7Greeting.Text.Trim();
            ov["greeting_name"] = g.Length > 0 ? (object)g : null;
            string themeDir = themeName.StartsWith("(") ? null : Path.Combine(repo, "themes\\" + themeName);
            string exCfg = chosenExample != null && chosenExample.HasConfig ? Path.Combine(chosenExample.Dir, "config.json") : null;
            Core.BuildTheme(themeDir, exCfg, ov, themeOut);
            Log("Prepared the home screen settings (" + (themeDir == null ? "plain" : themeName) + " look, " + dock.Count + " dock apps) in " + themeOut, Navy);
            return themeOut;
        }

        private void InstallHome()
        {
            if (!p7Install.Checked) { SetResult(p7Result, "Tick 'Install the new home screen' first, or press Skip.", Orange); return; }
            if (!done[P_CLEAN]) { ShowPage(P_CLEAN); return; }
            if (MessageBox.Show(this, "Build the home screen on this PC (2 to 5 minutes, offline), install it on the TV, apply your look and dock, and then finish the cleaning (the stock home screen app and its ad rows)?",
                AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            string themeDir;
            try { themeDir = SaveHomeChoices(); }
            catch (Exception ex) { SetResult(p7Result, "Could not prepare the settings: " + ex.Message, Red); return; }
            string args = "-TvHost " + TvIp + (p7InputKey.Checked ? " -InputKeyService" : "") + (p7HomeKey.Checked ? " -HomeKeyService" : "");
            string list = st.Get("cleaned_list");
            string stage = "";
            SetResult(p7Result, "Working... this takes a few minutes. Keep the TV on.", Orange);
            RunAsync("Installing the new home screen", delegate
            {
                stage = "building and installing the home screen";
                Log("1/3  Building and installing the home screen (offline)", Navy);
                if (RunPs("launcher\\build-and-install.ps1", args, 2400) != 0) return false;
                st.SetBool("launcher_installed", true);
                st.SetBool("launcher_skipped", false);
                stage = "applying the look and dock";
                Log("2/3  Applying your look and dock", Navy);
                if (RunPs("tools\\theme.ps1", "-TvHost " + TvIp + " " + Q(themeDir), 600) != 0) return false;
                stage = "finishing the cleaning";
                Log("3/3  Finishing the cleaning (the stock home screen app and its rows)", Navy);
                if (File.Exists(list) && RunPs("tools\\disable.ps1", "-TvHost " + TvIp + " " + Q(list), 900) != 0) return false;
                return true;
            }, delegate (bool ok)
            {
                if (!ok)
                {
                    SetResult(p7Result, "Stopped while " + stage + " (see the activity log). " +
                        (st.GetBool("launcher_installed") ? "The home screen itself is installed; you can press the button again." : "Home is still the stock one."), Red);
                    return;
                }
                SetResult(p7Result, "Done. The new home screen is installed and the cleaning is complete. Press Next.", Green);
                MarkDone(P_HOME, true);
                if (MessageBox.Show(this, "Restart the TV now so everything starts clean?", AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                    RebootTv();
            });
        }

        private void PushThemeOnly()
        {
            if (!st.GetBool("launcher_installed"))
            {
                SetResult(p7Result, "Install the home screen first; the look and dock belong to it.", Orange);
                return;
            }
            string themeDir;
            try { themeDir = SaveHomeChoices(); }
            catch (Exception ex) { SetResult(p7Result, "Could not prepare the settings: " + ex.Message, Red); return; }
            RunAsync("Applying the look and dock", delegate
            {
                return RunPs("tools\\theme.ps1", "-TvHost " + TvIp + " " + Q(themeDir), 600) == 0;
            }, delegate (bool ok)
            {
                if (ok) SetResult(p7Result, "Look and dock applied; Home restarted on the TV.", Green);
                else SetResult(p7Result, "Could not apply the look (see the activity log).", Red);
            });
        }

        // ================================================================== Step 8: finish

        private Control BuildFinish()
        {
            TableLayoutPanel t = NewPage("Step 8 - Finish and secure",
                "Last step: close the debugging door. Network debugging has no password, so switch it off now that the TV is clean. The new home screen keeps working without it.");
            p8Off = WrapCheck("On the TV: Settings > Device Preferences > Developer options: switch 'USB debugging' off, and choose 'Revoke USB debugging authorisations'.", false);
            p8Reboot = WrapCheck("Restart the TV (Settings > Device Preferences > About > Restart, or unplug it for 10 seconds).", false);
            AddRow(t, p8Off);
            AddRow(t, p8Reboot);
            Button check = Btn("Check that the debugging door is closed");
            StylePrimary(check);
            check.Click += delegate { CheckPortClosed(p8Result); };
            AddRow(t, Row(check));
            p8Result = Wrap("", Muted);
            p8Result.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, p8Result);
            AddRow(t, Wrap("Keep this app. After a TV firmware update, or if you ever want everything back, switch USB debugging on again and use 'Maintenance and undo'.", Muted));
            EventHandler ch = delegate
            {
                st.SetBool("s8_off", p8Off.Checked);
                st.SetBool("s8_reboot", p8Reboot.Checked);
                done[P_FINISH] = p8Off.Checked && p8Reboot.Checked;
                RefreshNav();
            };
            p8Off.Checked = st.GetBool("s8_off");
            p8Reboot.Checked = st.GetBool("s8_reboot");
            done[P_FINISH] = p8Off.Checked && p8Reboot.Checked;
            p8Off.CheckedChanged += ch;
            p8Reboot.CheckedChanged += ch;
            return t;
        }

        private void CheckPortClosed(Label target)
        {
            string ip = TvIp;
            if (!ValidIp(ip)) { SetResult(target, "Set the TV's IP address first.", Red); return; }
            int code = -1;
            RunAsync("Checking the debugging port", delegate
            {
                code = Run(venvPy, "-I tools\\adb-closed.py " + ip, repo, 60, null, true, null);
                return true;
            }, delegate (bool ok)
            {
                if (code == 0) SetResult(target, "Closed. Your TV no longer accepts debugging connections.", Green);
                else if (code == 1) SetResult(target, "Still open: switch USB debugging off on the TV, restart it, and check again.", Red);
                else SetResult(target, "Could not tell: the TV did not answer (off, asleep, restarting or at another address). Try again in a minute.", Orange);
            });
        }

        // ================================================================== Maintenance

        private Control BuildMaint()
        {
            TableLayoutPanel t = NewPage("Maintenance and undo",
                "These tools talk to the TV, so USB debugging must be switched on again first (step 1).");
            pmIp = new TextBox();
            pmIp.Width = 170;
            pmIp.Margin = new Padding(0, 5, 8, 3);
            pmIp.Text = TvIp;
            pmIp.TextChanged += delegate
            {
                string ip = pmIp.Text.Trim();
                if (ValidIp(ip) && ip != TvIp) { st.Set("tv_ip", ip); tv = null; done[P_CONNECT] = false; p1Ip.Text = ip; RefreshNav(); }
            };
            AddRow(t, Row(Lbl("TV IP address:"), pmIp));
            pmList = Wrap("", Muted);
            AddRow(t, pmList);

            AddRow(t, Section("Undo everything"));
            AddRow(t, Wrap("Puts the TV back exactly as it was before cleaning, from the record saved in step 6, and gives Home back to the stock home screen.", Color.Black));
            Button restore = Btn("Undo all changes");
            restore.Click += delegate { UndoAll(); };
            pmNeedsList.Add(restore);
            AddRow(t, Row(restore));

            AddRow(t, Section("After a TV firmware update"));
            AddRow(t, Wrap("Updates can switch disabled apps back on and give Home back to the stock launcher. Check first, then re-apply your choices if anything came back.", Color.Black));
            Button chk = Btn("Check what came back");
            Button fix = Btn("Re-apply my choices");
            chk.Click += delegate { CheckDrift(false); };
            fix.Click += delegate { CheckDrift(true); };
            pmNeedsList.Add(chk);
            pmNeedsList.Add(fix);
            AddRow(t, Row(chk, fix));

            AddRow(t, Section("More"));
            Button privacy = Btn("Privacy audit report");
            Button reboot = Btn("Restart the TV");
            Button closed = Btn("Check the debugging door is closed");
            Button change = Btn("Change my choices (step 5)");
            Button shell = Btn("Open CleanYourTV PowerShell");
            Button folder = Btn("Open my lists folder");
            privacy.Click += delegate { RunAsync("Running the privacy audit", delegate { return Run(venvPy, "-I tools\\privacy.py", repo, 300, null, true, null) == 0; }, null); };
            reboot.Click += delegate { if (MessageBox.Show(this, "Restart the TV now?", AppName, MessageBoxButtons.YesNo) == DialogResult.Yes) RebootTv(); };
            closed.Click += delegate { CheckPortClosed(pmResult); };
            change.Click += delegate { if (CanOpen(P_KEEP)) ShowPage(P_KEEP); else { SetStatus("Connect to the TV first (step 3)."); ShowPage(CanOpen(P_CONNECT) ? P_CONNECT : P_PREP); } };
            shell.Click += delegate { OpenShell(); };
            folder.Click += delegate { Directory.CreateDirectory(listsDir); Process.Start("explorer.exe", Q(listsDir)); };
            AddRow(t, Row(privacy, reboot, closed, change, shell, folder));
            pmResult = Wrap("", Muted);
            pmResult.Font = new Font("Segoe UI Semibold", 10.5f);
            AddRow(t, pmResult);
            return t;
        }

        private static Label Section(string title)
        {
            Label l = new Label();
            l.Text = title;
            l.AutoSize = true;
            l.UseMnemonic = false;
            l.Font = new Font("Segoe UI Semibold", 11.5f);
            l.ForeColor = Navy;
            l.Margin = new Padding(0, 16, 0, 2);
            return l;
        }

        private void UpdateMaint()
        {
            string list = st.Get("cleaned_list");
            bool has = list.Length > 0 && File.Exists(list);
            pmList.Text = has ? "Applied list: " + list + "   (on " + st.Get("cleaned_ip") + ")" : "No cleaning has been applied from this PC yet, so Undo and the firmware-update check are not available.";
            foreach (Button b in pmNeedsList) b.Enabled = has;
        }

        private void UndoAll()
        {
            string list = st.Get("cleaned_list");
            if (!File.Exists(list)) return;
            if (MessageBox.Show(this, "Put the TV at " + TvIp + " back the way it was before cleaning, and give Home back to the stock home screen?",
                AppName, MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            string stock = st.Get("stock_launcher");
            if (stock.Length == 0) stock = Core.KnownStockLaunchers[0];
            RunAsync("Undoing all changes", delegate
            {
                return RunPs("tools\\restore.ps1", "-TvHost " + TvIp + " " + Q(list) + " -Stock " + stock, 900) == 0;
            }, delegate (bool ok)
            {
                if (ok)
                {
                    SetResult(pmResult, "Undone. The TV is back the way it was. A restart of the TV is recommended.", Green);
                    st.Set("cleaned_list", "");
                    st.SetBool("launcher_installed", false);
                    st.SetBool("finished", false);
                    done[P_CLEAN] = false;
                    done[P_HOME] = false;
                    UpdateMaint();
                    RefreshNav();
                }
                else SetResult(pmResult, "The undo stopped with an error (see the activity log). Run it again once the TV answers.", Red);
            });
        }

        private void CheckDrift(bool fix)
        {
            string list = st.Get("cleaned_list");
            if (!File.Exists(list)) return;
            string args = "-I tools\\check.py " + (fix ? "--fix " : "") + Q(list) + (st.GetBool("launcher_installed") ? " " + Core.LauncherPackage : "");
            int code = -1;
            RunAsync(fix ? "Re-applying your choices" : "Checking what came back", delegate
            {
                code = Run(venvPy, args, repo, 900, null, true, null);
                return true;
            }, delegate (bool ok)
            {
                if (code == 0) SetResult(pmResult, fix ? "Re-applied. The TV matches your choices again." : "Nothing came back. The TV matches your choices.", Green);
                else if (code == 1) SetResult(pmResult, fix ? "Re-applied, but some apps were left on by a safety check (see the log)." : "Some apps came back (listed in the log). Press 'Re-apply my choices'.", Orange);
                else SetResult(pmResult, "Could not read the TV (see the log). Is USB debugging on and the IP right?", Red);
            });
        }

        private void RebootTv()
        {
            RunAsync("Restarting the TV", delegate { return Run(venvPy, "-I tools\\tv.py --reboot", repo, 60, null, true, null) == 0; }, null);
        }

        // ================================================================== page entry

        private void OnEnter(int i)
        {
            if (i == P_SETUP && !done[P_SETUP] && !setupAutoRan)
            {
                setupAutoRan = true;
                RunAsync("Setting up the tools", delegate { return DoSetup(); }, null);
            }
            else if (i == P_CONNECT)
            {
                p3Ip.Text = TvIp;
                if (tv != null) ShowTvInfo();
            }
            else if (i == P_MODEL)
            {
                if (examples.Count == 0) LoadExamples();
                if (p4Brand.Items.Count == 0) FillBrands();
                int score;
                suggested = Core.BestMatch(examples, tv, out score);
                if (suggested != null)
                {
                    p4Suggest.Text = "Your TV (" + (tv.Manufacturer + " " + tv.Model + ", " + tv.Device).Trim() + ") matches:  " + suggested.Tv;
                    p4Suggest.ForeColor = Green;
                }
                else
                {
                    p4Suggest.Text = tv != null ? "No tested list names your exact model (" + (tv.Model + ", " + tv.Device).Trim() + "). Pick the closest one, or use the privacy audit below." : "";
                    p4Suggest.ForeColor = Orange;
                }
                p4UseSuggestion.Visible = suggested != null;
                // Restore the earlier choice, else take the suggestion, else the brand.
                ExampleInfo saved = null;
                foreach (ExampleInfo e in examples) if (e.Folder == st.Get("example")) saved = e;
                if (chosenExample != null) SelectExample(chosenExample, true);
                else if (st.Get("source") == "audit" && File.Exists(Path.Combine(listsDir, "privacy-audit\\audit-source.txt")) && chosenSource.Length > 0) { }
                else if (saved != null && (suggested == null || saved == suggested)) SelectExample(saved, true);
                else if (suggested != null) SelectExample(suggested, true);
                else
                {
                    string brand = Core.BrandFor(examples, tv);
                    if (brand.Length > 0) { SelectBrand(brand); FillModels(null); }
                    else if (p4Brand.Items.Count > 0 && p4Brand.SelectedIndex < 0) { p4Brand.SelectedIndex = 0; }
                }
            }
            else if (i == P_KEEP)
            {
                if (chosenSource.Length == 0) { ShowPage(P_MODEL); return; }
                if (entries == null) LoadEntries();
                else UpdateKeepSummary();
            }
            else if (i == P_CLEAN) UpdateCleanSummary();
            else if (i == P_HOME) PrepareHomePage();
            else if (i == P_MAINT) { pmIp.Text = TvIp; UpdateMaint(); }
        }

        private void LoadExamples()
        {
            try
            {
                examples = Core.LoadExamples(Path.Combine(repo, "examples"));
                Log("Loaded " + examples.Count + " tested TV lists (" + Core.Brands(examples).Count + " brands).", Muted);
            }
            catch (Exception ex) { Log("Could not read the tested lists: " + ex.Message, Red); }
        }

        private void OnFirstShown()
        {
            Log("== " + AppName + " " + AppVersion + " ==", Navy);
            Log("Installed in: " + appDir, Muted);
            string info = Path.Combine(appDir, "bundle-info.txt");
            if (File.Exists(info))
                try { foreach (string l in File.ReadAllLines(info)) if (l.Trim().Length > 0) Log("  " + l, Muted); } catch { }
            UpdateStep1Done();
            // Is step 2 still good? Quick check in the background (no changes).
            if (File.Exists(marker))
            {
                RunAsync("Checking the tools", delegate { return RecheckAll(); }, delegate (bool ok)
                {
                    if (!ok) setupAutoRan = false;
                });
            }
            UpdateMaint();
            if (!fromInstaller && st.GetBool("finished") && done[P_PREP]) ShowPage(P_MAINT);
            else ShowPage(P_PREP);
        }

        // ================================================================== threading

        private void RunAsync(string what, Work work, Action<bool> after)
        {
            if (busy) return;
            busy = true;
            SetBusy(true, what + "...");
            Thread t = new Thread(delegate ()
            {
                bool ok = false;
                try { ok = work(); }
                catch (Exception ex) { Log("ERROR: " + ex.Message, Red); }
                UI(delegate
                {
                    busy = false;
                    SetBusy(false, ok ? "Ready" : "Finished with a problem - see the log");
                    if (after != null) after(ok);
                    RefreshNav();
                });
            });
            t.IsBackground = true;
            t.Start();
        }

        private void SetBusy(bool on, string text)
        {
            host.Enabled = !on;
            nav.Enabled = !on;
            busyBar.Visible = on;
            busyBar.MarqueeAnimationSpeed = on ? 30 : 0;
            statusLbl.Text = text;
            RefreshNav();
        }

        private void SetStatus(string text) { statusLbl.Text = text; }

        private void UI(MethodInvoker m)
        {
            if (IsDisposed) return;
            try { if (InvokeRequired) BeginInvoke(m); else m(); }
            catch (ObjectDisposedException) { }
            catch (InvalidOperationException) { }
        }

        private void Log(string text, Color color)
        {
            UI(delegate
            {
                log.SelectionStart = log.TextLength;
                log.SelectionLength = 0;
                log.SelectionColor = color;
                log.AppendText(text + Environment.NewLine);
                log.SelectionColor = log.ForeColor;
                log.ScrollToCaret();
            });
        }

        private void Log(string text) { Log(text, Color.Black); }

        private void ShowText(string title, string text)
        {
            Form f = new Form();
            f.Text = title;
            f.Size = new Size(900, 640);
            f.StartPosition = FormStartPosition.CenterParent;
            TextBox tb = new TextBox();
            tb.Multiline = true;
            tb.ReadOnly = true;
            tb.ScrollBars = ScrollBars.Both;
            tb.WordWrap = false;
            tb.Dock = DockStyle.Fill;
            tb.Font = new Font("Consolas", 9.5f);
            tb.Text = text.Replace("\r\n", "\n").Replace("\n", "\r\n");
            f.Controls.Add(tb);
            f.ShowDialog(this);
        }

        // ================================================================== processes

        private void ApplyEnv(ProcessStartInfo psi)
        {
            psi.EnvironmentVariables["JAVA_HOME"] = jdk;
            psi.EnvironmentVariables["ANDROID_HOME"] = sdk;
            psi.EnvironmentVariables["ANDROID_SDK_ROOT"] = sdk;
            psi.EnvironmentVariables["GRADLE_USER_HOME"] = gradleHome;
            psi.EnvironmentVariables["PYTHONUTF8"] = "1";
            psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            psi.EnvironmentVariables["PYTHONNOUSERSITE"] = "1";
            psi.EnvironmentVariables["PIP_NO_INDEX"] = "1";
            psi.EnvironmentVariables["PIP_DISABLE_PIP_VERSION_CHECK"] = "1";
            string path = psi.EnvironmentVariables["PATH"];
            psi.EnvironmentVariables["PATH"] = string.Join(";", new string[] {
                Path.Combine(venvDir, "Scripts"), Path.Combine(appDir, "python"), Path.Combine(jdk, "bin"),
                Path.Combine(sdk, "platform-tools"), path ?? "" });
            string ip = TvIp;
            if (ip.Length > 0) psi.EnvironmentVariables["TV_HOST"] = ip;
            foreach (string k in new string[] { "FORCE_SETUPWRAITH", "FORCE_HOME", "TVINPUT_ALLOW", "HANDLERS_ALLOW" })
                if (psi.EnvironmentVariables.ContainsKey(k)) psi.EnvironmentVariables.Remove(k);
        }

        /// Runs a program with the bundled environment, streams its output to the log, returns the exit code.
        private int Run(string exe, string args, string cwd, int timeoutSec, StringBuilder captured, bool echo, string stdin)
        {
            ProcessStartInfo psi = new ProcessStartInfo(exe, args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.RedirectStandardInput = stdin != null;
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;
            psi.WorkingDirectory = cwd ?? appDir;
            ApplyEnv(psi);
            if (echo) Log("> " + Path.GetFileName(exe) + " " + args, Color.FromArgb(0, 90, 160));
            using (Process p = new Process())
            {
                p.StartInfo = psi;
                object gate = new object();
                DataReceivedEventHandler h = delegate (object s, DataReceivedEventArgs e)
                {
                    if (e.Data == null) return;
                    lock (gate) { if (captured != null) captured.AppendLine(e.Data); }
                    if (echo) Log("  " + e.Data, Color.FromArgb(70, 70, 70));
                };
                p.OutputDataReceived += h;
                p.ErrorDataReceived += h;
                try { p.Start(); }
                catch (Exception ex) { Log("  could not start " + exe + ": " + ex.Message, Red); return -1; }
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                if (stdin != null)
                {
                    try
                    {
                        StreamWriter w = new StreamWriter(p.StandardInput.BaseStream, new UTF8Encoding(false));
                        w.Write(stdin);
                        w.Close();
                    }
                    catch (Exception ex) { Log("  could not send input: " + ex.Message, Red); }
                }
                if (!p.WaitForExit(timeoutSec * 1000))
                {
                    try { p.Kill(); } catch { }
                    Log("  timed out after " + timeoutSec + " s", Red);
                    return -2;
                }
                p.WaitForExit();
                return p.ExitCode;
            }
        }

        /// One of the repo's PowerShell scripts, run as its README shows, with the bundled toolchain.
        private int RunPs(string script, string args, int timeoutSec)
        {
            string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            return Run(ps, "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Q(Path.Combine(repo, script)) + " " + args,
                repo, timeoutSec, null, true, null);
        }

        private int RunCmd(string commandLine, string cwd, int timeoutSec)
        {
            string cmd = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
            return Run(cmd, "/d /c " + commandLine, cwd, timeoutSec, null, true, null);
        }

        private static string Q(string s) { return "\"" + s + "\""; }

        // ================================================================== step 2 checks and setup

        private void SetCheck(int i, CheckResult r)
        {
            UI(delegate
            {
                ListViewItem it = checks.Items[i];
                it.SubItems[1].Text = r.Ok ? "OK" : "Missing";
                it.SubItems[2].Text = r.Detail;
                it.ForeColor = r.Ok ? Green : Red;
            });
        }

        private CheckResult CheckPython()
        {
            if (!File.Exists(pyBase)) return new CheckResult(false, "python\\python.exe not found");
            StringBuilder sb = new StringBuilder();
            int rc = Run(pyBase, "--version", null, 30, sb, false, null);
            return new CheckResult(rc == 0, sb.ToString().Trim());
        }

        private CheckResult CheckJdk()
        {
            string java = Path.Combine(jdk, @"bin\java.exe");
            if (!File.Exists(java)) return new CheckResult(false, "jdk\\bin\\java.exe not found");
            if (!File.Exists(Path.Combine(jdk, @"bin\javac.exe")) || !File.Exists(Path.Combine(jdk, @"bin\jlink.exe")))
                return new CheckResult(false, "JDK is incomplete (javac/jlink missing)");
            StringBuilder sb = new StringBuilder();
            Run(java, "-version", null, 30, sb, false, null);
            Match m = Regex.Match(sb.ToString(), "version \"(\\d+)([^\"]*)\"");
            if (!m.Success) return new CheckResult(false, "could not read java -version");
            int major = int.Parse(m.Groups[1].Value);
            bool ok = major >= 17 && major <= 22;
            return new CheckResult(ok, "Java " + m.Groups[1].Value + m.Groups[2].Value + (ok ? "" : " (needs 17-22)"));
        }

        private CheckResult CheckPlatform()
        {
            return File.Exists(Path.Combine(sdk, @"platforms\android-34\android.jar")) ? new CheckResult(true, "platforms\\android-34") : new CheckResult(false, "android-34 not found");
        }

        private CheckResult CheckBuildTools()
        {
            string bt = Path.Combine(sdk, "build-tools");
            if (Directory.Exists(bt))
                foreach (string d in Directory.GetDirectories(bt, "34.*"))
                    if (File.Exists(Path.Combine(d, "aapt2.exe")) || File.Exists(Path.Combine(d, "aapt.exe")))
                        return new CheckResult(true, "build-tools\\" + Path.GetFileName(d));
            return new CheckResult(false, "build-tools 34.x not found");
        }

        private CheckResult CheckPlatformTools()
        {
            if (!File.Exists(Path.Combine(sdk, @"platform-tools\adb.exe"))) return new CheckResult(false, "platform-tools\\adb.exe not found");
            return new CheckResult(true, "adb " + ReadProp(Path.Combine(sdk, @"platform-tools\source.properties"), "Pkg.Revision"));
        }

        private CheckResult CheckLicences()
        {
            return File.Exists(Path.Combine(sdk, @"licenses\android-sdk-license")) ? new CheckResult(true, "accepted at bundle time") : new CheckResult(false, "licenses\\android-sdk-license missing");
        }

        private CheckResult CheckRepo()
        {
            if (!File.Exists(Path.Combine(repo, @"tools\tv.py")) || !File.Exists(Path.Combine(launcherDir, "gradlew.bat"))
                || !File.Exists(Path.Combine(repo, @"tools\disable.ps1")))
                return new CheckResult(false, "cleanyourtv folder incomplete");
            string info = Path.Combine(appDir, "bundle-info.txt");
            string commit = ReadProp(info, "repo_commit");
            int lists = 0;
            try { lists = Directory.GetDirectories(Path.Combine(repo, "examples")).Length; } catch { }
            return new CheckResult(true, string.Format("snapshot {0} {1}, {2} tested TVs", commit.Length > 10 ? commit.Substring(0, 10) : commit, ReadProp(info, "repo_date"), lists));
        }

        private CheckResult CheckGradleDist()
        {
            string dists = Path.Combine(gradleHome, @"wrapper\dists\gradle-8.9-bin");
            if (Directory.Exists(dists))
                foreach (string h in Directory.GetDirectories(dists))
                    if (File.Exists(Path.Combine(h, @"gradle-8.9\bin\gradle.bat"))) return new CheckResult(true, "gradle-8.9 (pre-extracted)");
            return new CheckResult(false, "Gradle 8.9 not found in gradle-home");
        }

        private CheckResult CheckGradleCache()
        {
            if (!Directory.Exists(Path.Combine(gradleHome, @"caches\modules-2\files-2.1\com.android.tools.build\gradle\8.5.2")))
                return new CheckResult(false, "Android Gradle Plugin 8.5.2 not cached");
            int groups = 0;
            try { groups = Directory.GetDirectories(Path.Combine(gradleHome, @"caches\modules-2\files-2.1")).Length; } catch { }
            return new CheckResult(true, "AGP 8.5.2 + " + groups + " Maven groups cached");
        }

        private CheckResult CheckLocalProps()
        {
            string lp = Path.Combine(launcherDir, "local.properties");
            if (!File.Exists(lp)) return new CheckResult(false, "not written yet");
            string v = ReadProp(lp, "sdk.dir").Replace("\\\\", "\\").Replace("\\:", ":");
            bool ok = string.Equals(v.TrimEnd('\\'), sdk.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
            return new CheckResult(ok, ok ? "points at the bundled SDK" : "points elsewhere: " + v);
        }

        private CheckResult CheckVenv()
        {
            if (!File.Exists(venvPy)) return new CheckResult(false, "tools\\venv not created yet");
            StringBuilder sb = new StringBuilder();
            int rc = Run(venvPy, "-I -c \"import adb_shell, rsa, cryptography, sys; print('Python', sys.version.split()[0], '| cryptography', cryptography.__version__)\"",
                repo, 60, sb, false, null);
            return rc != 0 ? new CheckResult(false, "venv broken or packages missing") : new CheckResult(true, sb.ToString().Trim());
        }

        private bool RecheckAll()
        {
            CheckResult[] r = new CheckResult[] {
                CheckPython(), CheckJdk(), CheckPlatform(), CheckBuildTools(), CheckPlatformTools(), CheckLicences(),
                CheckRepo(), CheckGradleDist(), CheckGradleCache(), CheckLocalProps(), CheckVenv() };
            bool all = true;
            for (int i = 0; i < r.Length; i++) { SetCheck(i, r[i]); if (!r[i].Ok) all = false; }
            MarkDone(P_SETUP, all);
            UI(delegate
            {
                if (all) SetResult(p2Result, "All parts are in place. Press Next.", Green);
                else SetResult(p2Result, "Some parts are not ready yet (red above). Press 'Run the setup again'; if a part stays missing, reinstall the app.", Red);
            });
            if (all) { try { File.WriteAllText(marker, "Step 2 completed " + DateTime.Now.ToString("yyyy-MM-dd HH:mm") + "\r\n"); } catch { } }
            return all;
        }

        private bool DoSetup()
        {
            Log("=== Step 2: setting up the tools (offline) ===", Navy);
            CheckResult[] fixedParts = new CheckResult[] {
                CheckPython(), CheckJdk(), CheckPlatform(), CheckBuildTools(), CheckPlatformTools(), CheckLicences(),
                CheckRepo(), CheckGradleDist(), CheckGradleCache() };
            bool missing = false;
            for (int i = 0; i < fixedParts.Length; i++)
            {
                SetCheck(i, fixedParts[i]);
                if (!fixedParts[i].Ok) { missing = true; Log("  missing: " + CheckNames[i] + "  " + fixedParts[i].Detail, Red); }
            }
            if (missing)
            {
                Log("Part of the bundle is missing. Re-run the installer (it repairs the folder); this app never downloads anything.", Red);
                UI(delegate { SetResult(p2Result, "Part of the app's folder is missing. Run the installer again to repair it.", Red); });
                return false;
            }
            string lp = Path.Combine(launcherDir, "local.properties");
            File.WriteAllText(lp, "sdk.dir=" + sdk.Replace("\\", "\\\\") + "\r\n", Encoding.ASCII);
            Log("Wrote launcher\\local.properties -> " + sdk);
            SetCheck(9, CheckLocalProps());
            CheckResult v = CheckVenv();
            if (!v.Ok && Directory.Exists(venvDir))
            {
                Log("The existing Python environment does not work (folder moved?) - recreating it.", Orange);
                try { Directory.Delete(venvDir, true); } catch (Exception ex) { Log("  could not remove it: " + ex.Message, Red); return false; }
            }
            if (!v.Ok)
            {
                if (Run(pyBase, "-m venv " + Q(venvDir), repo, 300, null, true, null) != 0) { Log("Creating the Python environment failed.", Red); return false; }
                int rc = Run(venvPy, "-m pip install --no-index --find-links " + Q(wheels) + " -r " + Q(Path.Combine(repo, @"tools\requirements.txt")) + " --no-warn-script-location",
                    repo, 600, null, true, null);
                if (rc != 0) { Log("Installing the Python packages from the bundle failed.", Red); return false; }
            }
            SetCheck(10, CheckVenv());
            Log("Starting Gradle offline (the first start takes a minute)...");
            if (RunCmd("gradlew.bat --offline --version --console=plain", launcherDir, 600) != 0) { Log("Gradle could not start offline.", Red); return false; }
            return RecheckAll();
        }

        private bool TestBuild()
        {
            Log("=== Offline test build of the home screen (nothing is sent to the TV) ===", Navy);
            if (!File.Exists(Path.Combine(launcherDir, "local.properties"))) { Log("Run the setup first.", Red); return false; }
            Stopwatch sw = Stopwatch.StartNew();
            int rc = RunCmd("gradlew.bat assembleRelease --offline --console=plain", launcherDir, 1800);
            string apk = Path.Combine(launcherDir, @"app\build\outputs\apk\release\app-release.apk");
            if (rc == 0 && File.Exists(apk))
            {
                Log(string.Format("Build OK in {0:0} s: app-release.apk, {1} KB. The toolchain works fully offline.", sw.Elapsed.TotalSeconds, new FileInfo(apk).Length / 1024), Green);
                return true;
            }
            Log("The offline build failed (exit " + rc + ").", Red);
            return false;
        }

        // ================================================================== misc

        private void OpenShell()
        {
            string ps1 = Path.Combine(appDir, "Open-CleanYourTV-Shell.ps1");
            if (!File.Exists(ps1)) { MessageBox.Show(this, "Open-CleanYourTV-Shell.ps1 is missing; reinstall.", AppName); return; }
            string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            string ip = TvIp;
            ProcessStartInfo psi = new ProcessStartInfo(ps, "-NoExit -NoProfile -ExecutionPolicy Bypass -File " + Q(ps1) + (ip.Length > 0 ? " -TvHost " + Q(ip) : ""));
            psi.UseShellExecute = true;
            psi.WorkingDirectory = repo;
            try { Process.Start(psi); } catch (Exception ex) { MessageBox.Show(this, ex.Message, AppName); }
        }

        private void ShowAbout()
        {
            string info = "";
            try { info = File.ReadAllText(Path.Combine(appDir, "bundle-info.txt")); } catch { }
            MessageBox.Show(this,
                AppName + " " + AppVersion + "\r\nby Sasanka Boruah, VU3INI  -  " + Email + "\r\n\r\n" +
                "A step-by-step, offline front end for CleanYourTV (github.com/Gathin23/cleanyourtv): it prepares the tools, " +
                "finds the tested list for your TV, lets you choose what to keep, cleans the TV, installs the new home screen, and can undo it all.\r\n\r\n" +
                "Bundled: CleanYourTV (MIT, Gathin23), Python (PSF licence), Eclipse Temurin JDK (GPLv2 + Classpath Exception), " +
                "Android SDK components (Android SDK Licence), Gradle (Apache 2.0) and its Maven dependencies. " +
                "See THIRD-PARTY-NOTICES.txt in the install folder.\r\n\r\n" + info,
                "About " + AppName, MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private static string ReadProp(string file, string key)
        {
            try
            {
                if (!File.Exists(file)) return "";
                foreach (string line in File.ReadAllLines(file))
                {
                    int eq = line.IndexOf('=');
                    if (eq > 0 && line.Substring(0, eq).Trim() == key) return line.Substring(eq + 1).Trim();
                }
            }
            catch { }
            return "";
        }
    }
}
