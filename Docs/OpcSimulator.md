# OPC Simulator

The OPC Simulator consists of an Ubuntu 18.04 virtual machine running three instances of the Microsoft OPC PLC server, which uses the [OPC UA .NET Standard Console Reference stack](https://github.com/OPCFoundation/UA-.NETStandard), with some nodes generating random data and data with anomalies. The source can be found [here](https://github.com/Azure-Samples/iot-edge-opc-plc). The nodeset of this server contains various nodes which can be used to generate random data or anomalies. A container is available as [mcr.microsoft.com/iotedge/opc-plc](https://hub.docker.com/r/microsoft/iot-edge-opc-plc/) in the Microsoft Container Registry.



In this solution, the OPC PLC server instances will be deployed with the default nodes:

- Alternating Boolean

- Random signed 32-bit integer

- Random unsigned 32-bit integer

- Sine wave with a spike anomaly

- Sine wave with a dip anomaly

- Value showing a positive trend

- Value showing a negative trend


 

> [!NOTE]: OPC PLC server supports custom nodes configuration via JSON configuration file. If you want to know more you can go to the OPC PLC server [source code](https://github.com/Azure-Samples/iot-edge-opc-plc). Note that you will need to provide the location of the JSON configuration file when starting the Docker container instances