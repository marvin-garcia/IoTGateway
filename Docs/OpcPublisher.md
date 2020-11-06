# OPC Publisher

OPC Publisher is a reference implementation that connects to existing OPC UA servers and publishes JSON encoded telemetry data in OPC UA Pub/Sub format, to Azure IoT Hub. It supports any of the transport protocols that the Azure IoT Hub client SDK supports: HTTPS, AMQP, MQTT.



The reference implementation includes:

- An OPC UA *client* for connecting to existing OPC UA servers you have on your network.
- An OPC UA *server* on port 62222 that you can use to manage what's published and offers IoT Hub direct methods to do the same.

You can download the [OPC Publisher reference implementation](https://github.com/Azure/iot-edge-opc-publisher) from GitHub.



## OPC Publisher Configuration

OPC Publisher supports configuration using JSON configuration file for publishing events, OPC UA method calls and IoT Hub direct methods. For simplicity, this solution leverages a fixed JSON [configuration file](https://raw.githubusercontent.com/marvin-garcia/IoTGateway/master/EdgeSolution/modules/OPC/publishednodes.json).



> [!NOTE]: IoT Hub direct methods is the default configuration method used in the [Azure Industrial IoT](https://github.com/Azure/Industrial-IoT/tree/master/deploy) platform to configure the OPC Publisher module. IoT Hub direct methods will be covered on a later edition of this tutorial. In the meantime, if you want to know more about the different configuration alternatives, take a look at the official [documentation](https://docs.microsoft.com/en-us/azure/iot-accelerators/howto-opc-publisher-configure).



## OPC Publisher Telemetry Output

Once the OPC Publisher module is successfully configured, it will connect to the specific OPC UA server(s) and start pulling tag(s) in JSON format. A sample output of the OPC Publisher module can be found below:

```json
[
 {
  "NodeId": "ns=2;s=RandomSignedInt32",
  "ApplicationUri": "urn:OpcPlc:c290937fbbd9",
  "DisplayName": "RandomSignedInt32",
  "Value": {
   "Value": -779986998,
   "SourceTimestamp": "2020-11-02T15:40:50.4949290Z"
  }
 }
]
```

