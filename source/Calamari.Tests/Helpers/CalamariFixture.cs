using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Calamari.Commands;
using Calamari.Integration.Processes;
using Calamari.Integration.ServiceMessages;
using Octostache;

namespace Calamari.Tests.Helpers
{
    public class ArgumentBuilder
    {
        readonly List<string> arguments = new List<string>();
        string action;

        public ArgumentBuilder Action(string actionName)
        {
            action = actionName;
            return this;
        }

        public ArgumentBuilder Flag(string flag)
        {
            arguments.Add(string.Format("-{0}", flag));
            return this;
        }

        public ArgumentBuilder Argument(string argName, string argValue)
        {
            Flag(argName);
            PositionalArgument(argValue);
            return this;
        }

        public ArgumentBuilder PositionalArgument(string argValue)
        {
            arguments.Add(argValue);
            return this;
        }

        public IEnumerable<string> GetArgs()
        {
            var args = new List<string>();
            if (!string.IsNullOrWhiteSpace(action))
                args.Add(action);

            args.AddRange(arguments);
            return args;
        }
    }

    public abstract class CalamariFixture
    {
        protected CommandLine Calamari()
        {
            var calamariFullPath = typeof (DeployPackageCommand).Assembly.FullLocalPath();
            var calamariConfigFilePath = calamariFullPath + ".config";
            if (!File.Exists(calamariConfigFilePath))
                throw new FileNotFoundException($"Unable to find {calamariConfigFilePath} which means the config file would not have been included in testing {calamariFullPath}");

            return CommandLine.Execute(calamariFullPath);
        }

        protected CommandLine OctoDiff()
        {
            var octoDiffExe = Path.Combine(TestEnvironment.CurrentWorkingDirectory, "Octodiff.exe");
            if (!File.Exists(octoDiffExe))
                throw new FileNotFoundException($"Unable to find {octoDiffExe}");

            return CommandLine.Execute(octoDiffExe);
        }

        protected CalamariResult Invoke(CommandLine command, VariableDictionary variables)
        {
            var capture = new CaptureCommandOutput();
            var runner = new CommandLineRunner(new SplitCommandOutput(new ConsoleCommandOutput(), new ServiceMessageCommandOutput(variables), capture));
            var result = runner.Execute(command.Build());
            return new CalamariResult(result.ExitCode, capture);
        }

        protected CalamariResult Invoke(CommandLine command)
        {
            return Invoke(command, new VariableDictionary());
        }

        protected CalamariResult Invoke2(ArgumentBuilder command)
        {
            var program = new Program("Calamari", typeof(Program).Assembly.GetInformationalVersion());

            var stdOut = Log.Out;
            var stdErr = Log.Out;
            try
            {
                Log.SetOut(new StringWriter());
                Log.SetError(new StringWriter());

                var exitCode = program.Execute(command.GetArgs().ToArray());

                var commandOutput = new CaptureCommandOutput();
                ReadWriter(Log.Out, commandOutput.WriteInfo);
                ReadWriter(Log.Err, commandOutput.WriteError);
                return new CalamariResult(exitCode, commandOutput);
            }
            finally
            {
                Console.SetOut(stdOut);
                Console.SetError(stdErr);
            }
        }

        void ReadWriter(TextWriter writer, Action<string> readLine)
        {
            using (var sr = new StringReader(writer.ToString()))
            {
                string input;
                while ((input = sr.ReadLine()) != null)
                {
                    readLine(input);
                }
            }
        }

        protected string GetFixtureResouce(params string[] paths)
        {
            var path = GetType().Namespace.Replace("Calamari.Tests.", String.Empty);
            path = path.Replace('.', Path.DirectorySeparatorChar);
            return Path.Combine(TestEnvironment.CurrentWorkingDirectory, path, Path.Combine(paths));
        }
    }
}