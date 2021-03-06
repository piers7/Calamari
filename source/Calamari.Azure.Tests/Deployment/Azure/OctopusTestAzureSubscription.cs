﻿using System;
using System.Security.Cryptography.X509Certificates;
using Calamari.Deployment;
using NUnit.Framework;
using Octostache;

namespace Calamari.Azure.Tests.Deployment.Azure
{
    public class OctopusTestAzureSubscription
    {
        public const string AzureSubscriptionId = "8affaa7d-3d74-427c-93c5-2d7f6a16e754";
        public const string CertificateThumbprint = "86B5C8E5553981FED961769B2DA3028C619596AC";

        public static void IgnoreIfCertificateNotInstalled()
        {
            // Ignore the test if the certificate is not installed on the machine
            if (GetCertificate() == null)
                Assert.Ignore(
                    "Cannot run Azure Integration Tests without an Azure Management Certificate that we can use for delegated access to the Azure Subscription. Was looking for a Certificate with the Thumbprint {0} authorized to Subscription {1}. If you work for Octopus Deploy ask one of your team mates for the test Certificate.",
                    CertificateThumbprint, AzureSubscriptionId);
        }

        public static void PopulateVariables(VariableDictionary variables)
        {
            var certificate = GetCertificate();

            variables.Set(SpecialVariables.Account.Name, "OctopusAzureTestAccount");
            variables.Set(SpecialVariables.Account.AccountType, "AzureSubscription");
            variables.Set(SpecialVariables.Action.Azure.CertificateBytes, Convert.ToBase64String(certificate.Export(X509ContentType.Pfx)));
            variables.Set(SpecialVariables.Action.Azure.CertificateThumbprint, CertificateThumbprint);
            variables.Set(SpecialVariables.Action.Azure.SubscriptionId, AzureSubscriptionId);
        }

        private static X509Certificate2 GetCertificate()
        {
            // To avoid putting the certificate details in GitHub, we will assume it is stored in the CertificateStore 
            var store = new X509Store(StoreName.My, StoreLocation.LocalMachine);
            store.Open(OpenFlags.ReadOnly);
            var certificates = store.Certificates.Find(X509FindType.FindByThumbprint, CertificateThumbprint, false);

            return certificates.Count == 0 ? null : certificates[0];
        }
    }
}