// SessionAudioLauncher.cs
// Lance Session Audio avec elevation et transmet uniquement les modes autorises.
// By Mamat

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("Session Audio")]
[assembly: AssemblyDescription("Preparation reversible d'un poste Windows pour le travail audio")]
[assembly: AssemblyCompany("Mamat")]
[assembly: AssemblyProduct("Session Audio")]
[assembly: AssemblyCopyright("By Mamat")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
        string scriptPath = Path.Combine(baseDirectory, "Audio-Live.ps1");

        if (!File.Exists(scriptPath))
        {
            MessageBox.Show(
                "Le fichier Audio-Live.ps1 est introuvable. Reinstalle Session Audio.",
                "Session Audio",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 2;
        }

        string scriptArguments = "";
        bool showConsole = false;

        if (HasArgument(args, "--restore"))
        {
            scriptArguments = " -Restore";
            showConsole = true;
        }
        else if (HasArgument(args, "--simulate"))
        {
            scriptArguments = " -NoGui -Simulate";
            showConsole = true;
        }
        else if (HasArgument(args, "--open-config"))
        {
            scriptArguments = " -OpenConfig";
        }
        else if (args.Length > 0)
        {
            MessageBox.Show(
                "Option de lancement inconnue.",
                "Session Audio",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return 3;
        }

        string powerShellPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            "System32",
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");

        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = powerShellPath;
        startInfo.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File \"" + scriptPath + "\"" + scriptArguments;
        startInfo.WorkingDirectory = baseDirectory;
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = !showConsole;
        startInfo.WindowStyle = showConsole ? ProcessWindowStyle.Normal : ProcessWindowStyle.Hidden;

        try
        {
            Process.Start(startInfo);
            return 0;
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                "Impossible de lancer Session Audio.\r\n\r\n" + exception.Message,
                "Session Audio",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }

    private static bool HasArgument(string[] args, string expected)
    {
        foreach (string argument in args)
        {
            if (string.Equals(argument, expected, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}
