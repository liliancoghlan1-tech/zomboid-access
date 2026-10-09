// Zomboid Access Setup: installs, updates, reinstalls and uninstalls Zomboid Access.
// It checks GitHub for the newest release (pre-releases too: every Zomboid Access release so far is one), compares
// it with the version installed (Zomboid\mods\ZomboidAccess\42\mod.info), and, when there is a newer one, shows its
// release notes and asks before updating. An update replaces only the files that changed (compared by content),
// removes files the new version no longer has, and never touches your settings (the bridge's voices.json, the mod's
// Zomboid\Lua\ZomboidAccess_options.txt).
// Standard Windows controls only, so screen readers read every part of it.
// Built with the C# compiler that comes with Windows (.NET Framework 4.x): see build.ps1 next to this file.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: System.Reflection.AssemblyTitle("Zomboid Access Setup")]
[assembly: System.Reflection.AssemblyProduct("Zomboid Access")]
[assembly: System.Reflection.AssemblyVersion("0.9.3.0")]

namespace ZomboidAccessSetup
{
    // ---------- where things are ----------

    static class Places
    {
        public const string Repo = "liliancoghlan1-tech/zomboid-access";
        public const string AppId = "108600";
        public const string ModId = "ZomboidAccess";

        static string Env(string name) { var v = Environment.GetEnvironmentVariable(name); return string.IsNullOrEmpty(v) ? null : v; }

        // The game's own folder for saves and mods: %USERPROFILE%\Zomboid, unless the launch options move it
        // with -cachedir=.
        static string cacheDir;
        public static string Zomboid
        {
            get
            {
                var test = Env("ZA_TEST_ZOMBOID");
                if (test != null) return test;
                if (cacheDir == null) cacheDir = Steam.CacheDir() ?? "";
                if (cacheDir != "") return cacheDir;
                return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Zomboid");
            }
        }
        public static string Mods { get { return Path.Combine(Zomboid, "mods"); } }
        public static string ModDir { get { return Path.Combine(Mods, ModId); } }
        public static string ModInfo { get { return Path.Combine(ModDir, "42", "mod.info"); } }

        // The speech bridge, this setup's own copy and the bridge's settings.
        public static string Home
        {
            get
            {
                var test = Env("ZA_TEST_LOCALAPPDATA");
                var local = test ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                return Path.Combine(local, "ZomboidAccess");
            }
        }
        public static string Bridge { get { return Path.Combine(Home, "ZomboidAccessBridge.exe"); } }
        public static string SetupCopy { get { return Path.Combine(Home, "ZomboidAccessSetup.exe"); } }
        public static string StartMenuLink
        {
            get
            {
                var test = Env("ZA_TEST_STARTMENU");
                var dir = test ?? Environment.GetFolderPath(Environment.SpecialFolder.Programs);
                return Path.Combine(dir, "Zomboid Access Setup.lnk");
            }
        }
        // Kept through updates and reinstalls: what the bridge saved next to itself, and this program.
        public static readonly string[] KeepInHome = { "voices.json", "bridge.log", "ZomboidAccessSetup.exe", "ZomboidAccessSetup.exe.old" };

        public static string InstalledVersion()
        {
            try
            {
                if (!File.Exists(ModInfo)) return null;
                foreach (var line in File.ReadAllLines(ModInfo))
                    if (line.StartsWith("modversion=")) return line.Substring("modversion=".Length).Trim();
            }
            catch (Exception) { }
            return "unknown";
        }
    }

    // ---------- versions ----------

    static class Versions
    {
        public static int[] Parse(string v)
        {
            var parts = new List<int>();
            if (v != null)
                foreach (Match m in Regex.Matches(v, @"\d+")) { int n; if (int.TryParse(m.Value, out n)) parts.Add(n); }
            while (parts.Count < 3) parts.Add(0);
            return parts.ToArray();
        }
        public static int Compare(string a, string b)
        {
            var x = Parse(a); var y = Parse(b);
            for (int i = 0; i < Math.Max(x.Length, y.Length); i++)
            {
                int p = i < x.Length ? x[i] : 0, q = i < y.Length ? y[i] : 0;
                if (p != q) return p < q ? -1 : 1;
            }
            return 0;
        }
    }

    // ---------- Steam ----------

    static class Steam
    {
        public static string Dir()
        {
            var test = Environment.GetEnvironmentVariable("ZA_TEST_STEAM_DIR");
            if (!string.IsNullOrEmpty(test)) return test;
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam"))
                {
                    var p = k == null ? null : k.GetValue("SteamPath") as string;
                    if (!string.IsNullOrEmpty(p)) return p.Replace('/', '\\');
                }
            }
            catch (Exception) { }
            return null;
        }

