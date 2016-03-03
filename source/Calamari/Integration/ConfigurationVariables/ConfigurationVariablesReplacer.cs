﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Xml;
using System.Xml.Linq;
using System.Xml.XPath;
using Calamari.Util;
using Octostache;

namespace Calamari.Integration.ConfigurationVariables
{
    public class ConfigurationVariablesReplacer : IConfigurationVariablesReplacer
    {
        readonly bool ignoreVariableReplacementErrors;

        public ConfigurationVariablesReplacer(bool ignoreVariableReplacementErrors = false)
        {
            this.ignoreVariableReplacementErrors = ignoreVariableReplacementErrors;
        }

        public void ModifyConfigurationFile(string configurationFilePath, VariableDictionary variables)
        {
            try
            {
                var doc = ReadXmlDocument(configurationFilePath);
                var changes = ApplyChanges(doc, variables);

                if (!changes.Any())
                {
                    Log.Info("No matching appSetting, applicationSetting, nor connectionString names were found in: {0}", configurationFilePath);
                    return;
                }

                Log.Info("Updating appSettings, applicationSettings, and connectionStrings in: {0}", configurationFilePath);

                foreach (var change in changes)
                {
                    Log.Verbose(change);
                }

                WriteXmlDocument(doc, configurationFilePath);
            }
            catch (Exception ex)
            {
                if (ignoreVariableReplacementErrors)
                {
                    Log.Warn(ex.Message);
                    Log.Warn(ex.StackTrace);
                }
                else
                {
                    Log.ErrorFormat("Exception while replacing configuration-variables in: {0}", configurationFilePath);
                    throw;
                }
            }
        }

        static XDocument ReadXmlDocument(string configurationFilePath)
        {
            using (var reader = XmlReader.Create(configurationFilePath, XmlUtils.DtdSafeReaderSettings))
            {
                return XDocument.Load(reader, LoadOptions.PreserveWhitespace);
            }
        }

        static List<string> ApplyChanges(XNode doc, VariableDictionary variables)
        {
            var changes = new List<string>();

            foreach (var variable in variables.GetNames())
            {
                changes.AddRange(
                    ReplaceAppSettingOrConnectionString(doc, "//*[local-name()='appSettings']/*[local-name()='add']", "key", variable, "value", variables).Concat(
                    ReplaceAppSettingOrConnectionString(doc, "//*[local-name()='connectionStrings']/*[local-name()='add']", "name", variable, "connectionString", variables).Concat(
                    ReplaceStonglyTypeApplicationSetting(doc, "//*[local-name()='applicationSettings']//*[local-name()='setting']", "name", variable, variables))));
            }
            return changes;
        }

        static void WriteXmlDocument(XDocument doc, string configurationFilePath)
        {
            var xws = new XmlWriterSettings {OmitXmlDeclaration = doc.Declaration == null, Indent = true};
            using (var writer = XmlWriter.Create(configurationFilePath, xws))
            {
                doc.Save(writer);
            }
        }

        static IEnumerable<string> ReplaceAppSettingOrConnectionString(XNode document, string xpath, string keyAttributeName, string keyAttributeValue, string valueAttributeName, VariableDictionary variables)
        {
            var changes = new List<string>();
            var settings = (
                from element in document.XPathSelectElements(xpath)
                let keyAttribute = element.Attribute(keyAttributeName)
                where keyAttribute != null
                where string.Equals(keyAttribute.Value, keyAttributeValue, StringComparison.InvariantCultureIgnoreCase)
                select element).ToList();

            if (settings.Count == 0)
                return changes;

            var value = variables.Get(keyAttributeValue) ?? string.Empty;

            foreach (var setting in settings)
            {
                changes.Add(string.Format("Setting '{0}' = '{1}'", keyAttributeValue, value));

                var valueAttribute = setting.Attribute(valueAttributeName);
                if (valueAttribute == null)
                {
                    setting.Add(new XAttribute(valueAttributeName, value));
                }
                else
                {
                    valueAttribute.SetValue(value);
                }
            }

            return changes;
        }

        static IEnumerable<string> ReplaceStonglyTypeApplicationSetting(XNode document, string xpath, string keyAttributeName, string keyAttributeValue, VariableDictionary variables)
        {
            var changes = new List<string>();

            var settings = (
                from element in document.XPathSelectElements(xpath)
                let keyAttribute = element.Attribute(keyAttributeName)
                where keyAttribute != null
                where string.Equals(keyAttribute.Value, keyAttributeValue, StringComparison.InvariantCultureIgnoreCase)
                select element).ToList();

            if (settings.Count == 0)
                return changes;

            var value = variables.Get(keyAttributeValue) ?? string.Empty;

            foreach (var setting in settings)
            {
                changes.Add(string.Format("Setting '{0}' = '{1}'", keyAttributeValue, value));

                var valueElement = setting.Elements().FirstOrDefault(e => e.Name.LocalName == "value");
                if (valueElement == null)
                {
                    setting.Add(new XElement("value", value));
                }
                else
                {
                    valueElement.SetValue(value);
                }
            }

            return changes;
        }
    }
}
