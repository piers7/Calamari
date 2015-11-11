using System;
using System.CodeDom.Compiler;
using System.Globalization;
using System.IO;
using System.Text;
using Calamari.Integration.Processes;
using Octostache;

namespace Calamari
{
    public class Log
    {
        static string stdOutMode;
        private static IndentedTextWriter stdOut;
        private static IndentedTextWriter stdErr;
        static readonly object Sync = new object();

        public static void SetOut(TextWriter newOut)
        {
            stdOut = new IndentedTextWriter(newOut, "  ");
        }

        public static void SetError(TextWriter newError)
        {
            stdErr = new IndentedTextWriter(newError, "  ");
        }

        public static TextWriter Out
        {
            get { return stdOut.InnerWriter; }
        }

        public static TextWriter Err
        {
            get { return stdErr.InnerWriter; }
        }

        static Log()
        {
            SetOut(Console.Out);
            SetError(Console.Error);
        }

        static void SetMode(string mode)
        {
            if (stdOutMode == mode) return;
            stdOut.WriteLine("##octopus[stdout-" + mode + "]");
            stdOutMode = mode;
        }

        public static void Verbose(string message)
        {
            lock (Sync)
            {
                SetMode("verbose");
                stdOut.WriteLine(message);
            }
        }

        public static void SetOutputVariable(string name, string value)
        {
            SetOutputVariable(name, value, null);
        }

        public static void SetOutputVariable(string name, string value, VariableDictionary variables)
        {
            Info(String.Format("##octopus[setVariable name=\"{0}\" value=\"{1}\"]",
                ConvertServiceMessageValue(name),
                ConvertServiceMessageValue(value)));

            if (variables != null)
                variables.SetOutputVariable(name, value);
        }

        static string ConvertServiceMessageValue(string value)
        {
            return Convert.ToBase64String(Encoding.Default.GetBytes(value));
        }

        public static void VerboseFormat(string messageFormat, params object[] args)
        {
            Verbose(String.Format(messageFormat, args));
        }

        public static void Info(string message)
        {
            lock (Sync)
            {
                SetMode("default");
                stdOut.WriteLine(message);
            }
        }

        public static void Info(string messageFormat, params object[] args)
        {
            Info(String.Format(messageFormat, args));
        }

        public static void Warn(string message)
        {
            lock (Sync)
            {
                SetMode("warning");
                stdOut.WriteLine(message);
            }
        }

        public static void WarnFormat(string messageFormat, params object[] args)
        {
            Warn(String.Format(messageFormat, args));
        }

        public static void Error(string message)
        {
            lock (Sync)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                stdErr.WriteLine(message);
                Console.ResetColor();
            }
        }

        public static void ErrorFormat(string messageFormat, params object[] args)
        {
            Error(String.Format(messageFormat, args));
        }

        public static class ServiceMessages
        {
            public static string ConvertServiceMessageValue(string value)
            {
                return Convert.ToBase64String(Encoding.Default.GetBytes(value));
            }

            public static void PackageFound(string packageId, string packageVersion, string packageHash,
                string packageFullPath, bool exactMatchExists = false)
            {
                if (exactMatchExists)
                    Verbose("##octopus[calamari-found-package]");

                VerboseFormat("##octopus[foundPackage id=\"{0}\" version=\"{1}\" hash=\"{2}\" remotePath=\"{3}\"]",
                    ConvertServiceMessageValue(packageId),
                    ConvertServiceMessageValue(packageVersion),
                    ConvertServiceMessageValue(packageHash),
                    ConvertServiceMessageValue(packageFullPath));

            }

            public static void DeltaVerification(string remotePath, string hash, long size)
            {
                VerboseFormat("##octopus[deltaVerification remotePath=\"{0}\" hash=\"{1}\" size=\"{2}\"]",
                    ConvertServiceMessageValue(remotePath),
                    ConvertServiceMessageValue(hash),
                    ConvertServiceMessageValue(size.ToString(CultureInfo.InvariantCulture)));
            }
        }
    }
}