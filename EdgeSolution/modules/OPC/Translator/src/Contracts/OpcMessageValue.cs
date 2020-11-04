using System;
using Newtonsoft.Json;

namespace MicrosoftSolutions.IoT.Edge.OpcToDtdl.Contracts
{
    /// <summary>
    ///  Represents an OPC-UA Json Message Value field
    /// </summary>
    internal class OpcMessageValue {
        [JsonProperty("Value")]
        public object Value { get; set; }
        [JsonProperty("SourceTimestamp")]
        public DateTime SourceTimestamp { get; set; }
    }
}