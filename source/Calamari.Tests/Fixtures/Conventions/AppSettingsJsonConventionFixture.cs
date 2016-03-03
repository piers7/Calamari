﻿using System.IO;
using Calamari.Deployment;
using Calamari.Deployment.Conventions;
using Calamari.Integration.AppSettingsJson;
using Calamari.Integration.Processes;
using NSubstitute;
using NUnit.Framework;

namespace Calamari.Tests.Fixtures.Conventions
{
    [TestFixture]
    public class AppSettingsJsonConventionFixture
    {
        RunningDeployment deployment;
        IAppSettingsJsonGenerator generator;
        const string StagingDirectory = "C:\\applications\\Acme\\1.0.0";

        [SetUp]
        public void SetUp()
        {
            var variables = new CalamariVariableDictionary(); 
            variables.Set(SpecialVariables.OriginalPackageDirectoryPath, StagingDirectory);
            deployment = new RunningDeployment("C:\\Packages", variables);
            generator = Substitute.For<IAppSettingsJsonGenerator>();
        }

        [Test]
        public void ShouldNotRunIfVariableNotSet()
        {
            var convention = new AppSettingsJsonConvention(generator);
            convention.Install(deployment);
            generator.DidNotReceiveWithAnyArgs().Generate(null, null);
        }

        [Test]
        public void ShouldFindAndCallDeployScripts()
        {
            deployment.Variables.Set(SpecialVariables.Package.GenerateAppSettingsJson, "true");
            deployment.Variables.Set(SpecialVariables.Package.AppSettingsJsonPath, "appsettings.environment.json");
            var convention = new AppSettingsJsonConvention(generator);
            convention.Install(deployment);
            generator.Received().Generate(Path.Combine(StagingDirectory, "appsettings.environment.json"), deployment.Variables);
        }
    }
}
