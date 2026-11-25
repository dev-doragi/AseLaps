using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;

public static class AseLapsRawEncoder
{
    public static void RunJob(string executable, string[] arguments, string log, string cancel, string status, string manifest, string source)
    {
        StringBuilder command = new StringBuilder();
        foreach (string argument in arguments)
        {
            if (command.Length > 0) command.Append(' ');
            command.Append(Quote(argument));
        }
        ProcessStartInfo start = new ProcessStartInfo(executable, command.ToString());
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.RedirectStandardError = true;
        bool native = !String.IsNullOrEmpty(manifest);
        start.RedirectStandardInput = native;
        string result;
        using (Process process = Process.Start(start))
        {
            Task<string> errors = process.StandardError.ReadToEndAsync();
            bool cancelled = false;
            Task writer = native ? Task.Factory.StartNew(() => {
                try { WriteNative(manifest, source, process.StandardInput.BaseStream, cancel); }
                finally { process.StandardInput.Close(); }
            }) : null;
            while (!process.WaitForExit(100))
            {
                if (File.Exists(cancel) || (writer != null && writer.IsFaulted))
                {
                    cancelled = File.Exists(cancel);
                    try { process.Kill(); }
                    catch (InvalidOperationException) { /* The process already exited. */ }
                    process.WaitForExit();
                    break;
                }
            }
            string messages = errors.GetAwaiter().GetResult();
            bool writerOk = true;
            if (writer != null) {
                try { writer.GetAwaiter().GetResult(); }
                catch (Exception e) { writerOk = false; messages += Environment.NewLine + e; }
            }
            File.WriteAllText(log, messages);
            result = "failed";
            if (cancelled) result = "cancelled";
            else if (process.ExitCode == 0 && writerOk) result = "done";
        }
        File.WriteAllText(status + ".tmp", result);
        File.Move(status + ".tmp", status);
    }

    private sealed class Record
    {
        public int Generation, Length, Width, Height, Base;
        public long Offset;
        public bool Reference;
    }

    private static long[] Numbers(string line, int count)
    {
        if (line == null) throw new EndOfStreamException("Incomplete frame index");
        string[] fields = line.Split(' ');
        if (fields.Length != count) throw new InvalidDataException("Invalid frame index");
        long[] values = new long[count];
        for (int i = 0; i < count; i++) values[i] = Int64.Parse(fields[i], System.Globalization.CultureInfo.InvariantCulture);
        return values;
    }

    private static void ReadExact(BinaryReader reader, byte[] target, int offset, int count)
    {
        while (count > 0) {
            int n = reader.Read(target, offset, count);
            if (n == 0) throw new EndOfStreamException("Truncated frame pack");
            offset += n; count -= n;
        }
    }

