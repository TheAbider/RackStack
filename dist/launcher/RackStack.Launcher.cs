// RackStack.exe — the native host for the RackStack PowerShell toolkit.
//
// This program does one thing: it starts Windows PowerShell's own console host
// (the same engine and console UI that powershell.exe uses) and runs RackStack
// in it. It contains no PowerShell of its own, performs no work beyond locating
// the script and handing over, and writes nothing to disk.
//
// The script is embedded as a plain-text resource; it is byte-identical to the
// monolithic .ps1 published (and Sigstore-signed) in the same release, so what
// the EXE does can be read there.
//
// Build: csc.exe from the .NET Framework 4.x that ships inside Windows — no
// third-party compiler, wrapper, or packer. See ci.yml "Compile RackStack.exe".

using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Management.Automation.Runspaces;
using Microsoft.PowerShell;

[assembly: AssemblyTitle("RackStack - Windows Server configuration toolkit")]
[assembly: AssemblyDescription("Menu-driven configuration and automation for Windows Server hosts.")]
[assembly: AssemblyProduct("RackStack")]
[assembly: AssemblyCompany("TheAbider")]
[assembly: AssemblyCopyright("Copyright (c) 2026 TheAbider")]
[assembly: AssemblyVersion(RackStack.Launcher.Version)]
[assembly: AssemblyFileVersion(RackStack.Launcher.Version)]
[assembly: AssemblyInformationalVersion(RackStack.Launcher.Version)]

namespace RackStack
{
    internal static class Launcher
    {
        // Stamped by the build from Header.ps1's .VERSION; the placeholder never ships.
        internal const string Version = "0.0.0.0";

        // Name of the embedded resource AND of the optional sibling file used when
        // the resource is absent (development builds).
        private const string ScriptName = "RackStack.ps1";

        private static int Main(string[] args)
        {
            var psArgs = new List<string>
            {
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy", "Bypass"
            };

            string script = ReadEmbeddedScript();
            if (script != null)
            {
                // The host joins everything after -Command with spaces, so the script
                // becomes one anonymous script block and the user's arguments follow it
                // exactly as they would after "& { ... }" at a PowerShell prompt.
                psArgs.Add("-Command");
                psArgs.Add("& {" + Environment.NewLine + script + Environment.NewLine + "}");
                foreach (string a in args) psArgs.Add(QuoteForCommand(a));
            }
            else
            {
                string scriptPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ScriptName);
                if (!File.Exists(scriptPath))
                {
                    Console.Error.WriteLine("RackStack: this executable carries no embedded script and no " + ScriptName + " sits next to it.");
                    Console.Error.WriteLine("Re-download it from https://github.com/TheAbider/RackStack/releases");
                    return 2;
                }
                psArgs.Add("-File");
                psArgs.Add(scriptPath);
                psArgs.AddRange(args);
            }

            try
            {
                return ConsoleShell.Start(RunspaceConfiguration.Create(), string.Empty, string.Empty, psArgs.ToArray());
            }
            catch (FileNotFoundException ex)
            {
                Console.Error.WriteLine("RackStack: Windows PowerShell 5.1 (Windows Management Framework 5.1) is required but was not found.");
                Console.Error.WriteLine(ex.Message);
                return 3;
            }
        }

        private static string ReadEmbeddedScript()
        {
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(ScriptName))
            {
                if (s == null) return null;
                using (var r = new StreamReader(s, true)) { return r.ReadToEnd(); }
            }
        }

        // Parameter names (-Action, -Silent) must stay bare so PowerShell binds them;
        // everything else is single-quoted so spaces and special characters survive.
        private static string QuoteForCommand(string a)
        {
            bool looksLikeParameter = a.Length > 1 && a[0] == '-'
                && a.IndexOfAny(new[] { ' ', '\t', '\'', '"', '`', '$', ';', '&', '|', '(', ')', '{', '}' }) < 0;
            if (looksLikeParameter) return a;
            return "'" + a.Replace("'", "''") + "'";
        }
    }
}
