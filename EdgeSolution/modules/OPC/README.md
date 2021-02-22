# Updating OPC Publisher Module through IoT Hub Direct Methods

Probably the easiest way to configure the OPC Publisher module is through the published nodes JSON file that can get loaded at start time. The downside is that it is too rigid and updating the JSON file would require restarting the module, not easy or convenient. Instead, the OPC Publisher module from version 2.5 and below supports [IoT Hub Direct Methods](https://docs.microsoft.com/en-us/azure/iot-hub/iot-hub-devguide-direct-methods), which is a much more convenient route since they can be triggered from the Azure Portal, using the [Azure CLI IoT Extension](https://github.com/Azure/azure-iot-cli-extension) or the [Azure IoT Device SDK](https://docs.microsoft.com/en-us/azure/iot-hub/iot-hub-devguide-sdks#azure-iot-hub-device-sdks). Dealing with direct methods is relatively easy, but it requires you to know the available endpoints and required payloads in advance, which is why we are going to do some playing in this tutorial with the OPC Publisher direct methods.



## Pre-requisites:

In order to go through this tutorial successfully, you will need a couple of things first:

- An Azure account with an active subscription. [Create one for free](https://azure.microsoft.com/free/?ref=microsoft.com&utm_source=microsoft.com&utm_medium=docs&utm_campaign=visualstudio).
- A standard [IoT hub](https://docs.microsoft.com/en-us/azure/iot-hub/iot-hub-create-through-portal?view=iotedge-2018-06) in your Azure subscription.
- A [registered IoT Edge device](https://docs.microsoft.com/en-us/azure/iot-edge/how-to-register-device?view=iotedge-2018-06&tabs=azure-portal) in your IoT Hub.
- Version 2.5 or below of the OPC Publisher running on your edge device.
- One of the following:
  - [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) and [Azure IoT CLI Extension](https://github.com/Azure/azure-iot-cli-extension), or
  - [Azure Cloud Shell](http://shell.azure.com/)



## Review OPC Publisher available methods

OPC Publisher implements the following IoT Hub direct method calls:

- PublishNodes
- UnpublishNodes
- UnpublishAllNodes
- GetConfiguredEndpoints
- GetConfiguredNodesOnEndpoint
- GetDiagnosticInfo
- GetDiagnosticLog
- GetDiagnosticStartupLog
- ExitApplication
- GetInfo



You can find out more about the module in the official module's [repo](https://github.com/azure/iot-edge-opc-publisher) page.



## Invoke Direct Methods

Let's start using the direct method, for the purpose of this demonstration, I have the OPC Publisher module already running, which has been previously configured  with the following configuration file:

```json
[
  {
    "EndpointUrl": "opc.tcp://10.0.0.4:51200/",
    "UseSecurity": false,
    "OpcNodes": [
      {
        "Id": "ns=2;s=DipData",
        "DisplayName": "DipData"
      },
      {
        "Id": "ns=2;s=SpikeData",
        "DisplayName": "SpikeData"
      },
      {
        "Id": "ns=2;s=AlternatingBoolean",
        "DisplayName": "AlternatingBoolean"
      },
      {
        "Id": "ns=2;s=NegativeTrendData",
        "OpcPublishingInterval": 10000,
        "DisplayName": "NegativeTrendData"
      },
      {
        "Id": "ns=2;s=PositiveTrendData",
        "OpcPublishingInterval": 10000,
        "DisplayName": "PositiveTrendData"
      },
      {
        "Id": "ns=2;s=RandomSignedInt32",
        "OpcPublishingInterval": 10000,
        "DisplayName": "RandomSignedInt32"
      }
    ]
  },
  {
    "EndpointUrl": "opc.tcp://10.0.0.4:51201/",
    "UseSecurity": false,
    "OpcNodes": [
      {
        "Id": "ns=2;s=DipData",
        "OpcPublishingInterval": 5000,
        "DisplayName": "DipData"
      },
      {
        "Id": "ns=2;s=SpikeData",
        "OpcPublishingInterval": 5000,
        "DisplayName": "SpikeData"
      },
      {
        "Id": "ns=2;s=AlternatingBoolean",
        "OpcPublishingInterval": 10000,
        "DisplayName": "AlternatingBoolean"
      },
      {
        "Id": "ns=2;s=NegativeTrendData",
        "OpcPublishingInterval": 10000,
        "DisplayName": "NegativeTrendData"
      },
      {
        "Id": "ns=2;s=PositiveTrendData",
        "OpcPublishingInterval": 10000,
        "DisplayName": "PositiveTrendData"
      },
      {
        "Id": "ns=2;s=RandomSignedInt32",
        "OpcPublishingInterval": 10000,
        "DisplayName": "RandomSignedInt32"
      }
    ]
  },
  {
    "EndpointUrl": "opc.tcp://10.0.0.4:51202/",
    "UseSecurity": false,
    "OpcNodes": [
      {
        "Id": "ns=2;s=DipData",
        "OpcPublishingInterval": 15000,
        "DisplayName": "DipData"
      },
      {
        "Id": "ns=2;s=SpikeData",
        "OpcPublishingInterval": 15000,
        "DisplayName": "SpikeData"
      },
      {
        "Id": "ns=2;s=AlternatingBoolean",
        "OpcPublishingInterval": 30000,
        "DisplayName": "AlternatingBoolean"
      },
      {
        "Id": "ns=2;s=NegativeTrendData",
        "OpcPublishingInterval": 10000,
        "DisplayName": "NegativeTrendData"
      },
      {
        "Id": "ns=2;s=PositiveTrendData",
        "OpcPublishingInterval": 10000,
        "DisplayName": "PositiveTrendData"
      }
    ]
  }
]
```



If you look closely, the published nodes file references three endpoints and each one of them contains a number of nodes.



### Get endpoints

To get the endpoints configured in the module, run the command below:

```bash
az iot hub invoke-module-method \
	-n {iothub-name} \
	-d {device-id} \
	-m {module-name} \
	--method-name GetConfiguredEndpoints
```

The response is the following:

```json
{
  "payload": {
    "Endpoints": [
      {
        "EndpointUrl": "opc.tcp://10.0.0.4:51200/"
      },
      {
        "EndpointUrl": "opc.tcp://10.0.0.4:51201/"
      },
      {
        "EndpointUrl": "opc.tcp://10.0.0.4:51202/"
      }
    ]
  },
  "status": 200
}
```



The method response is in JSON format, containing all configured endpoints.



### Get published nodes

Now let's dive into one of the endpoints and see its published nodes:

```bash
az iot hub invoke-module-method \
	-n {iothub-name} \
	-d {device-id} \
	-m {module-name} \
	--method-name GetConfiguredNodesOnEndpoint \
	--method-payload '{ "EndpointUrl": "opc.tcp://10.0.0.4:51200/" }'
```



The response is the following:

```bash
{
  "payload": {
    "EndpointUrl": "opc.tcp://10.0.0.4:51200/",
    "OpcNodes": [
      {
        "DisplayName": "DipData",
        "Id": "ns=2;s=DipData"
      },
      {
        "DisplayName": "SpikeData",
        "Id": "ns=2;s=SpikeData"
      },
      {
        "DisplayName": "AlternatingBoolean",
        "Id": "ns=2;s=AlternatingBoolean"
      },
      {
        "DisplayName": "NegativeTrendData",
        "Id": "ns=2;s=NegativeTrendData",
        "OpcPublishingInterval": 10000
      },
      {
        "DisplayName": "PositiveTrendData",
        "Id": "ns=2;s=PositiveTrendData",
        "OpcPublishingInterval": 10000
      },
      {
        "DisplayName": "RandomSignedInt32",
        "Id": "ns=2;s=RandomSignedInt32",
        "OpcPublishingInterval": 10000
      }
    ]
  },
  "status": 200
}
```



### Unpublish node

```bash
az iot hub invoke-module-method \
	-n {iothub-name} \
	-d {device-id} \
	-m {module-name} \
	--method-name UnpublishNodes \
	--method-payload '{ "EndpointUrl": "opc.tcp://10.0.0.4:51200/", "OpcNodes": [ { "DisplayName": "DipData", "Id": "ns=2;s=DipData" } ] }'
```

> [!NOTE]: Notice that you must provide an array of nodes to unpublish, since there can be more than one in the same request.



The response to the request is as follows:

```json
{
  "payload": [
    "Id 'ns=2;s=DipData': tagged for removal"
  ],
  "status": 200
}
```



### Publish nodes

Now, let's add the node back:

```bash
az iot hub invoke-module-method \
	-n {iothub-name} \
	-d {device-id} \
	-m {module-name} \
	--method-name PublishNodes \
	--method-payload '{ "EndpointUrl": "opc.tcp://10.0.0.4:51200/", "OpcNodes": [ { "DisplayName": "DipData", "Id": "ns=2;s=DipData" } ] }'
```



The response to this request is:

```bash
{
  "payload": [
    "'ns=2;s=DipData': added"
  ],
  "status": 200
}
```

> [!NOTE:] Notice that you must provide an array of nodes to publish, since there can be more than one in the same request.
>
> [!NOTE]: If you ever try to re-add a node, the response will be successful and the message will say "already monitored".



### Unpublish all nodes

You can unpublish all nodes from a specific endpoint by running the following command:

```bash
az iot hub invoke-module-method \
	-n {iothub-name} \
	-d {device-id} \
	-m {module-name} \
	--method-name UnpublishNodes \
	--method-payload '{ "EndpointUrl": "opc.tcp://10.0.0.4:51200/" }'
```



In a similar way, you can remove all nodes from all endpoints by omitting to pass an `EndpointUrl`:

```bash
az iot hub invoke-module-method \
	-n {iothub-name} \
	-d {device-id} \
	-m {module-name} \
	--method-name UnpublishNodes \
	--method-payload '{}'
```



You can also use the method `UnpublishAllNodes` and that will wipe out the configuration from one or all of your endpoints.



### Diagnostic methods

There are other direct methods that provide useful information about the module's health:



#### Get Info

```bash
az iot hub invoke-module-method \
	-n {iothub-name} \
	-d {device-id} \
	-m {module-name} \
	--method-name GetInfo
```



Response:

```json
{
  "payload": {
    "FrameworkDescription": ".NET Core 4.6.29321.03",
    "InformationalVersion": "2.5.4",
    "OS": "Linux 4.15.0-1106-azure #118~16.04.1-Ubuntu SMP Tue Jan 19 16:13:06 UTC 2021",
    "OSArchitecture": 1,
    "SemanticVersion": "2.5.4",
    "VersionMajor": 2,
    "VersionMinor": 5,
    "VersionPatch": 4
  },
  "status": 200
}
```



#### Get Diagnostic Info

```bash
az iot hub invoke-module-method \
	-n {iothub-name} \
	-d {device-id} \
	-m {module-name} \
	--method-name GetDiagnosticInfo
```



Response:

```json
{
  "payload": {
    "DefaultSendIntervalSeconds": 10,
    "EnqueueCount": 11199,
    "EnqueueFailureCount": 0,
    "FailedMessages": 0,
    "HubMessageSize": 262144,
    "HubProtocol": 3,
    "MissedSendIntervalCount": 264,
    "MonitoredItemsQueueCapacity": 8192,
    "MonitoredItemsQueueCount": 0,
    "NumberOfEvents": 11199,
    "NumberOfOpcMonitoredItemsConfigured": 17,
    "NumberOfOpcMonitoredItemsMonitored": 17,
    "NumberOfOpcMonitoredItemsToRemove": 0,
    "NumberOfOpcSessionsConfigured": 3,
    "NumberOfOpcSessionsConnected": 3,
    "NumberOfOpcSubscriptionsConfigured": 7,
    "NumberOfOpcSubscriptionsConnected": 7,
    "PublisherStartTime": "2021-02-23T15:12:21.0825055Z",
    "SentBytes": 1985748,
    "SentLastTime": "2021-02-23T16:13:27.7953066Z",
    "SentMessages": 345,
    "TooLargeCount": 0,
    "WorkingSetMB": 104
  },
  "status": 200
}
```



#### Get Logs

Similarly, you can get the module's logs by using the methods `GetDiagnosticLog` and `GetDiagnosticsStartupLog`.