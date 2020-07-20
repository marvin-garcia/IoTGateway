using System;
using System.ComponentModel;
using Newtonsoft.Json;

namespace MicrosoftSolutions.IoT.Edge.OpcToDtdl.Contracts
{
    /// <summary>
    ///  Represents an OPC-UA Json Message
    /// </summary>
    internal class OpcMessage {
        [JsonProperty("NodeId")]
        public string NodeId  { get; set; }
        [JsonProperty("ApplicationUri")]
        public string ApplicationUri { get; set; }
        [JsonProperty("DisplayName")]
        public string DisplayName { get; set; }
        [DefaultValue("OK")]
        [JsonProperty("Status", DefaultValueHandling = DefaultValueHandling.Populate)]
        public string Status { get; set; }
        [JsonProperty("Value")]
        public OpcMessageValue Value { get; set; }
    }
}