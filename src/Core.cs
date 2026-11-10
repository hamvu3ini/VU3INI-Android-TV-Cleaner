// VU3INI Android TV Cleaner - logic that does not touch the UI: the TV list index, debloat list parsing and
// generation, matching a TV to a tested list, the launcher theme merge, and the settings file.
// C# 5 (the compiler built into Windows): no $"", ?. , nameof, expression bodies.
//
// Author: Sasanka Boruah, VU3INI  <hamvu3ini@gmail.com>

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace Vu3ini.AndroidTvCleaner
{
    /// One tested TV in the repo's examples\ folder.
    public sealed class ExampleInfo
    {
        public string Folder = "";
        public string Dir = "";
        public string Brand = "";
        public string Tv = "";
        public string Os = "";
        public string Notes = "";
        public List<string> Lists = new List<string>();   // file names: debloat.txt first, then debloat-*.txt
        public bool HasConfig;
        public override string ToString() { return Tv; }
    }

    /// One package line of a debloat list.
    public sealed class ListEntry
    {
        public string Package = "";
        public string Comment = "";
        public string Section = "";
        public bool DefaultDisable;   // true: an active line in the tested list; false: the list author kept it (commented)
        public bool Locked;           // core Android / TV middleware: never disabled (disable.ps1 refuses it too)
        public bool Disable;          // the user's choice
        public string Status = "";    // on the TV: "enabled", "already disabled", "not installed", "" (unknown)
    }

    /// What the probe read from the TV.
    public sealed class TvInfo
    {
        public string Model = "", Device = "", Manufacturer = "", Android = "", Sdk = "", Firmware = "", HomePackage = "";
        public HashSet<string> Installed = new HashSet<string>();
        public HashSet<string> Disabled = new HashSet<string>();
        public HashSet<string> ThirdParty = new HashSet<string>();
        public List<string> Leanback = new List<string>();
        public bool HasPackages { get { return Installed.Count > 0; } }
    }

    /// A "keep everything of this kind" switch on the What-to-keep page.
    public sealed class KeepCategory
    {
        public string Name;
        public string[] PackageWords;
        public string[] CommentWords;
        public KeepCategory(string name, string[] pkg, string[] comment) { Name = name; PackageWords = pkg; CommentWords = comment; }

        public bool Matches(ListEntry e)
        {
            string p = e.Package.ToLowerInvariant();
            string c = e.Comment.ToLowerInvariant();
            foreach (string w in PackageWords) if (p.Contains(w)) return true;
            foreach (string w in CommentWords) if (c.Contains(w)) return true;
            return false;
        }
    }

    public static class Core
    {
        // Same guard as tools\disable.ps1 / recovery.py: these are never disabled.
        public static readonly Regex CoreRe = new Regex(
            @"^(android|android\.ext\.(services|shared)|com\.android\.sdksandbox|com\.android\.location\.fused|com\.android\.systemui|com\.android\.shell|com\.android\.phone|com\.android\.settings|com\.android\.tv\.settings|com\.(google\.)?android\.(permissioncontroller|packageinstaller|ext\.services|ext\.shared|modulemetadata)|com\.google\.android\.overlay\.modules.*|com\.android\.providers\..*|com\.cltv\.mal|com\.mediatek\.(tis|tv\.service|tv\.agent))$");
        public static readonly Regex CoreOk = new Regex(@"^com\.android\.providers\.(calendar|contacts|userdictionary|blockednumber)$");
        public const string PkgPattern = @"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+";
        public static readonly Regex PkgRe = new Regex("^" + PkgPattern + "$");
        private static readonly Regex ActiveLine = new Regex(@"^(" + PkgPattern + @")\s*(?:#\s*(.*))?$");
        private static readonly Regex CommentedLine = new Regex(@"^#\s*(" + PkgPattern + @")\s*(?:#\s*(.*))?$");

        public const string LauncherPackage = "com.gathin.tvhome";
        public static readonly string[] KnownStockLaunchers = new string[] {
            "com.google.android.tvlauncher", "com.google.android.apps.tv.launcherx",
            "com.google.android.leanbacklauncher", "com.mitv.tvhome" };

        // Live TV apps seen in the tested lists, used to pre-fill the home screen's Inputs menu.
        public static readonly string[] KnownLiveTv = new string[] {
            "com.heytap.tv.livetv", "com.oneplus.tv.android.livetv", "com.mediatek.wwtv.tvcenter", "com.vt.tv.tvcenter",
            "com.sony.dtv.tvx", "com.tcl.tv", "com.tcl.tvinput", "com.xiaomi.mitv.tvplayer", "com.mitv.tvplayer",
            "com.droidlogic.tvsource", "com.realtek.tv", "com.google.android.tv", "com.android.tv" };

        public static readonly KeepCategory[] KeepCategories = new KeepCategory[] {
            new KeepCategory("Casting and screen mirroring",
                new string[] { "mediashell", "miracast", "mirror", "cast", "dlna", "airplay", "ars.sink", "multiscreen" },
                new string[] { "chromecast", "cast", "mirror", "screen shar", "dlna", "airplay" }),
            new KeepCategory("USB media players and file manager",
                new string[] { "filebrowser", "filemanager", "gallery", "musicplayer", "videoplayer", "mediaplayer", "mediacenter", "photoplayer" },
                new string[] { "(usb)", " usb", "file manager", "media player", "music player", "video player", "gallery" }),
            new KeepCategory("Bluetooth speaker mode",
                new string[] { "btspeaker", "bluetooth" },
                new string[] { "bluetooth speaker", "bluetooth" }),
            new KeepCategory("Voice assistant",
                new string[] { "katniss", "alexa", "voice" },
                new string[] { "google assistant", "voice", "alexa", "assistant mic" }),
            new KeepCategory("Streaming apps",
                new string[] { "netflix", "youtube", "amazonvideo", "primevideo", "hotstar", "jiocinema", "spotify", "sonyliv",
                               "graymatrix.did", "zee5", "airtel", "disney", "hulu", "tubi", "pluto", "mxplayer", "apps.youtube.music",
                               "tvmusic", "android.videos", "movies" },
                new string[] { "netflix", "youtube", "prime video", "streaming", "play movies", "spotify" })
        };

        public static bool IsCore(string pkg) { return CoreRe.IsMatch(pkg) && !CoreOk.IsMatch(pkg); }

        // ------------------------------------------------------------------ JSON

        public static Dictionary<string, object> ReadJson(string path)
        {
            try
            {
                if (!File.Exists(path)) return null;
                JavaScriptSerializer js = new JavaScriptSerializer();
                js.MaxJsonLength = 16 * 1024 * 1024;
                return js.DeserializeObject(File.ReadAllText(path, Encoding.UTF8)) as Dictionary<string, object>;
            }
            catch { return null; }
        }

        public static string JsonString(Dictionary<string, object> d, string key)
        {
            object v;
            if (d != null && d.TryGetValue(key, out v) && v != null) return Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture);
            return "";
        }

        public static List<string> JsonStringList(Dictionary<string, object> d, string key)
        {
            List<string> r = new List<string>();
            object v;
            if (d != null && d.TryGetValue(key, out v))
            {
                object[] arr = v as object[];
                if (arr != null) foreach (object o in arr) if (o != null) r.Add(o.ToString());
            }
            return r;
        }

        // ------------------------------------------------------------------ examples index

        public static List<ExampleInfo> LoadExamples(string examplesDir)
        {
            List<ExampleInfo> all = new List<ExampleInfo>();
            if (!Directory.Exists(examplesDir)) return all;
            foreach (string dir in Directory.GetDirectories(examplesDir))
            {
                List<string> lists = new List<string>();
                foreach (string f in Directory.GetFiles(dir, "debloat*.txt")) lists.Add(Path.GetFileName(f));
                if (lists.Count == 0) continue;
                lists.Sort(delegate (string a, string b)
                {
                    if (a == "debloat.txt") return -1;
                    if (b == "debloat.txt") return 1;
                    return string.Compare(a, b, StringComparison.OrdinalIgnoreCase);
                });
                ExampleInfo ex = new ExampleInfo();
                ex.Folder = Path.GetFileName(dir);
                ex.Dir = dir;
                ex.Lists = lists;
                ex.HasConfig = File.Exists(Path.Combine(dir, "config.json"));
                Dictionary<string, object> j = ReadJson(Path.Combine(dir, "tv.json"));
                ex.Brand = JsonString(j, "brand");
                ex.Tv = JsonString(j, "tv");
                ex.Os = JsonString(j, "os");
                ex.Notes = JsonString(j, "notes");
                if (ex.Brand.Length == 0) ex.Brand = "Other";
                if (ex.Tv.Length == 0) ex.Tv = ex.Folder;
                all.Add(ex);
            }
            all.Sort(delegate (ExampleInfo a, ExampleInfo b) { return string.Compare(a.Tv, b.Tv, StringComparison.OrdinalIgnoreCase); });
            return all;
        }

        /// Brands with their list counts, sorted by name (case-insensitive, first spelling wins).
        public static SortedDictionary<string, int> Brands(List<ExampleInfo> all)
        {
            SortedDictionary<string, int> r = new SortedDictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (ExampleInfo e in all)
            {
                int n;
                r.TryGetValue(e.Brand, out n);
                r[e.Brand] = n + 1;
            }
            return r;
        }

        private static bool ContainsWord(string hay, string word)
        {
            if (word.Length == 0) return false;
            return Regex.IsMatch(hay, "(^|[^a-z0-9])" + Regex.Escape(word) + "($|[^a-z0-9])");
        }

        /// The tested list that best fits the probed TV, or null. score >= 5 means the device codename or the
        /// model name was found; lower scores are brand-only and are not offered as a match.
        public static ExampleInfo BestMatch(List<ExampleInfo> all, TvInfo tv, out int bestScore)
        {
            bestScore = 0;
            ExampleInfo best = null;
            if (tv == null) return null;
            string man = tv.Manufacturer.Trim().ToLowerInvariant();
            string dev = tv.Device.Trim().ToLowerInvariant();
            string model = tv.Model.Trim().ToLowerInvariant();
            List<string> modelTokens = new List<string>();
            foreach (string t in Regex.Split(model, "[^a-z0-9]+"))
                if (t.Length >= 3 && Regex.IsMatch(t, "[0-9]")) modelTokens.Add(t);
            foreach (ExampleInfo e in all)
            {
                string hay = (e.Folder.Replace('-', ' ') + " " + e.Tv).ToLowerInvariant();
                string brand = e.Brand.ToLowerInvariant();
                int s = 0;
                if (man.Length > 1 && (brand.Contains(man) || man.Contains(brand) || hay.Contains(man))) s += 2;
                if (dev.Length >= 3 && ContainsWord(hay, dev)) s += 5;
                if (model.Length >= 3 && ContainsWord(hay, model)) s += 4;
                else
                {
                    int tokenScore = 0;
                    foreach (string t in modelTokens) if (ContainsWord(hay, t)) tokenScore += 2;
                    s += Math.Min(tokenScore, 4);
                }
                if (s > bestScore) { bestScore = s; best = e; }
            }
            return bestScore >= 5 ? best : null;
        }

        /// The brand that matches the TV's manufacturer, or "".
        public static string BrandFor(List<ExampleInfo> all, TvInfo tv)
        {
            if (tv == null) return "";
            string man = tv.Manufacturer.Trim().ToLowerInvariant();
            if (man.Length < 2) return "";
            foreach (ExampleInfo e in all) if (e.Brand.ToLowerInvariant() == man) return e.Brand;
            foreach (ExampleInfo e in all)
            {
                string b = e.Brand.ToLowerInvariant();
                if (b.Contains(man) || man.Contains(b)) return e.Brand;
            }
            return "";
        }

        // ------------------------------------------------------------------ debloat lists

        public static List<ListEntry> ParseList(string path)
        {
            List<ListEntry> entries = new List<ListEntry>();
            HashSet<string> seen = new HashSet<string>();
            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            string section = "General";
            for (int i = 0; i < lines.Length; i++)
            {
                string t = lines[i].Trim();
                if (t.Length == 0) continue;
                Match m = ActiveLine.Match(t);
                bool active = m.Success;
                if (!active) m = CommentedLine.Match(t);
                if (m.Success)
                {
                    string pkg = m.Groups[1].Value;
                    if (seen.Contains(pkg)) continue;
                    seen.Add(pkg);
                    ListEntry e = new ListEntry();
                    e.Package = pkg;
                    e.Comment = m.Groups[2].Success ? m.Groups[2].Value.Trim() : "";
                    e.Section = section;
                    e.Locked = IsCore(pkg);
                    e.DefaultDisable = active && !e.Locked;
                    e.Disable = e.DefaultDisable;
                    entries.Add(e);
                    continue;
                }
                // A section heading: a comment right after a blank line and right before a package line.
                if (t.StartsWith("#") && (i == 0 || lines[i - 1].Trim().Length == 0) && i + 1 < lines.Length)
                {
                    string next = lines[i + 1].Trim();
                    if (ActiveLine.IsMatch(next) || CommentedLine.IsMatch(next))
                    {
                        string h = t.TrimStart('#').Trim();
                        if (h.Length > 0) section = h.Length > 90 ? h.Substring(0, 87) + "..." : h;
                    }
                }
            }
            return entries;
        }

        public static void ApplyStatus(List<ListEntry> entries, TvInfo tv)
        {
            foreach (ListEntry e in entries)
            {
                if (tv == null || !tv.HasPackages) e.Status = "";
                else if (!tv.Installed.Contains(e.Package)) e.Status = "not installed";
                else if (tv.Disabled.Contains(e.Package)) e.Status = "already disabled";
                else e.Status = "enabled";
            }
        }

        /// The list the user chose: the tested list with every line they kept commented out and every line they
        /// turned on uncommented. Comments and order stay as in the tested list.
        public static string BuildList(string sourcePath, List<ListEntry> entries, string sourceLabel)
        {
            Dictionary<string, ListEntry> byPkg = new Dictionary<string, ListEntry>();
            foreach (ListEntry e in entries) if (!byPkg.ContainsKey(e.Package)) byPkg[e.Package] = e;
            HashSet<string> written = new HashSet<string>();
            StringBuilder sb = new StringBuilder();
            int on = 0;
            foreach (ListEntry e in entries) if (e.Disable && !e.Locked) on++;
            sb.AppendLine("# Generated by VU3INI Android TV Cleaner on " + DateTime.Now.ToString("yyyy-MM-dd HH:mm"));
            sb.AppendLine("# From: " + sourceLabel);
            sb.AppendLine("# " + on + " packages to disable. Lines marked 'kept by your choice' stay enabled.");
            sb.AppendLine("# Change the choices in the app (step 5), not here: the app rewrites this file.");
            sb.AppendLine("#");
            foreach (string raw in File.ReadAllLines(sourcePath, Encoding.UTF8))
            {
                string t = raw.Trim();
                Match m = ActiveLine.Match(t);
                bool active = m.Success;
                if (!active) m = CommentedLine.Match(t);
                if (!m.Success) { sb.AppendLine(raw); continue; }
                string pkg = m.Groups[1].Value;
                string comment = m.Groups[2].Success ? m.Groups[2].Value.Trim() : "";
                ListEntry e;
                if (!byPkg.TryGetValue(pkg, out e) || written.Contains(pkg)) { sb.AppendLine(active ? "# " + raw : raw); continue; }
                written.Add(pkg);
                bool disable = e.Disable && !e.Locked;
                if (disable)
                {
                    if (active) sb.AppendLine(raw);
                    else sb.AppendLine(pkg.PadRight(44) + " # " + (comment.Length > 0 ? comment + " " : "") + "(disabled by your choice)");
                }
                else
                {
                    if (active) sb.AppendLine("# " + pkg.PadRight(42) + " # " + (comment.Length > 0 ? comment + " " : "") + "(kept by your choice)");
                    else sb.AppendLine(raw);
                }
            }
            return sb.ToString();
        }

        public static int CountDisable(List<ListEntry> entries)
        {
            int n = 0;
            foreach (ListEntry e in entries) if (e.Disable && !e.Locked) n++;
            return n;
        }

        // ------------------------------------------------------------------ probe

        /// Splits tv.py --batch output ("$ command" then its output) into command -> output.
        public static Dictionary<string, string> SplitBatch(string output)
        {
            Dictionary<string, string> r = new Dictionary<string, string>();
            string cur = null;
            StringBuilder sb = new StringBuilder();
            foreach (string line in output.Replace("\r\n", "\n").Split('\n'))
            {
                if (line.StartsWith("$ "))
                {
                    if (cur != null) r[cur] = sb.ToString();
                    cur = line.Substring(2).Trim();
                    sb.Length = 0;
                }
                else if (cur != null) sb.AppendLine(line);
            }
            if (cur != null) r[cur] = sb.ToString();
            return r;
        }

        public static readonly string[] ProbeCommands = new string[] {
            "getprop ro.product.model",
            "getprop ro.product.device",
            "getprop ro.product.manufacturer",
            "getprop ro.build.version.release",
            "getprop ro.build.version.sdk",
            "getprop ro.build.display.id",
            "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME",
            "pm list packages",
            "pm list packages -d",
            "pm list packages -3",
            "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER"
        };

        private static string Get(Dictionary<string, string> d, string k)
        {
            string v;
            return d.TryGetValue(k, out v) ? v.Trim() : "";
        }

        private static void ReadPackages(string text, HashSet<string> into)
        {
            foreach (string l in text.Replace("\r", "").Split('\n'))
            {
                string t = l.Trim();
                if (t.StartsWith("package:"))
                {
                    string p = t.Substring(8).Trim();
                    if (PkgRe.IsMatch(p)) into.Add(p);
                }
            }
        }

        public static TvInfo ParseProbe(string output)
        {
            Dictionary<string, string> d = SplitBatch(output);
            TvInfo tv = new TvInfo();
            tv.Model = Get(d, ProbeCommands[0]);
            tv.Device = Get(d, ProbeCommands[1]);
            tv.Manufacturer = Get(d, ProbeCommands[2]);
            tv.Android = Get(d, ProbeCommands[3]);
            tv.Sdk = Get(d, ProbeCommands[4]);
            tv.Firmware = Get(d, ProbeCommands[5]);
            Regex comp = new Regex(@"(" + PkgPattern + @")/");
            foreach (string l in Get(d, ProbeCommands[6]).Replace("\r", "").Split('\n'))
            {
                Match m = comp.Match(l.Trim());
                if (m.Success) tv.HomePackage = m.Groups[1].Value;   // last component line wins
            }
            ReadPackages(Get(d, ProbeCommands[7]), tv.Installed);
            ReadPackages(Get(d, ProbeCommands[8]), tv.Disabled);
            ReadPackages(Get(d, ProbeCommands[9]), tv.ThirdParty);
            Regex named = new Regex(@"packageName=(" + PkgPattern + ")");
            foreach (string l in Get(d, ProbeCommands[10]).Replace("\r", "").Split('\n'))
            {
                string t = l.Trim();
                Match m = comp.Match(t);
                if (!m.Success || m.Index != 0) m = named.Match(t);
                if (m.Success)
                {
                    string p = m.Groups[1].Value;
                    if (!tv.Leanback.Contains(p)) tv.Leanback.Add(p);
                }
            }
            return tv;
        }

        // ------------------------------------------------------------------ launcher theme

        private static void CopyDir(string from, string to)
        {
            Directory.CreateDirectory(to);
            foreach (string f in Directory.GetFiles(from))
            {
                string n = Path.GetFileName(f);
                if (n.Equals("screenshot.jpg", StringComparison.OrdinalIgnoreCase) || n.Equals("config.json", StringComparison.OrdinalIgnoreCase)
                    || n.EndsWith(".md", StringComparison.OrdinalIgnoreCase)) continue;
                File.Copy(f, Path.Combine(to, n), true);
            }
            foreach (string d in Directory.GetDirectories(from)) CopyDir(d, Path.Combine(to, Path.GetFileName(d)));
        }

        /// Builds the theme folder pushed with tools\theme.ps1: the chosen theme's files and config, overlaid with
        /// the tested TV's config.json (its dock, Live TV app and remote-key fixes), overlaid with the user's
        /// choices. A null value in overrides removes that key.
        public static Dictionary<string, object> BuildTheme(string themeDir, string exampleConfig, Dictionary<string, object> overrides, string outDir)
        {
            if (Directory.Exists(outDir)) Directory.Delete(outDir, true);
            Directory.CreateDirectory(outDir);
            Dictionary<string, object> cfg = new Dictionary<string, object>();
            if (!string.IsNullOrEmpty(themeDir) && Directory.Exists(themeDir))
            {
                CopyDir(themeDir, outDir);
                Dictionary<string, object> t = ReadJson(Path.Combine(themeDir, "config.json"));
                if (t != null) foreach (KeyValuePair<string, object> kv in t) cfg[kv.Key] = kv.Value;
            }
            Dictionary<string, object> ex = string.IsNullOrEmpty(exampleConfig) ? null : ReadJson(exampleConfig);
            if (ex != null) foreach (KeyValuePair<string, object> kv in ex) cfg[kv.Key] = kv.Value;
            foreach (KeyValuePair<string, object> kv in overrides)
            {
                if (kv.Value == null) cfg.Remove(kv.Key);
                else cfg[kv.Key] = kv.Value;
            }
            JavaScriptSerializer js = new JavaScriptSerializer();
            File.WriteAllText(Path.Combine(outDir, "config.json"), PrettyJson(js.Serialize(cfg)), new UTF8Encoding(false));
            return cfg;
        }

        /// Indents compact JSON so the file is readable; strings are copied verbatim.
        public static string PrettyJson(string json)
        {
            StringBuilder sb = new StringBuilder();
            int indent = 0;
            bool inStr = false;
            for (int i = 0; i < json.Length; i++)
            {
                char c = json[i];
                if (inStr)
                {
                    sb.Append(c);
                    if (c == '\\' && i + 1 < json.Length) { sb.Append(json[++i]); }
                    else if (c == '"') inStr = false;
                    continue;
                }
                switch (c)
                {
                    case '"': inStr = true; sb.Append(c); break;
                    case '{':
                    case '[':
                        if (i + 1 < json.Length && (json[i + 1] == '}' || json[i + 1] == ']')) { sb.Append(c).Append(json[++i]); break; }
                        sb.Append(c); indent++; sb.Append('\n').Append(' ', indent * 2); break;
                    case '}':
                    case ']':
                        indent--; sb.Append('\n').Append(' ', indent * 2).Append(c); break;
                    case ',': sb.Append(c).Append('\n').Append(' ', indent * 2); break;
                    case ':': sb.Append(": "); break;
                    default: sb.Append(c); break;
                }
            }
            return sb.ToString() + "\n";
        }
    }

    /// key=value settings in %APPDATA%\VU3INI\AndroidTVCleaner\settings.txt
    public sealed class Settings
    {
        private readonly string file;
        private readonly Dictionary<string, string> values = new Dictionary<string, string>();

        public Settings(string file)
        {
            this.file = file;
            try
            {
                if (File.Exists(file))
                    foreach (string line in File.ReadAllLines(file, Encoding.UTF8))
                    {
                        int eq = line.IndexOf('=');
                        if (eq > 0) values[line.Substring(0, eq)] = line.Substring(eq + 1);
                    }
            }
            catch { }
        }

        public string Get(string key) { string v; return values.TryGetValue(key, out v) ? v : ""; }
        public bool GetBool(string key) { return Get(key) == "1"; }

        public void Set(string key, string value)
        {
            values[key] = (value ?? "").Replace("\r", " ").Replace("\n", " ");
            Save();
        }

        public void SetBool(string key, bool v) { Set(key, v ? "1" : "0"); }

        private void Save()
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(file));
                List<string> lines = new List<string>();
                foreach (KeyValuePair<string, string> kv in values) lines.Add(kv.Key + "=" + kv.Value);
                lines.Sort(StringComparer.Ordinal);
                File.WriteAllLines(file, lines.ToArray(), new UTF8Encoding(false));
            }
            catch { }
        }
    }
}
