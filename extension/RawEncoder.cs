using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;

public static class AseLapsRawEncoder
{
    public static void RunJob(string executable, string[] arguments, string log, string cancel, string status)
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
        string result;
        using (Process process = Process.Start(start))
        {
            Task<string> errors = process.StandardError.ReadToEndAsync();
            bool cancelled = false;
            while (!process.WaitForExit(100))
            {
                if (File.Exists(cancel))
                {
                    cancelled = true;
                    try { process.Kill(); }
                    catch (InvalidOperationException) { /* The process already exited. */ }
                    process.WaitForExit();
                    break;
                }
            }
            File.WriteAllText(log, errors.GetAwaiter().GetResult());
            result = "failed";
            if (cancelled) result = "cancelled";
            else if (process.ExitCode == 0) result = "done";
        }
        File.WriteAllText(status + ".tmp", result);
        File.Move(status + ".tmp", status);
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
