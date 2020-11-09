# Solution accelerator for Industrial IoT on Azure

 

Often times I have seen customers and partners getting stuck at how to use Microsoft's OPC modules and how to use OPC UA data upstream for different purposes. This project is a solution accelerator that provides guidance on how to get started with the OPC Publisher module at the edge and data visualization. This article makes some important assumptions:

·     The initial version of this deployment provides default security settings. This is not recommended for production environments as security is something that should be discussed and planned in advance.

·     The IoT edge runtime is deployed on an Ubuntu 18.04 virtual machine. Similar results can be achieved with Windows or other Linux distributions as well.

 

> [!IMPORTANT]: This solution aims to serve as a starting point to get familiar with some of the core components of the Industrial IoT platform and other Azure services that are usually paired with them in production scenarios. For a complete deployment of the Azure Industrial IoT Platform, please refer to the official repository [here](https://github.com/azure/industrial-IoT/).

 

## Pre-requisites

In order to successfully deploy this solution, you will need a couple of things first:

·     **PowerShell**. This deployment script is written in PowerShell. If you are using a Linux environment, follow these [instructions](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7) to install PowerShell on Linux.

·     **Azure CLI**. Follow these [instructions](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) to install or update to the latest version.

·     **Webhook endpoint**. This solution uses Azure Event Grid to send notifications and alerts, so you will need a webhook endpoint to receive such events. There are several services that provide this functionality for free. You can obtain a webhook URL by going to https://webhook.site/ and copying **your unique URL**.

![webhook.site](https://raw.githubusercontent.com/marvin-garcia/IoTGateway/master/Images/WebhookSite.png)

 

> [!NOTE]: If you are interested in understanding how Azure Event Grid works and create your own webhook, take a look at this Azure Event Grid viewer [sample solution](https://github.com/Azure-Samples/azure-event-grid-viewer/tree/master/).

 

# Architecture

![Architecture reference](https://raw.githubusercontent.com/marvin-garcia/IoTGateway/master/Images/Architecture.png)

 

# Getting started



### Webhook validation

> [!IMPORTANT:] Please read the section below, as it details steps needed for your deployment to succeed.

Shortly after the deployment starts, your webhook will receive two messages containing a validation URL that needs to be triggered in order for the deployment to succeed. That is because at the time of event subscription creation/update, Event Grid posts a validation event to the target endpoint that includes a  `validationUrl` property with a URL for manually validating the subscription. You need to copy the `validationUrl` property and open it on your browser within 5 minutes of the event subscription creation/update. Failure to complete these steps will cause the deployment to partially fail.

An example subscription validation event is shown below:

```json
[
  {
    "id": "2d1781af-3a4c-4d7c-bd0c-e34b19da4e66",
    "topic": "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "subject": "",
    "data": {
      "validationCode": "512d38b6-c7b8-40c8-89fe-f46f9e9622b6",
      "validationUrl": "https://rp-eastus2.eventgrid.azure.net:553/eventsubscriptions/estest/validate?id=512d38b6-c7b8-40c8-89fe-f46f9e9622b6&t=2018-04-26T20:30:54.4538837Z&apiVersion=2018-05-01-preview&token=1A1A1A1A"
    },
    "eventType": "Microsoft.EventGrid.SubscriptionValidationEvent",
    "eventTime": "2018-01-25T22:12:19.4556811Z",
    "metadataVersion": "1",
    "dataVersion": "1"
  }
]
```



After calling the validation URL from your browser, you should see the success message *"Webhook successfully validated as a subscription endpoint."*.



## Deployment Start

Clone the repository:

```powershell
git clone https://github.com/marvin-garcia/IoTGateway.git
cd IoTGateway
```

Start the deployment:

```powershell
. ./Scripts/deploy.ps1
```

 

## Next Steps

Once the solution has been successfully deployed, you may want to spend some time understanding each component:

1. [OPC Simulator](Docs/OpcSimulator.md)
2. [OPC Publisher](Docs/OpcPublisher.md)
3. [Stream Analytics Edge job](Docs/EdgeASA.md)
4. [OPC Translator](Docs/OpcTranslator.md)
5. [IoT Edge Deployment](Docs/IoTEdgeDeployment.md)
6. [Stream Analytics Cloud job](Docs/CloudASA.md)
7. [Notification & Alerting](Docs/Notification/Alerting.md)
8. [Real-time data visualization with Time Series Insights](Docs/TimeSeriesInsights.md)
9. [Data visualization through Azure Data Explorer](DataExplorer.md)