    // Reuse one native buffer and one output canvas. No RGBA temporary file.
    public static void WriteNative(string manifest, string source, Stream output, string cancel)
    {
        using (StreamReader index = new StreamReader(manifest)) {
            long[] header = Numbers(index.ReadLine(), 4);
            int width = checked((int)header[0]), height = checked((int)header[1]);
            int total = checked((int)header[2]), count = checked((int)header[3]);
            if (width <= 0 || height <= 0 || total <= 0 || count <= 0) throw new InvalidDataException("Invalid frame index dimensions");
            byte[] canvas = new byte[checked(width * height * 4)];
            Record[] records = new Record[checked(total + 1)];
            for (int i = 1; i <= total; i++) {
                long[] v = Numbers(index.ReadLine(), 7);
                records[i] = new Record { Generation=checked((int)v[0]), Offset=v[1], Length=checked((int)v[2]), Width=checked((int)v[3]), Height=checked((int)v[4]), Reference=v[5]!=0, Base=checked((int)v[6]) };
            }
            int cached = 0, generation = -1, nw = 0, nh = 0;
            byte[] native = null, pixel = new byte[4];
            BinaryReader reader = null;
            try {
                for (int i = 0; i < count; i++) {
                    if (File.Exists(cancel)) throw new OperationCanceledException();
                    long[] selection = Numbers(index.ReadLine(), 3);
                    int id = checked((int)selection[0]), dx = checked((int)selection[1]), dy = checked((int)selection[2]);
                    if (id < 1 || id > total) throw new InvalidDataException("Invalid selected frame");
                    Record target = records[id];
                    if (target.Base < 1 || target.Base > id) throw new InvalidDataException("Invalid reference frame");
                    int start = cached >= target.Base && cached <= id ? cached + 1 : target.Base;
                    for (int n = start; n <= id; n++) {
                        if (File.Exists(cancel)) throw new OperationCanceledException();
                        Record r = records[n];
                        if (r.Generation != generation) {
                            if (reader != null) reader.Dispose();
                            string name = r.Generation == 0 ? "frames.pack" : String.Format("frames.{0:D6}.pack", r.Generation);
                            reader = new BinaryReader(new FileStream(Path.Combine(source, name), FileMode.Open, FileAccess.Read, FileShare.ReadWrite));
                            generation = r.Generation;
                        }
                        if (r.Width <= 0 || r.Height <= 0 || r.Offset < 0 || r.Length < 0) throw new InvalidDataException("Invalid native frame dimensions");
                        if (r.Reference) {
                            int length = checked(r.Width * r.Height * 4);
                            if (native == null || native.Length != length) native = new byte[length]; else Array.Clear(native, 0, length);
                            nw = r.Width; nh = r.Height;
                        }
                        if (native == null || nw != r.Width || nh != r.Height) throw new InvalidDataException("Invalid delta reference");
                        reader.BaseStream.Position = r.Offset;
                        long end = checked(r.Offset + r.Length);
                        if (end > reader.BaseStream.Length) throw new EndOfStreamException("Truncated frame pack");
                        while (reader.BaseStream.Position < end) {
                            if (end - reader.BaseStream.Position < 8) throw new InvalidDataException("Truncated span");
                            long pos = reader.ReadUInt32();
                            uint spanLength = reader.ReadUInt32();
                            long stop = checked(reader.BaseStream.Position + spanLength);
                            if (stop > end || pos >= (long)nw * nh) throw new InvalidDataException("Invalid span");
                            int at = checked((int)pos * 4), rowEnd = checked(((int)pos / nw + 1) * nw * 4);
                            while (reader.BaseStream.Position < stop) {
                                if (stop - reader.BaseStream.Position < 2) throw new InvalidDataException("Truncated run");
                                int run = reader.ReadInt16();
                                int bytes = Math.Abs(run) * 4;
                                if (run == 0 || bytes > rowEnd - at || stop - reader.BaseStream.Position < (run < 0 ? 4 : bytes)) throw new InvalidDataException("Invalid run");
                                if (run < 0) {
                                    ReadExact(reader, pixel, 0, 4);
                                    Buffer.BlockCopy(pixel, 0, native, at, 4);
                                    for (int filled = 4; filled < bytes;) {
                                        int copy = Math.Min(filled, bytes-filled);
                                        Buffer.BlockCopy(native, at, native, at+filled, copy);
                                        filled += copy;
                                    }
                                } else ReadExact(reader, native, at, bytes);
                                at += bytes;
                            }
                        }
                    }
                    cached = id;
                    if (dx == 0 && dy == 0 && nw == width && nh == height) output.Write(native, 0, native.Length);
                    else {
                        Array.Clear(canvas, 0, canvas.Length);
                        int x = Math.Max(0, dx), y = Math.Max(0, dy), sx = Math.Max(0, -dx), sy = Math.Max(0, -dy);
                        int w = Math.Min(width-x, nw-sx), h = Math.Min(height-y, nh-sy);
                        if (w > 0 && h > 0) for (int r = 0; r < h; r++)
                            Buffer.BlockCopy(native, ((sy+r)*nw+sx)*4, canvas, ((y+r)*width+x)*4, w*4);
                        output.Write(canvas, 0, canvas.Length);
                    }
                }
            } finally { if (reader != null) reader.Dispose(); }
        }
    }

    private static string Quote(string argument)
    {
        StringBuilder quoted = new StringBuilder("\"");
        int backslashes = 0;
        foreach (char character in argument)
        {
            if (character == '\\')
            {
                backslashes++;
                continue;
            }
            if (character == '"')
            {
                quoted.Append('\\', backslashes * 2 + 1);
            }
            else
            {
                quoted.Append('\\', backslashes);
            }
            quoted.Append(character);
            backslashes = 0;
        }
        quoted.Append('\\', backslashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }

    public static int Run(string executable, string[] arguments, string log)
    {
        StringBuilder command = new StringBuilder();
        foreach (string argument in arguments)
        {
            if (command.Length > 0)
                command.Append(' ');
            command.Append(Quote(argument));
        }
        ProcessStartInfo start = new ProcessStartInfo(executable, command.ToString());
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.RedirectStandardInput = true;
        start.RedirectStandardError = true;
        using (Process process = Process.Start(start))
        {
            Task<string> errors = process.StandardError.ReadToEndAsync();
            Exception inputError = null;
            try
            {
                Stream input = process.StandardInput.BaseStream;
                using (Stream frames = Console.OpenStandardInput())
                {
                    frames.CopyTo(input);
                }
            }
            catch (Exception error)
            {
                inputError = error;
            }
            finally
            {
                try
                {
                    process.StandardInput.Close();
                }
                catch (IOException error)
                {
                    if (inputError == null)
                        inputError = error;
                }
            }
            process.WaitForExit();
            string messages = errors.GetAwaiter().GetResult();
            if (inputError != null)
                messages += Environment.NewLine + inputError;
            File.WriteAllText(log, messages);
            if (process.ExitCode != 0)
                return process.ExitCode;
            if (inputError != null)
                throw new IOException("Could not stream RGBA snapshots. Log: " + log, inputError);
            return 0;
        }
    }
}
