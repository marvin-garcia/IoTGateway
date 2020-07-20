using System;
using System.ComponentModel;
using Newtonsoft.Json;

namespace MicrosoftSolutions.IoT.Edge.OpcToDtdl.Contracts
{
    /// <summary>
    ///  Represents an OPC-UA Json Message
    /// </summary>
    internal class OpcMessage {
        public string NodeId  { get; set; }
        public string ApplicationUri { get; set; }
        public string DisplayName { get; set; }
        [DefaultValue("OK")]
        [JsonProperty(DefaultValueHandling = DefaultValueHandling.Populate)]
        public string Status { get; set; }
        public OpcMessageValue Value { get; set; }
    }
}