        public static bool Running()
        {
            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("ZA_TEST_STEAM_DIR"))) return false;
            return Process.GetProcessesByName("steam").Length > 0;
        }

        static string Unescape(string s) { return Regex.Replace(s, @"\\(.)", "$1"); }
        static string Escape(string s) { return s.Replace("\\", "\\\\").Replace("\"", "\\\""); }

        // Every Steam library, on any drive (steamapps\libraryfolders.vdf), the main one first.
        public static List<string> Libraries()
        {
            var libs = new List<string>();
            var steam = Dir();
            if (steam == null) return libs;
            libs.Add(steam);
            try
            {
                var vdf = Path.Combine(steam, "steamapps", "libraryfolders.vdf");
                if (File.Exists(vdf))
                    foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s*\"((?:[^\"\\\\]|\\\\.)*)\""))
                    {
                        var p = Unescape(m.Groups[1].Value);
                        if (!libs.Exists(l => string.Equals(Path.GetFullPath(l).TrimEnd('\\'), Path.GetFullPath(p).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)))
                            libs.Add(p);
                    }
            }
            catch (Exception) { }
            return libs;
        }

        // The game's folder, whichever drive it's on, or null.
        public static string FindGame()
        {
            foreach (var lib in Libraries())
            {
                try
                {
                    var acf = Path.Combine(lib, "steamapps", "appmanifest_" + Places.AppId + ".acf");
                    if (!File.Exists(acf)) continue;
                    var m = Regex.Match(File.ReadAllText(acf), "\"installdir\"\\s*\"([^\"]*)\"");
                    var dir = Path.Combine(lib, "steamapps", "common", m.Success ? m.Groups[1].Value : "ProjectZomboid");
                    if (Directory.Exists(dir)) return dir;
                }
                catch (Exception) { }
            }
            return null;
        }

        public static List<string> Configs()
        {
            var list = new List<string>();
            var steam = Dir();
            if (steam == null) return list;
            var users = Path.Combine(steam, "userdata");
            if (!Directory.Exists(users)) return list;
            foreach (var u in Directory.GetDirectories(users))
            {
                var f = Path.Combine(u, "config", "localconfig.vdf");
                if (File.Exists(f)) list.Add(f);
            }
            return list;
        }

        // The block that is the direct child `key` of the block whose contents run from `from` to `to`:
        // { index of "{", index of "}" } or null.
        static int[] FindChild(string text, int from, int to, string key)
        {
            int depth = 0, i = from; string last = null;
            while (i < to)
            {
                char c = text[i];
                if (c == '"')
                {
                    int j = i + 1;
                    while (j < to && text[j] != '"') { if (text[j] == '\\') j++; j++; }
                    if (depth == 0 && j <= to) last = text.Substring(i + 1, j - i - 1);
                    i = j + 1; continue;
                }
                if (c == '{')
                {
                    if (depth == 0 && last == key)
                    {
                        int d = 0;
                        for (int k = i; k < to; k++)
                        {
                            if (text[k] == '"') { k++; while (k < to && text[k] != '"') { if (text[k] == '\\') k++; k++; } }
                            else if (text[k] == '{') d++;
                            else if (text[k] == '}') { d--; if (d == 0) return new[] { i, k }; }
                        }
                        return null;
                    }
                    depth++; last = null;
                }
                else if (c == '}') { depth--; last = null; }
                i++;
            }
            return null;
        }

        static int[] AppBlock(string text)
        {
            var range = new[] { -1, text.Length };
            foreach (var key in new[] { "UserLocalConfigStore", "Software", "Valve", "Steam", "apps", Places.AppId })
            {
                range = FindChild(text, range[0] + 1, range[1], key);
                if (range == null) return null;
            }
            return range;
        }

        static readonly Regex LaunchRe = new Regex("\"LaunchOptions\"(\\s*)\"((?:[^\"\\\\]|\\\\.)*)\"");

        // Project Zomboid's launch options in one Steam account, or null if it never started the game.
        public static string LaunchOptions(string config)
        {
            var text = File.ReadAllText(config);
            var block = AppBlock(text);
            if (block == null) return null;
            var m = LaunchRe.Match(text.Substring(block[0], block[1] - block[0]));
            return m.Success ? Unescape(m.Groups[2].Value) : "";
        }

        // Sets them; returns false if this account never started the game. Keeps a copy of the old file.
        public static bool SetLaunchOptions(string config, string value)
        {
            var text = File.ReadAllText(config);
            var block = AppBlock(text);
            if (block == null) return false;
            int open = block[0], close = block[1];
            var m = LaunchRe.Match(text.Substring(open, close - open));
            var quoted = "\"" + Escape(value) + "\"";
            if (m.Success)
            {
                int start = open + m.Groups[2].Index - 1;
                text = text.Substring(0, start) + quoted + text.Substring(start + m.Groups[2].Length + 2);
            }
            else
            {
                int lineStart = text.LastIndexOf('\n', open) + 1;
                var indent = Regex.Match(text.Substring(lineStart, open - lineStart), "^\t*").Value + "\t";
                text = text.Substring(0, open + 1) + "\n" + indent + "\"LaunchOptions\"\t\t" + quoted + text.Substring(open + 1);
            }
            File.Copy(config, config + ".before-zomboid-access", true);
            File.WriteAllText(config, text, new UTF8Encoding(false));
            return true;
        }

        public static string BridgeOption() { return "\"" + Places.Bridge + "\" %command%"; }
        static readonly Regex OursRe = new Regex("^\\s*\"[^\"]*ZomboidAccessBridge\\.exe\"\\s*%command%\\s*", RegexOptions.IgnoreCase);
        public static string WithoutBridge(string options) { return OursRe.Replace(options ?? "", "").Trim(); }

        // -cachedir=... in any account's launch options (the game's folder moved).
        public static string CacheDir()
        {
            try
            {
                foreach (var c in Configs())
                {
                    var o = LaunchOptions(c);
                    if (o == null) continue;
                    var m = Regex.Match(o, "-cachedir=(\"[^\"]+\"|\\S+)");
                    if (m.Success) return Path.Combine(m.Groups[1].Value.Trim('"'), "Zomboid");
                }
            }
            catch (Exception) { }
            return null;
        }
    }

    // ---------- releases ----------

    class Release
    {
        public string Tag, Name, Notes, ZipUrl, LocalFolder;
        public bool Pre;
        public string Version { get { return Tag == null ? null : Tag.TrimStart('v', 'V'); } }

        static WebClient Client()
        {
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; // TLS 1.2
            var w = new WebClient();
            w.Headers[HttpRequestHeader.UserAgent] = "ZomboidAccessSetup";
            w.Encoding = Encoding.UTF8;
            return w;
        }

        // The newest release on GitHub, pre-releases included (drafts never).
        public static Release Newest()
        {
            string json;
            var test = Environment.GetEnvironmentVariable("ZA_TEST_RELEASES_JSON");
            if (!string.IsNullOrEmpty(test)) json = File.ReadAllText(test);
            else using (var w = Client()) json = w.DownloadString("https://api.github.com/repos/" + Places.Repo + "/releases?per_page=30");
            var list = new JavaScriptSerializer().Deserialize<List<Dictionary<string, object>>>(json);
            Release best = null;
            foreach (var r in list)
            {
                if (r.ContainsKey("draft") && r["draft"] is bool && (bool)r["draft"]) continue;
                var rel = new Release
                {
                    Tag = r["tag_name"] as string,
                    Name = r.ContainsKey("name") ? r["name"] as string : null,
                    Notes = r.ContainsKey("body") ? r["body"] as string : "",
                    Pre = r.ContainsKey("prerelease") && r["prerelease"] is bool && (bool)r["prerelease"],
                };
                var assets = r.ContainsKey("assets") ? r["assets"] as System.Collections.ArrayList : null;
                if (assets != null)
                    foreach (Dictionary<string, object> a in assets)
                    {
                        var name = a["name"] as string;
                        if (name != null && name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)) { rel.ZipUrl = a["browser_download_url"] as string; break; }
                    }
                if (rel.Tag == null || rel.ZipUrl == null) continue;
                if (best == null || Versions.Compare(rel.Version, best.Version) > 0) best = rel;
            }
            return best;
        }

        // Unpacks the release into `into`; returns the folder that holds "files".
        public string Fetch(string into, Action<string> say)
        {
            if (LocalFolder != null) return LocalFolder;
            var zip = Path.Combine(into, "release.zip");
            say("Downloading Zomboid Access " + Version + "...");
            var test = Environment.GetEnvironmentVariable("ZA_TEST_RELEASE_ZIP");
            if (!string.IsNullOrEmpty(test)) File.Copy(test, zip, true);
            else using (var w = Client()) w.DownloadFile(ZipUrl, zip);
            say("Unpacking...");
            var dir = Path.Combine(into, "release");
            ZipFile.ExtractToDirectory(zip, dir);
            var found = FindPackage(dir);
            if (found == null) throw new Exception("The download doesn't look like a Zomboid Access release (no files\\mods\\ZomboidAccess in it).");
            return found;
        }

        // A folder holding files\mods\ZomboidAccess, at most two levels down.
        public static string FindPackage(string dir)
        {
            if (Directory.Exists(Path.Combine(dir, "files", "mods", Places.ModId))) return dir;
            foreach (var sub in Directory.GetDirectories(dir))
            {
                if (Directory.Exists(Path.Combine(sub, "files", "mods", Places.ModId))) return sub;
                foreach (var sub2 in Directory.GetDirectories(sub))
                    if (Directory.Exists(Path.Combine(sub2, "files", "mods", Places.ModId))) return sub2;
            }
            return null;
        }

        // The release this program came in, if it was unzipped next to it: used when GitHub can't be reached,
        // or when it is as new as GitHub's (no download needed).
        public static Release Beside()
        {
            var here = Path.GetDirectoryName(Application.ExecutablePath);
            var pkg = FindPackage(here);
            if (pkg == null) return null;
            var info = Path.Combine(pkg, "files", "mods", Places.ModId, "42", "mod.info");
            string v = null;
            try { foreach (var l in File.ReadAllLines(info)) if (l.StartsWith("modversion=")) v = l.Substring(11).Trim(); }
            catch (Exception) { }
            if (v == null) return null;
            return new Release { Tag = "v" + v, Name = "Zomboid Access " + v + " (the copy in this folder)", Notes = "", LocalFolder = pkg };
        }
    }

    // ---------- copying only what changed ----------

    class SyncResult { public int Copied, Same, Removed; }

    static class Sync
    {
        static string Hash(string path)
        {
            using (var sha = SHA256.Create())
            using (var s = File.OpenRead(path))
                return Convert.ToBase64String(sha.ComputeHash(s));
        }

        static bool SameFile(string a, string b)
        {
            var fa = new FileInfo(a); var fb = new FileInfo(b);
            if (!fb.Exists || fa.Length != fb.Length) return false;
            return Hash(a) == Hash(b);
        }

        // Makes `to` hold what `from` holds: copies new and changed files (all of them when `everything`), and
        // removes files `from` doesn't have, except the names in `keep` (at the top of `to`).
        public static SyncResult Run(string from, string to, string[] keep, bool everything)
        {
            var r = new SyncResult();
            Directory.CreateDirectory(to);
            var wanted = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var src in Directory.GetFiles(from, "*", SearchOption.AllDirectories))
            {
                var rel = src.Substring(from.Length).TrimStart('\\');
                wanted.Add(rel);
                var dst = Path.Combine(to, rel);
                if (!everything && File.Exists(dst) && SameFile(src, dst)) { r.Same++; continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(dst));
                if (File.Exists(dst)) File.SetAttributes(dst, FileAttributes.Normal);
                File.Copy(src, dst, true);
                r.Copied++;
            }
            var kept = new HashSet<string>(keep ?? new string[0], StringComparer.OrdinalIgnoreCase);
            foreach (var dst in Directory.GetFiles(to, "*", SearchOption.AllDirectories))
            {
                var rel = dst.Substring(to.Length).TrimStart('\\');
                if (wanted.Contains(rel) || kept.Contains(rel)) continue;
                File.SetAttributes(dst, FileAttributes.Normal);
                File.Delete(dst);
                r.Removed++;
            }
            // folders left empty
            var dirs = Directory.GetDirectories(to, "*", SearchOption.AllDirectories);
            Array.Sort(dirs, (a, b) => b.Length.CompareTo(a.Length));
            foreach (var d in dirs)
                if (Directory.GetFileSystemEntries(d).Length == 0) Directory.Delete(d);
            return r;
        }
    }

    // ---------- installing ----------

    class Installer
    {
        readonly Action<string> say;
        public readonly List<string> Notes = new List<string>();
        public Installer(Action<string> say) { this.say = say; }

        // What must be true before changing anything. Returns a reason, or null.
        public static string Blocked()
        {
            if (Process.GetProcessesByName("ProjectZomboid64").Length > 0)
                return "Project Zomboid is running. Quit the game, then try again.";
            if (!Directory.Exists(Places.Zomboid))
                return "There is no Zomboid folder yet (" + Places.Zomboid + "). Start Project Zomboid once, wait about a minute, close it, then try again.";
            if (!File.Exists(Path.Combine(Places.Mods, "reset-mods-42_00.txt")))
                return "Start Project Zomboid once, wait about a minute, close it with Alt F4, then try again. "
                    + "(The game clears its mod list the first time it starts, so installing before that would be undone. "
                    + "The very first time it stops on a Terms of Service screen; closing it there is fine.)";
            return null;
        }

        static void StopBridge()
        {
            foreach (var p in Process.GetProcessesByName("ZomboidAccessBridge"))
                try { p.Kill(); p.WaitForExit(5000); } catch (Exception) { }
        }

        // Install or update (only what changed), or reinstall (everything).
        public void Install(Release release, bool everything)
        {
            var game = Steam.FindGame();
            Notes.Add(game != null ? "Found Project Zomboid in " + game + "."
                : "Couldn't find Project Zomboid in your Steam libraries. That's fine if it is installed somewhere else: the mod goes in your Zomboid folder (" + Places.Zomboid + "), not the game's.");

            var temp = Path.Combine(Path.GetTempPath(), "ZomboidAccessSetup-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temp);
            try
            {
                var pkg = release.Fetch(temp, say);
                var files = Path.Combine(pkg, "files");

                say("Installing the mod...");
                var mod = Sync.Run(Path.Combine(files, "mods", Places.ModId), Places.ModDir, null, everything);
                Notes.Add("Mod: " + Describe(mod) + " (" + Places.ModDir + ").");
                EnableMod();

                var bridgeFrom = Path.Combine(files, "ZomboidAccessBridge");
                if (Directory.Exists(bridgeFrom))
                {
                    say("Installing the speech bridge...");
                    StopBridge();
                    var b = Sync.Run(bridgeFrom, Places.Home, Places.KeepInHome, everything);
                    Notes.Add("Speech bridge: " + Describe(b) + " (" + Places.Home + "). Your voice settings are kept.");
                    SetLaunchOption();
                }
                else Notes.Add("This release has no speech bridge (it is older than 0.9.3 and uses an NVDA add-on): install that from the release's folder.");

                var setupFrom = Path.Combine(pkg, "ZomboidAccessSetup.exe");
                KeepSetup(File.Exists(setupFrom) ? setupFrom : Application.ExecutablePath);

                if (Directory.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "nvda", "addons", "zomboidAccess")))
                    Notes.Add("The old Zomboid Access NVDA add-on is still installed. Remove it, or everything is said twice: NVDA menu, Tools, Add-on store, Installed add-ons, Zomboid Access, Remove.");
            }
            finally
            {
                try { Directory.Delete(temp, true); } catch (Exception) { }
            }
        }

        static string Describe(SyncResult r)
        {
            var parts = new List<string>();
            parts.Add(r.Copied + (r.Copied == 1 ? " file" : " files") + " copied");
            if (r.Same > 0) parts.Add(r.Same + " already up to date");
            if (r.Removed > 0) parts.Add(r.Removed + " no longer needed, removed");
            return string.Join(", ", parts);
        }

        // "mod = ZomboidAccess," inside the mods block of mods\default.txt, keeping the player's other mods.
        void EnableMod()
        {
            var list = Path.Combine(Places.Mods, "default.txt");
            var line = "    mod = " + Places.ModId + ",";
            if (!File.Exists(list))
            {
                File.WriteAllText(list, "VERSION = 1,\n\nmods\n{\n" + line + "\n}\n\nmaps\n{\n}\n", new UTF8Encoding(false));
                return;
            }
            var lines = new List<string>(File.ReadAllLines(list));
            if (lines.Exists(l => Regex.IsMatch(l, @"^\s*mod\s*=\s*\\?" + Places.ModId + @"\s*,"))) return;
            var output = new List<string>();
            bool inMods = false, added = false;
            foreach (var l in lines)
            {
                output.Add(l);
                if (Regex.IsMatch(l, @"^\s*mods\s*$")) inMods = true;
                else if (inMods && !added && Regex.IsMatch(l, @"^\s*\{\s*$")) { output.Add(line); added = true; }
            }
            if (!added) { output.Add(""); output.Add("mods"); output.Add("{"); output.Add(line); output.Add("}"); }
            File.Copy(list, list + ".before-zomboid-access", true);
            File.WriteAllLines(list, output.ToArray(), new UTF8Encoding(false));
            Notes.Add("Turned the mod on (your other mods stay on).");
        }

        // Steam starts the bridge, the bridge starts the game: "<bridge>" %command%, keeping the player's own options
        // (like -debug) after it.
        void SetLaunchOption()
        {
            var manual = "In Steam, open Project Zomboid's Properties, and in Launch Options type: " + Steam.BridgeOption();
            var configs = Steam.Configs();
            if (configs.Count == 0) { Notes.Add("Couldn't find Steam's settings. " + manual); return; }
            bool any = false;
            foreach (var c in configs)
            {
                var old = Steam.LaunchOptions(c);
                if (old == null) continue;   // this Steam account never started the game
                any = true;
                var rest = Steam.WithoutBridge(old);
                if (Regex.IsMatch(rest, "%command%"))
                {
                    Notes.Add("Project Zomboid already has launch options that run another program, so they were left alone. " + manual);
                    continue;
                }
                var want = (Steam.BridgeOption() + " " + rest).Trim();
                if (want == old) { Notes.Add("Steam already starts the speech bridge with Project Zomboid."); continue; }
                if (Steam.Running())
                {
                    Notes.Add("Steam is running, so its launch options couldn't be changed. Exit Steam (Steam menu, Exit) and run this again, or: " + manual);
                    return;
                }
                Steam.SetLaunchOptions(c, want);
                Notes.Add("Steam now starts the speech bridge with Project Zomboid (launch options: " + want + ").");
            }
            if (!any) Notes.Add("Steam doesn't list Project Zomboid as started yet. " + manual);
        }

        // This program, next to the bridge, with a Start menu entry: run it again for updates.
        void KeepSetup(string from)
        {
            try
            {
                Directory.CreateDirectory(Places.Home);
                var to = Places.SetupCopy;
                if (!string.Equals(Path.GetFullPath(from), Path.GetFullPath(to), StringComparison.OrdinalIgnoreCase))
                {
                    // A running program can't be overwritten, but it can be renamed out of the way.
                    if (File.Exists(to) && string.Equals(Path.GetFullPath(Application.ExecutablePath), Path.GetFullPath(to), StringComparison.OrdinalIgnoreCase))
                    {
                        var old = to + ".old";
                        if (File.Exists(old)) File.Delete(old);
                        File.Move(to, old);
                    }
                    File.Copy(from, to, true);
                }
                Shortcut(Places.StartMenuLink, to);
            }
            catch (Exception e) { Notes.Add("Couldn't keep a copy of this setup for updates: " + e.Message); }
        }

        static void Shortcut(string link, string target)
        {
            var t = Type.GetTypeFromProgID("WScript.Shell");
            if (t == null) return;
            object shell = Activator.CreateInstance(t);
            try
            {
                object sc = t.InvokeMember("CreateShortcut", System.Reflection.BindingFlags.InvokeMethod, null, shell, new object[] { link });
                var st = sc.GetType();
                st.InvokeMember("TargetPath", System.Reflection.BindingFlags.SetProperty, null, sc, new object[] { target });
                st.InvokeMember("Description", System.Reflection.BindingFlags.SetProperty, null, sc, new object[] { "Install, update or remove Zomboid Access" });
                st.InvokeMember("Save", System.Reflection.BindingFlags.InvokeMethod, null, sc, null);
                Marshal.FinalReleaseComObject(sc);
            }
            finally { Marshal.FinalReleaseComObject(shell); }
        }

        public void Uninstall()
        {
            if (Directory.Exists(Places.ModDir)) { Directory.Delete(Places.ModDir, true); Notes.Add("Removed the mod."); }
            var list = Path.Combine(Places.Mods, "default.txt");
            if (File.Exists(list))
            {
                var keep = new List<string>();
                foreach (var l in File.ReadAllLines(list))
                    if (!Regex.IsMatch(l, @"^\s*mod\s*=\s*\\?" + Places.ModId + @"\s*,")) keep.Add(l);
                File.WriteAllLines(list, keep.ToArray(), new UTF8Encoding(false));
                Notes.Add("Turned the mod off.");
            }
            var configs = Steam.Configs();
            foreach (var c in configs)
            {
                var old = Steam.LaunchOptions(c);
                if (old == null || old.IndexOf("ZomboidAccessBridge.exe", StringComparison.OrdinalIgnoreCase) < 0) continue;
                if (Steam.Running())
                {
                    Notes.Add("Steam is running, so the speech bridge is still in Project Zomboid's launch options. Exit Steam and uninstall again, or remove it yourself: Project Zomboid, Properties, Launch Options.");
                    break;
                }
                Steam.SetLaunchOptions(c, Steam.WithoutBridge(old));
                Notes.Add("Took the speech bridge out of Steam's launch options.");
            }
            StopBridge();
            try { if (File.Exists(Places.StartMenuLink)) File.Delete(Places.StartMenuLink); } catch (Exception) { }
            if (Directory.Exists(Places.Home))
            {
                bool runningFromHome = Path.GetFullPath(Application.ExecutablePath).StartsWith(Path.GetFullPath(Places.Home), StringComparison.OrdinalIgnoreCase);
                foreach (var f in Directory.GetFiles(Places.Home, "*", SearchOption.AllDirectories))
                    try { File.SetAttributes(f, FileAttributes.Normal); File.Delete(f); } catch (Exception) { }
                foreach (var d in Directory.GetDirectories(Places.Home))
                    try { Directory.Delete(d, true); } catch (Exception) { }
                if (runningFromHome)
                {
                    // This program is in there: remove it, and the folder, a moment after it closes.
                    Process.Start(new ProcessStartInfo("cmd.exe", "/c timeout /t 3 /nobreak >nul & rmdir /s /q \"" + Places.Home + "\"")
                        { CreateNoWindow = true, UseShellExecute = false });
                }
                else try { Directory.Delete(Places.Home, true); } catch (Exception) { }
                Notes.Add("Removed the speech bridge and its settings.");
            }
            Notes.Add("Your saves and the game itself are untouched.");
        }

        // The bridge says which screen reader it speaks through.
        public static void TestSpeech()
        {
            if (!File.Exists(Places.Bridge) || Environment.GetEnvironmentVariable("ZA_TEST_NO_BRIDGE") != null) return;
            try
            {
                var p = Process.Start(new ProcessStartInfo(Places.Bridge, "--test") { UseShellExecute = false });
                p.WaitForExit(10000);
            }
            catch (Exception) { }
        }
    }

    // ---------- the window ----------

    class MainForm : Form
    {
        readonly TextBox status, notes;
        readonly Button main, reinstall, uninstall, close;
        Release newest;
        string installed;

        public MainForm()
        {
            Text = "Zomboid Access Setup";
            Font = new Font("Segoe UI", 10f);
            ClientSize = new Size(760, 560);
            StartPosition = FormStartPosition.CenterScreen;
            MinimumSize = new Size(560, 420);

            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 5, Padding = new Padding(12) };
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 110));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Controls.Add(layout);

            // Each box follows its label, so a screen reader names it.
            layout.Controls.Add(new Label { Text = "&Status", AutoSize = true });
            status = new TextBox { Multiline = true, ReadOnly = true, Dock = DockStyle.Fill, ScrollBars = ScrollBars.Vertical, AccessibleName = "Status", TabIndex = 0 };
            layout.Controls.Add(status);
            layout.Controls.Add(new Label { Text = "&Release notes", AutoSize = true });
            notes = new TextBox { Multiline = true, ReadOnly = true, Dock = DockStyle.Fill, ScrollBars = ScrollBars.Vertical, AccessibleName = "Release notes", TabIndex = 1 };
            layout.Controls.Add(notes);

            var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight };
            main = new Button { Text = "&Install", AutoSize = true, Enabled = false, TabIndex = 2 };
            reinstall = new Button { Text = "Re&install", AutoSize = true, Enabled = false, TabIndex = 3 };
            uninstall = new Button { Text = "&Uninstall", AutoSize = true, Enabled = false, TabIndex = 4 };
            close = new Button { Text = "&Close", AutoSize = true, TabIndex = 5 };
            buttons.Controls.AddRange(new Control[] { main, reinstall, uninstall, close });
            layout.Controls.Add(buttons);
            CancelButton = close;

            main.Click += (s, e) => Run(main.Tag as string);
            reinstall.Click += (s, e) => Run("reinstall");
            uninstall.Click += (s, e) => Run("uninstall");
            close.Click += (s, e) => Close();
            Shown += (s, e) => { status.Focus(); Check(); };
        }

        void Say(string text)
        {
            if (InvokeRequired) { BeginInvoke(new Action<string>(Say), text); return; }
            status.Text = text;
        }

        static string Plain(string markdown)
        {
            if (string.IsNullOrEmpty(markdown)) return "(No release notes.)";
            var t = markdown.Replace("\r\n", "\n");
            t = Regex.Replace(t, @"^#+\s*", "", RegexOptions.Multiline);
            t = t.Replace("**", "");
            return t.Replace("\n", "\r\n");
        }

        void Check()
        {
            installed = Places.InstalledVersion();
            Say("Checking GitHub for the newest version of Zomboid Access...");
            new Thread(() =>
            {
                Release rel = null; string problem = null;
                try { rel = Release.Newest(); }
                catch (Exception e) { problem = e.Message; }
                var beside = Release.Beside();
                // No download needed when the copy next to this program is as new.
                if (beside != null && (rel == null || Versions.Compare(beside.Version, rel.Version) >= 0))
                {
                    if (rel != null) beside.Notes = rel.Notes;
                    rel = beside;
                }
                BeginInvoke(new Action(() => Show(rel, problem)));
            }) { IsBackground = true }.Start();
        }

        void Show(Release rel, string problem)
        {
            newest = rel;
            var lines = new List<string>();
            lines.Add(installed == null ? "Zomboid Access is not installed." : "You have Zomboid Access " + installed + ".");
            if (rel == null)
            {
                lines.Add("Couldn't check GitHub for the newest version" + (problem != null ? " (" + problem + ")" : "") + ".");
                main.Enabled = false; reinstall.Enabled = false;
            }
            else
            {
                notes.Text = Plain(rel.Notes);
                int cmp = installed == null ? 1 : Versions.Compare(rel.Version, installed);
                var newestText = "The newest version is " + rel.Version + (rel.Pre ? " (an early version)" : "") + (rel.LocalFolder != null ? ", in this folder" : "") + ".";
                if (installed == null)
                {
                    lines.Add(newestText + " Its release notes are below. Press Install to install it.");
                    main.Text = "&Install"; main.Tag = "install"; main.Enabled = true;
                }
                else if (cmp > 0)
                {
                    lines.Add("An update is available: version " + rel.Version + ". Its release notes are below.");
                    lines.Add("Do you want to update your copy? Press Update to update (only the files that changed are replaced; your settings are kept), or Close to leave it as it is.");
                    main.Text = "&Update"; main.Tag = "update"; main.Enabled = true;
                }
                else
                {
                    lines.Add(cmp == 0 ? "You have the newest version." : newestText + " You have a newer one.");
                    lines.Add("Reinstall copies every file again, if something seems broken.");
                    main.Text = "&Update"; main.Tag = "update"; main.Enabled = false;
                }
                reinstall.Enabled = installed != null;
            }
            uninstall.Enabled = installed != null || Directory.Exists(Places.Home);
            Say(string.Join("\r\n", lines));
            status.Focus();
            status.Select(0, 0);
        }

        void Run(string what)
        {
            var blocked = Installer.Blocked();
            if (what != "uninstall" && blocked != null) { MessageBox.Show(this, blocked, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
            if (what == "uninstall")
            {
                if (Process.GetProcessesByName("ProjectZomboid64").Length > 0) { MessageBox.Show(this, "Project Zomboid is running. Quit the game, then try again.", Text); return; }
                if (MessageBox.Show(this, "Remove Zomboid Access, its speech bridge and its voice settings? Your saves are kept.", Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            }
            foreach (var b in new[] { main, reinstall, uninstall, close }) b.Enabled = false;
            var inst = new Installer(Say);
            new Thread(() =>
            {
                string error = null;
                try
                {
                    if (what == "uninstall") inst.Uninstall();
                    else inst.Install(newest, what == "reinstall");
                }
                catch (Exception e) { error = e.Message; }
                BeginInvoke(new Action(() => Done(what, inst, error)));
            }) { IsBackground = true }.Start();
        }

        void Done(string what, Installer inst, string error)
        {
            close.Enabled = true;
            string title = error != null ? "That didn't work" : what == "uninstall" ? "Zomboid Access is removed" : what == "update" ? "Zomboid Access is updated" : "Zomboid Access is installed";
            var text = title + ".\r\n" + string.Join("\r\n", inst.Notes) + (error != null ? "\r\nWhat went wrong: " + error : "");
            if (error == null && what != "uninstall") text += "\r\nStart Project Zomboid from Steam: it says Starting Project Zomboid, and then the main menu speaks.";
            Say(text);
            if (error == null && what != "uninstall") Installer.TestSpeech();
            MessageBox.Show(this, text, Text, MessageBoxButtons.OK, error != null ? MessageBoxIcon.Error : MessageBoxIcon.Information);
            if (what == "uninstall") { Close(); return; }
            installed = Places.InstalledVersion();
            Show(newest, null);
        }
    }

    static class Program
    {
        [STAThread]
        static void Main()
        {
            // An older copy of this program renamed out of the way while updating itself.
            try { var old = Places.SetupCopy + ".old"; if (File.Exists(old)) File.Delete(old); } catch (Exception) { }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
