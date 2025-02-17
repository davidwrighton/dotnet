// Copyright(c) .NET Foundation.All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System.Xml.Linq;

namespace NuGet.Configuration
{
    public sealed class SourceItem : AddItem
    {
        public string ProtocolVersion
        {
            get
            {
                if (Attributes.TryGetValue(ConfigurationConstants.ProtocolVersionAttribute, out var attribute))
                {
                    return Settings.ApplyEnvironmentTransform(attribute);
                }

                return null;
            }
            set => AddOrUpdateAttribute(ConfigurationConstants.ProtocolVersionAttribute, value);
        }

        public SourceItem(string key, string value, string protocolVersion = "")
            : base(key, value)
        {
            if (!string.IsNullOrEmpty(protocolVersion))
            {
                ProtocolVersion = protocolVersion;
            }
        }

        internal SourceItem(XElement element, SettingsFile origin)
            : base(element, origin)
        {
        }

        public override SettingBase Clone()
        {
            var newSetting = new SourceItem(Key, Value, ProtocolVersion);

            if (Origin != null)
            {
                newSetting.SetOrigin(Origin);
            }

            return newSetting;
        }
    }
}
