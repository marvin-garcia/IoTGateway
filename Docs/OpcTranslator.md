# OPC Translator

> [!NOTE]: Special thanks to Joey Lorich for sharing his original version of this module. You can find his repository [here](https://github.com/jlorich/demo-opc-iot-edge-to-central).



Many of the new Azure IoT Services, such as IoT Central, Azure Digital Twins, and the Time Series Insights require data to conform to a well-defined model. This model is described using the open-source [Digital Twins Definition Language](https://github.com/Azure/opendigitaltwins-dtdl/tree/master/DTDL), which is a core part of [IoT Plug & Play](https://docs.microsoft.com/en-us/azure/iot-pnp/overview-iot-plug-and-play).

The data emitted by the OPC Publisher does not immediately conform data that can be described in this model so an additional module is used to make some simple transformations.

The `opcPublisher` emits data in this format:

```json
{
    "NodeId": "OPC_NODE_ID",
    "ApplicationUri": "OPC_APPLICATION_URI",
    "DisplayName": "TAG_DISPLAY_NAME",
    "Status": "TAG_STATUS",
    "Value": {
        "Value": "TAG_VALUE",
        "SourceTimestamp": "TAG_SOURCE_TIMESTAMP"
    }
}
```

The `opcToDtdl` module is a simple [Azure Function](https://docs.microsoft.com/en-us/azure/iot-edge/tutorial-deploy-function) takes this data and emits the following schema:

```json
{
    "NodeId": "OPC_NODE_ID",
    "ApplicationUri": "OPC_APPLICATION_URI",
    "Status": "TAG_STATUS",
    "SourceTimestamp": "TAG_SOURCE_TIMESTAMP",
    "TAG_DISPLAY_NAME": "TAG_VALUE"
}
```

By using a key: value method for tag name and tag it becomes easier to model this data in the DTDL spec, meaning it's compatible with all the modern Azure IoT Services.



The Docker image is available at [Docker Hub](https://hub.docker.com/r/marvingarcia/iotedge-opc-dtdl), but you can customize and build your own [here](../EdgeSolution/modules/OPC/Translator/).



> [!NOTE:] This edge module is not required to have a production environment for Industrial IoT applications. Hopefully, as technology progresses and OPC UA implementations at the edge keep maturing, there will be better seamless compatibility between those data formats and cloud services. This tutorial just wants to demonstrate that this is one of the many data manipulation methods available to you.