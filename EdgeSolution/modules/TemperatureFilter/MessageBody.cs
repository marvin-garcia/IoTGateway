using System;
using Newtonsoft.Json;

namespace TemperatureFilter
{
    public class MachineMeasure
    {
        [JsonProperty("temperature")]
        public double Temperature { get; set; }
        [JsonProperty("pressure")]
        public double Pressure { get; set; }
    }

    public class AmbientMeasure
    {
        [JsonProperty("temperature")]
        public double Temperature { get; set; }
        [JsonProperty("humidity")]
        public double Pressure { get; set; }
    }

    public class MessageBody
    {
        [JsonProperty("machine")]
        public MachineMeasure Machine { get; set; }
        [JsonProperty("ambient")]
        public AmbientMeasure Ambient { get; set; }
        [JsonProperty("timeCreated")]
        public DateTime TimeCreated { get; set; }
    }
}