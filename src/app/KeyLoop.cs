// src/app/KeyLoop.cs -- KeyLoop screens and send loop.
// main.ps1 compiles this once per version and loads the cached DLL afterwards; the same logic
// run as PowerShell code costs about 0.6 s on every launch. Add-Type compiles C# 5, so newer
// syntax (string interpolation, expression-bodied members, out var) is not available here.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace KeyLoop
{
    static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

        [StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode)]
        public struct INPUT_RECORD
        {
            [FieldOffset(0)] public ushort EventType;
            [FieldOffset(4)] public int KeyDown;
            [FieldOffset(10)] public ushort VirtualKeyCode;
            [FieldOffset(14)] public char UnicodeChar;
            [FieldOffset(16)] public uint ControlKeyState;
        }

        [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
        [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint code, uint mapType);
        [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int which);
        [DllImport("kernel32.dll")] public static extern uint GetConsoleProcessList([Out] uint[] list, uint count);
        [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr handle, out uint mode);
        [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr handle, uint mode);
        [DllImport("kernel32.dll")] public static extern bool GetNumberOfConsoleInputEvents(IntPtr handle, out uint count);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        public static extern bool ReadConsoleInputW(IntPtr handle, [Out] INPUT_RECORD[] records, uint length, out uint read);

        // Milliseconds since the last keyboard or mouse input in this session.
        public static long IdleMs()
        {
            LASTINPUTINFO info = new LASTINPUTINFO();
            info.cbSize = (uint)Marshal.SizeOf(info);
            GetLastInputInfo(ref info);
            unchecked { return (uint)Environment.TickCount - info.dwTime; }
        }

        public static void SendKey(int code)
        {
            keybd_event((byte)code, 0, 0, UIntPtr.Zero);
            keybd_event((byte)code, 0, 2, UIntPtr.Zero);   // KEYEVENTF_KEYUP
        }
    }

    // ---- Settings ----
    public static class Keys
    {
        static readonly Dictionary<int, string> Names = new Dictionary<int, string> {
            { 0x07, "Unassigned" }, { 0x08, "Backspace" }, { 0x09, "Tab" }, { 0x0D, "Enter" }, { 0x10, "Shift" },
            { 0x11, "Ctrl" }, { 0x12, "Alt" }, { 0x13, "Pause" }, { 0x14, "Caps Lock" }, { 0x15, "Kana" },
            { 0x19, "Kanji" }, { 0x1B, "Esc" }, { 0x1C, "Convert" }, { 0x1D, "NonConvert" }, { 0x20, "Space" },
            { 0x21, "Page Up" }, { 0x22, "Page Down" }, { 0x23, "End" }, { 0x24, "Home" }, { 0x25, "Left" },
            { 0x26, "Up" }, { 0x27, "Right" }, { 0x28, "Down" }, { 0x2C, "Print Screen" }, { 0x2D, "Insert" },
            { 0x2E, "Delete" }, { 0x5B, "Win" }, { 0x5C, "Win" }, { 0x5D, "Menu" }, { 0x6A, "Num *" },
            { 0x6B, "Num +" }, { 0x6D, "Num -" }, { 0x6E, "Num ." }, { 0x6F, "Num /" }, { 0x90, "Num Lock" },
            { 0x91, "Scroll Lock" }, { 0xA0, "Left Shift" }, { 0xA1, "Right Shift" }, { 0xA2, "Left Ctrl" },
            { 0xA3, "Right Ctrl" }, { 0xA4, "Left Alt" }, { 0xA5, "Right Alt" }, { 0xF0, "Eisu" },
            { 0xF2, "Katakana" }, { 0xF3, "Hankaku/Zenkaku" }, { 0xF4, "Hankaku/Zenkaku" }
        };

        public static string Name(int code)
        {
            string name;
            if (Names.TryGetValue(code, out name)) return name;
            if (code >= 0x60 && code <= 0x69) return "Num " + (code - 0x60);
            if (code >= 0x70 && code <= 0x87) return "F" + (code - 0x6F);
            // The character this key types on the current keyboard layout (letters, digits, symbols).
            uint ch = Native.MapVirtualKeyW((uint)code, 2) & 0x7FFFFFFF;
            return ch > 0x20 ? ((char)ch).ToString().ToUpperInvariant() : "";
        }

        public static string Code(int code) { return "0x" + code.ToString("X2"); }

        public static string Format(int code)
        {
            string name = Name(code);
            return name.Length > 0 ? name + "  " + Code(code) : Code(code);
        }

        public static bool TryParse(string text, out int code)
        {
            code = 0;
            string hex = text.Trim();
            if (hex.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) hex = hex.Substring(2);
            if (hex.Length < 1 || hex.Length > 2) return false;
            foreach (char c in hex) if (!Uri.IsHexDigit(c)) return false;
            code = Convert.ToInt32(hex, 16);
            return code >= 0x01 && code <= 0xFE;
        }

        public static int Parse(string text)
        {
            int code;
            if (TryParse(text, out code)) return code;
            throw new ArgumentException("Key code must be 0x01 to 0xFE: " + text);
        }
    }

    public static class Settings
    {
        public const long IdleDefault = 120, MaxRunDefault = 0;
        public const int KeyDefault = 0x07;

        public static bool TryParseSeconds(string text, long min, out long value)
        {
            value = 0;
            string t = text.Trim();
            if (t.Length < 1 || t.Length > 7) return false;
            foreach (char c in t) if (c < '0' || c > '9') return false;
            value = long.Parse(t);
            return value >= min;
        }

        public static long ParseSeconds(string text, long min, string name)
        {
            long value;
            if (TryParseSeconds(text, min, out value)) return value;
            throw new ArgumentException(name + " must be a whole number of seconds, " + min + " or more: " + text);
        }

        public static string Clock(long seconds)
        {
            return string.Format("{0:00}:{1:00}:{2:00}", seconds / 3600, seconds % 3600 / 60, seconds % 60);
        }
    }

    // A key is due once the PC has had no input for the threshold and the previous send is at
    // least that long ago. Active means real input arrived recently (our own send is excluded).
    public struct Countdown
    {
        public bool Due, Active;
        public long RemainingMs;
        public double Progress;

        public static Countdown Compute(long idleMs, long sinceMs, long thresholdMs)
        {
            Countdown c = new Countdown();
            c.RemainingMs = Math.Max(0, thresholdMs - Math.Min(idleMs, sinceMs));
            c.Progress = 1.0 - (double)c.RemainingMs / thresholdMs;
            c.Due = idleMs >= thresholdMs && sinceMs >= thresholdMs;
            c.Active = idleMs < 2000 && idleMs + 500 < sinceMs;
            return c;
        }
    }

    // ---- Console input ----
    public struct Key
    {
        public int Code;
        public char Char;
        public bool Ctrl;
        public bool IsCtrlC { get { return Ctrl && Code == 0x43; } }
    }

    // Raw console key events: unlike Console.ReadKey these include modifier keys on their own,
    // and with processed input off Ctrl+C arrives as a key instead of killing the process.
    static class Input
    {
        static IntPtr handle;
        static uint savedMode;
        static bool active;

        public static void Start()
        {
            handle = Native.GetStdHandle(-10);   // STD_INPUT_HANDLE
            if (!Native.GetConsoleMode(handle, out savedMode)) return;
            active = Native.SetConsoleMode(handle, savedMode & ~1u);   // ENABLE_PROCESSED_INPUT
        }

        public static void Stop() { if (active) Native.SetConsoleMode(handle, savedMode); }

        // Next key-down event, or false when none is waiting. Key-up and non-key events (such as
        // the release of the Enter that opened a screen) are discarded.
        public static bool TryRead(out Key key)
        {
            key = new Key();
            Native.INPUT_RECORD[] records = new Native.INPUT_RECORD[1];
            uint count, read;
            while (active && Native.GetNumberOfConsoleInputEvents(handle, out count) && count > 0)
            {
                if (!Native.ReadConsoleInputW(handle, records, 1, out read) || read == 0) break;
                Native.INPUT_RECORD r = records[0];
                if (r.EventType != 1 || r.KeyDown == 0) continue;
                key.Code = r.VirtualKeyCode;
                key.Char = r.UnicodeChar;
                key.Ctrl = (r.ControlKeyState & 0x0C) != 0;   // LEFT/RIGHT_CTRL_PRESSED
                return true;
            }
            return false;
        }
    }

    // ---- Drawing ----
    public sealed class Seg
    {
        public readonly string Text;
        public readonly ConsoleColor? Fore, Back;
        public Seg(string text, ConsoleColor? fore = null, ConsoleColor? back = null) { Text = text; Fore = fore; Back = back; }
    }

    public static class Ui
    {
        public const int Width = 46;   // every line is padded to this many cells, so shorter text never leaves residue

        // Cells a string occupies. East Asian wide characters take two; ambiguous-width symbols are
        // avoided in the screens because terminals disagree on them.
        public static int TextWidth(string text)
        {
            int width = 0;
            foreach (char c in text)
            {
                bool wide = (c >= 0x1100 && c <= 0x115F) || (c >= 0x2E80 && c <= 0xA4CF) || (c >= 0xAC00 && c <= 0xD7A3) ||
                    (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFE30 && c <= 0xFE4F) || (c >= 0xFF00 && c <= 0xFF60) ||
                    (c >= 0xFFE0 && c <= 0xFFE6);
                width += wide ? 2 : 1;
            }
            return width;
        }

        public static List<Seg> Line(params Seg[] segs) { return Join(segs, new Seg[0]); }

        // Left segments from the margin, right segments flush to the right margin.
        public static List<Seg> Join(IList<Seg> left, IList<Seg> right)
        {
            int used = 4;
            foreach (Seg s in left) used += TextWidth(s.Text);
            foreach (Seg s in right) used += TextWidth(s.Text);
            List<Seg> line = new List<Seg>();
            line.Add(new Seg("  "));
            line.AddRange(left);
            line.Add(new Seg(new string(' ', Math.Max(1, Width - used))));
            line.AddRange(right);
            return line;
        }

        public static List<Seg> Join(Seg left, Seg right) { return Join(new[] { left }, new[] { right }); }

        public static Seg Badge(string text, ConsoleColor fore, ConsoleColor back)
        {
            int pad = 12 - TextWidth(text);
            return new Seg(new string(' ', pad / 2) + text + new string(' ', pad - pad / 2), fore, back);
        }

        // A row of colored blank cells: renders as a solid bar in every font.
        public static List<Seg> Bar(int width, double progress, ConsoleColor fill, ConsoleColor empty, ConsoleColor? head)
        {
            int filled = (int)Math.Floor(Math.Min(1, Math.Max(0, progress)) * width);
            List<Seg> line = new List<Seg>();
            line.Add(new Seg("  "));
            if (filled > 0) line.Add(new Seg(new string(' ', filled), null, fill));
            if (filled < width && head.HasValue) { line.Add(new Seg(" ", null, head)); filled++; }
            if (filled < width) line.Add(new Seg(new string(' ', width - filled), null, empty));
            return line;
        }

        public static List<Seg> Option(string label, string code, bool selected)
        {
            string body = " " + label;
            body += new string(' ', Math.Max(1, Width - 4 - TextWidth(body) - TextWidth(code) - 1)) + code + " ";
            List<Seg> line = new List<Seg>();
            line.Add(new Seg("  "));
            line.Add(selected ? new Seg(body, ConsoleColor.White, ConsoleColor.DarkCyan) : new Seg(body, ConsoleColor.Gray));
            return line;
        }

        public static bool Blink() { return (Environment.TickCount & int.MaxValue) % 1000 < 500; }
    }

    static class Screen
    {
        static readonly Dictionary<int, string> drawn = new Dictionary<int, string>();
        static string size = "";
        static int rows;

        public static int Rows { get { return rows; } }

        public const int WindowRows = 16;   // the 15 screen rows plus the row the cursor rests on

        public static void Start()
        {
            Console.Title = "KeyLoop";
            Console.CursorVisible = false;
            Clear();
        }

        // Shrinks the window to the screen so nothing sits in an empty corner. Only when this
        // process owns the console (launched from the menu): a cmd window it was started from is
        // left alone. Windows Terminal ignores the request, which is fine.
        public static void FitWindow(int width, int height)
        {
            try
            {
                if (Native.GetConsoleProcessList(new uint[4], 4) != 1) return;
                width = Math.Min(width, Console.LargestWindowWidth);
                height = Math.Min(height, Console.LargestWindowHeight);
                Console.SetWindowPosition(0, 0);
                // The buffer can never be smaller than the window, so shrink the window first.
                Console.SetWindowSize(Math.Min(width, Console.WindowWidth), Math.Min(height, Console.WindowHeight));
                Console.SetBufferSize(width, height);
                Console.SetWindowSize(width, height);
            }
            catch (Exception) { }
        }

        public static void Stop()
        {
            try
            {
                Console.ResetColor();
                Console.CursorVisible = true;
                if (rows > 0) Console.SetCursorPosition(0, rows);
            }
            catch (Exception) { }
        }

        // Clearing is slow in a console with a long scrollback, so it is done only when needed.
        public static void Clear()
        {
            Console.ResetColor();
            Console.Clear();
            drawn.Clear();
            rows = 0;
            size = Console.WindowWidth + "x" + Console.WindowHeight;
        }

        // Draws only the rows that changed since the last call, so redrawing ten times a second does not flicker.
        public static void Draw(IList<List<Seg>> lines)
        {
            if (Console.WindowWidth + "x" + Console.WindowHeight != size) Clear();
            for (int row = 0; row < lines.Count; row++)
            {
                List<Seg> line = lines[row] ?? new List<Seg>();
                string key = "";
                foreach (Seg s in line) key += s.Fore + "|" + s.Back + "|" + s.Text + "\n";
                string old;
                if (drawn.TryGetValue(row, out old) && old == key) continue;
                Console.SetCursorPosition(0, row);
                int used = 0;
                foreach (Seg s in line)
                {
                    Console.ResetColor();
                    if (s.Fore.HasValue) Console.ForegroundColor = s.Fore.Value;
                    if (s.Back.HasValue) Console.BackgroundColor = s.Back.Value;
                    Console.Write(s.Text);
                    used += Ui.TextWidth(s.Text);
                }
                Console.ResetColor();
                if (used < Ui.Width) Console.Write(new string(' ', Ui.Width - used));
                drawn[row] = key;
            }
            for (int row = lines.Count; row < rows; row++)
            {
                Console.SetCursorPosition(0, row);
                Console.Write(new string(' ', Ui.Width));
                drawn.Remove(row);
            }
            rows = lines.Count;
        }

        public static void Wait() { Thread.Sleep(40); }
    }

    // ---- Setup screen ----
    // Asks for every value not given on the command line.
    sealed class Setup
    {
        public long? Idle, MaxRun;
        public int? KeyCode;

        static readonly string[] Labels = { "Idle time", "Run time", "Key to send" };
        const int IdleRow = 0, MaxRunRow = 1, KeyRow = 2;
        const string Pick = "Up/Down + Enter";

        // Returns false when the user quits.
        public bool Run()
        {
            if (!Idle.HasValue && !(Idle = ReadSeconds(IdleRow, 1, "Seconds + Enter   Esc: quit")).HasValue) return false;
            if (!MaxRun.HasValue && !(MaxRun = ReadSeconds(MaxRunRow, 0, "Seconds + Enter (0 = no limit)   Esc: quit")).HasValue) return false;
            if (!KeyCode.HasValue && !(KeyCode = ReadKeyField()).HasValue) return false;
            return true;
        }

        string Value(int row, long value)
        {
            if (row == KeyRow) return Keys.Format((int)value);
            if (row == MaxRunRow && value == 0) return "No limit";
            return value + " s";
        }

        // Field rows: decided values in white, pending ones show their default in gray, and the
        // active one shows what is being edited. The prompt area always has six rows, so the
        // message and hint rows never move.
        void Draw(int active, IList<Seg> editing, IList<List<Seg>> prompt, string message, string hint)
        {
            long?[] values = { Idle, MaxRun, KeyCode };
            long[] defaults = { Settings.IdleDefault, Settings.MaxRunDefault, Settings.KeyDefault };
            List<List<Seg>> lines = new List<List<Seg>>();
            lines.Add(null);
            lines.Add(Ui.Join(new Seg("KeyLoop", ConsoleColor.Cyan), Ui.Badge("Setup", ConsoleColor.White, ConsoleColor.DarkGray)));
            lines.Add(null);
            for (int row = 0; row < 3; row++)
            {
                if (row == active) lines.Add(Ui.Join(new[] { new Seg(Labels[row], ConsoleColor.Cyan) }, editing));
                else if (!values[row].HasValue) lines.Add(Ui.Join(new Seg(Labels[row], ConsoleColor.DarkGray), new Seg(Value(row, defaults[row]), ConsoleColor.DarkGray)));
                else lines.Add(Ui.Join(new Seg(Labels[row], ConsoleColor.Gray), new Seg(Value(row, values[row].Value), ConsoleColor.White)));
            }
            lines.Add(null);
            for (int i = 0; i < 6; i++) lines.Add(prompt != null && i < prompt.Count ? prompt[i] : null);
            lines.Add(Ui.Line(new Seg(message, ConsoleColor.Red)));
            lines.Add(Ui.Line(new Seg(hint, ConsoleColor.DarkGray)));
            Screen.Draw(lines);
        }

        static Seg Cursor() { return new Seg(" ", null, Ui.Blink() ? ConsoleColor.Gray : ConsoleColor.DarkGray); }

        // Digits-only field. Returns null on Esc/Ctrl+C.
        long? ReadSeconds(int row, long min, string hint)
        {
            string buffer = "", message = "";
            string fallback = (row == IdleRow ? Settings.IdleDefault : Settings.MaxRunDefault).ToString();
            while (true)
            {
                Seg shown = buffer.Length > 0 ? new Seg(buffer, ConsoleColor.White) : new Seg(fallback, ConsoleColor.DarkGray);
                Draw(row, new[] { shown, Cursor(), new Seg(" s", ConsoleColor.White) }, null, message, hint);
                Key k;
                if (!Input.TryRead(out k)) { Screen.Wait(); continue; }
                if (k.IsCtrlC || k.Code == 0x1B) return null;
                if (k.Code == 0x0D)
                {
                    long value;
                    if (Settings.TryParseSeconds(buffer.Length > 0 ? buffer : fallback, min, out value)) return value;
                    message = "Enter a number, " + min + " or more";
                    buffer = "";
                }
                else if (k.Code == 0x08) { if (buffer.Length > 0) buffer = buffer.Substring(0, buffer.Length - 1); }
                else if (k.Char >= '0' && k.Char <= '9' && buffer.Length < 7) { buffer += k.Char; message = ""; }
            }
        }

        // Up/Down/Enter list; previews holds the key field's look for each option.
        // Returns the chosen index, or -1 on Esc/Ctrl+C.
        int ReadChoice(string[] labels, string[] codes, IList<Seg>[] previews, int index, string hint)
        {
            while (true)
            {
                List<List<Seg>> prompt = new List<List<Seg>>();
                for (int i = 0; i < labels.Length; i++) prompt.Add(Ui.Option(labels[i], codes[i], i == index));
                Draw(KeyRow, previews[index], prompt, "", hint);
                Key k;
                if (!Input.TryRead(out k)) { Screen.Wait(); continue; }
                if (k.IsCtrlC || k.Code == 0x1B) return -1;
                if (k.Code == 0x26) index = (index + labels.Length - 1) % labels.Length;
                else if (k.Code == 0x28) index = (index + 1) % labels.Length;
                else if (k.Code == 0x0D) return index;
            }
        }

        const int Back = -1, Quit = -2;

        int? ReadKeyField()
        {
            int[] keys = { 0x07, 0x7E, 0x91 };
            string[] labels = { Keys.Name(0x07), Keys.Name(0x7E), Keys.Name(0x91), "Enter a key code", "Press a key" };
            string[] codes = { Keys.Code(0x07), Keys.Code(0x7E), Keys.Code(0x91), "", "" };
            IList<Seg>[] previews = new IList<Seg>[labels.Length];
            for (int i = 0; i < labels.Length; i++)
                previews[i] = new[] { i < keys.Length ? new Seg(Keys.Format(keys[i]), ConsoleColor.Cyan) : new Seg(labels[i], ConsoleColor.DarkGray) };
            int index = 0;
            while (true)
            {
                index = ReadChoice(labels, codes, previews, index, Pick + "   Esc: quit");
                if (index < 0) return null;
                if (index < keys.Length) return keys[index];
                int result = index == 3 ? ReadKeyCode() : ReadKeyCapture();
                if (result == Quit) return null;
                if (result != Back) return result;
            }
        }

        // Hex code entry. Returns the code, Back on Esc, or Quit on Ctrl+C.
        int ReadKeyCode()
        {
            string buffer = "", message = "";
            while (true)
            {
                int code;
                bool valid = Keys.TryParse(buffer, out code);
                Seg[] preview = valid
                    ? new[] { new Seg(Keys.Format(code), ConsoleColor.Cyan) }
                    : new[] { new Seg("0x" + buffer, ConsoleColor.DarkGray) };
                List<List<Seg>> prompt = new List<List<Seg>>();
                prompt.Add(Ui.Join(new[] { new Seg("Key code", ConsoleColor.Gray) }, new[] { new Seg("0x" + buffer, ConsoleColor.White), Cursor() }));
                Draw(KeyRow, preview, prompt, message, "Hex code + Enter   Esc: back");
                Key k;
                if (!Input.TryRead(out k)) { Screen.Wait(); continue; }
                if (k.IsCtrlC) return Quit;
                if (k.Code == 0x1B) return Back;
                if (k.Code == 0x0D)
                {
                    if (valid) return code;
                    message = "Use a code from 0x01 to 0xFE";
                }
                else if (k.Code == 0x08) { if (buffer.Length > 0) buffer = buffer.Substring(0, buffer.Length - 1); }
                else if (Uri.IsHexDigit(k.Char) && buffer.Length < 2) { buffer += char.ToUpperInvariant(k.Char); message = ""; }
            }
        }

        // Waits for a real key press and records its virtual-key code. Every key is recorded,
        // including Esc, Ctrl and Shift, so leaving goes through the confirm list. Returns the
        // code, Back, or Quit on Ctrl+C at the confirm list.
        int ReadKeyCapture()
        {
            Seg[] waiting = { new Seg("Listening", ConsoleColor.DarkGray) };
            while (true)
            {
                int code = 0;
                while (code == 0)
                {
                    // A lit cell sweeps back and forth while listening.
                    int step = (Environment.TickCount & int.MaxValue) / 90 % 22;
                    int pos = step < 12 ? step : 22 - step;
                    List<Seg> sweep = new List<Seg>();
                    sweep.Add(new Seg("  "));
                    sweep.Add(new Seg(new string(' ', pos), null, ConsoleColor.DarkGray));
                    sweep.Add(new Seg(" ", null, ConsoleColor.Cyan));
                    sweep.Add(new Seg(new string(' ', 11 - pos), null, ConsoleColor.DarkGray));
                    List<List<Seg>> prompt = new List<List<Seg>>();
                    prompt.Add(Ui.Line(new Seg("Press the key to send", ConsoleColor.White)));
                    prompt.Add(null);
                    prompt.Add(sweep);
                    Draw(KeyRow, waiting, prompt, "", "");
                    Key k;
                    if (!Input.TryRead(out k)) { Screen.Wait(); continue; }
                    if (k.Code >= 0x01 && k.Code <= 0xFE) code = k.Code;
                }
                IList<Seg> recorded = new[] { new Seg(Keys.Format(code), ConsoleColor.Cyan) };
                int choice = ReadChoice(new[] { "Use this key", "Press again", "Back" }, new[] { "", "", "" },
                    new[] { recorded, recorded, recorded }, 0, Pick);
                if (choice == 0) return code;
                if (choice == 2) return Back;
                if (choice < 0) return Quit;
            }
        }
    }

    // ---- Running screen ----
    sealed class Dashboard
    {
        enum Status { Wait, Active, Sent, Stopped, Done }

        readonly long idle, maxRun;
        readonly int code;
        int sent;
        DateTime? lastSent;

        public Dashboard(long idle, long maxRun, int code) { this.idle = idle; this.maxRun = maxRun; this.code = code; }

        public void Run()
        {
            long threshold = idle * 1000;
            Stopwatch clock = Stopwatch.StartNew();
            long lastSend = -threshold;   // lets the first key go out as soon as the PC is idle long enough
            long flashUntil = -1;
            if (Screen.Rows > 0) Screen.Clear();   // coming from the setup screen
            while (true)
            {
                long now = clock.ElapsedMilliseconds;
                long elapsed = now / 1000;
                // Draining the input also swallows the key we send when this window has focus.
                bool stop = false;
                Key k;
                while (Input.TryRead(out k)) if (k.IsCtrlC) stop = true;
                if (stop) { Draw(Status.Stopped, new Countdown(), elapsed); return; }
                if (maxRun > 0 && now >= maxRun * 1000) { Draw(Status.Done, new Countdown(), maxRun); return; }

                Countdown state = Countdown.Compute(Native.IdleMs(), now - lastSend, threshold);
                if (state.Due)
                {
                    Native.SendKey(code);
                    lastSend = now;
                    flashUntil = now + 1500;
                    sent++;
                    lastSent = DateTime.Now;
                    state = Countdown.Compute(0, 0, threshold);
                }
                Draw(now < flashUntil ? Status.Sent : state.Active ? Status.Active : Status.Wait, state, elapsed);
                Thread.Sleep(100);
            }
        }

        // No backslash: Japanese console fonts draw it as a yen sign.
        static readonly string[] SpinnerFrames = { "o..", ".o.", "..o", ".o." };

        // Moves while the loop runs; a blank of the same width once it has ended.
        static string Spinner(bool running)
        {
            return running ? SpinnerFrames[(Environment.TickCount & int.MaxValue) / 125 % SpinnerFrames.Length] : "   ";
        }

        void Draw(Status status, Countdown state, long elapsed)
        {
            Seg badge;
            List<Seg> bar;
            bool pulse = Ui.Blink();
            switch (status)
            {
                case Status.Wait:
                    badge = Ui.Badge("Waiting", ConsoleColor.White, ConsoleColor.DarkBlue);
                    bar = Ui.Bar(42, state.Progress, ConsoleColor.DarkCyan, ConsoleColor.DarkGray, pulse ? ConsoleColor.Cyan : ConsoleColor.DarkCyan);
                    break;
                case Status.Active:
                    badge = Ui.Badge("Active", ConsoleColor.Black, ConsoleColor.DarkYellow);
                    bar = Ui.Bar(42, state.Progress, ConsoleColor.DarkYellow, ConsoleColor.DarkGray, null);
                    break;
                case Status.Sent:
                    badge = pulse ? Ui.Badge("Key sent", ConsoleColor.Black, ConsoleColor.Green) : Ui.Badge("Key sent", ConsoleColor.White, ConsoleColor.DarkGreen);
                    bar = Ui.Bar(42, 1, ConsoleColor.Green, ConsoleColor.Green, null);
                    break;
                default:
                    badge = Ui.Badge(status == Status.Stopped ? "Stopped" : "Finished", ConsoleColor.White, ConsoleColor.DarkGray);
                    bar = Ui.Bar(42, 0, ConsoleColor.DarkGray, ConsoleColor.DarkGray, null);
                    break;
            }
            bool running = status == Status.Wait || status == Status.Active || status == Status.Sent;
            string next = running ? (long)Math.Ceiling(state.RemainingMs / 1000.0) + " s" : "-";
            string last = lastSent.HasValue ? lastSent.Value.ToString("HH:mm:ss") : "-";
            string left = maxRun > 0 ? Settings.Clock(Math.Max(0, maxRun - elapsed)) : "No limit";
            ConsoleColor countColor = status == Status.Sent ? ConsoleColor.Green : ConsoleColor.White;
            Screen.Draw(new List<List<Seg>> {
                null,
                Ui.Join(new[] { new Seg("KeyLoop", ConsoleColor.Cyan) }, new[] { new Seg(Spinner(running), ConsoleColor.Cyan), new Seg(" "), badge }),
                null,
                Ui.Join(new Seg("Key", ConsoleColor.Gray), new Seg(Keys.Format(code), ConsoleColor.White)),
                Ui.Join(new Seg("Idle time", ConsoleColor.Gray), new Seg(idle + " s", ConsoleColor.White)),
                null,
                Ui.Join(new Seg("Next send in", ConsoleColor.Gray), new Seg(next, ConsoleColor.White)),
                bar,
                null,
                Ui.Join(new Seg("Keys sent", ConsoleColor.Gray), new Seg(sent.ToString(), countColor)),
                Ui.Join(new Seg("Last sent", ConsoleColor.Gray), new Seg(last, ConsoleColor.White)),
                Ui.Join(new Seg("Running for", ConsoleColor.Gray), new Seg(Settings.Clock(elapsed), ConsoleColor.White)),
                Ui.Join(new Seg("Time left", ConsoleColor.Gray), new Seg(left, ConsoleColor.White)),
                null,
                Ui.Line(new Seg(running ? "Ctrl+C: stop" : "", ConsoleColor.DarkGray))
            });
        }
    }

    public static class App
    {
        // Empty strings mean "ask on the setup screen". Throws ArgumentException for bad values.
        public static void Run(string idle, string maxRun, string key)
        {
            // Before the arguments are checked, so an error message also shows in the fitted window.
            Screen.FitWindow(Ui.Width, Screen.WindowRows);
            Setup setup = new Setup();
            if (idle.Length > 0) setup.Idle = Settings.ParseSeconds(idle, 1, "Idle time");
            if (maxRun.Length > 0) setup.MaxRun = Settings.ParseSeconds(maxRun, 0, "Run time");
            if (key.Length > 0) setup.KeyCode = Keys.Parse(key);
            Input.Start();
            try
            {
                Screen.Start();
                if (setup.Run()) new Dashboard(setup.Idle.Value, setup.MaxRun.Value, setup.KeyCode.Value).Run();
            }
            finally
            {
                Screen.Stop();
                Input.Stop();
            }
        }
    }
}
