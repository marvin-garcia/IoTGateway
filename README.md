# Solution accelerator for Industrial IoT on Azure

 

Often times I have seen customers and partners getting stuck at how to use Microsoft's OPC modules and how to use OPC UA data upstream for different purposes. This project is a solution accelerator that provides guidance on how to get started with the OPC Publisher module at the edge and data visualization. This article makes some important assumptions:

·     The initial version of this deployment provides default security settings. This is not recommended for production environments as security is something that should be discussed and planned in advance.

·     The IoT edge runtime is deployed on an Ubuntu 18.04 virtual machine. Similar results can be achieved with Windows or other Linux distributions as well.

 

> [!IMPORTANT]: This solution aims to serve as a starting point to get familiar with some of the core components of the Industrial IoT platform and other Azure services that are usually paired with them in production scenarios. For a complete deployment of the Azure Industrial IoT Platform, please refer to the official repository [here](https://github.com/azure/industrial-IoT/).

 

## Prerequisites

In order to successfully deploy this solution, you will need a couple of things first:

·     **PowerShell**. This deployment script is written in PowerShell. If you are using a Linux environment, follow these [instructions](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7) to install PowerShell on Linux.

·     **Azure CLI**. Follow these [instructions](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) to install or update to the latest version.

·     **Webhook endpoint**. This solution uses Azure Event Grid to send notifications and alerts, so you will need a webhook endpoint to receive such events. There are several services that provide this functionality for free. You can obtain a webhook URL by going to https://webhook.site/ and copying **your unique URL**.

![webhook.site](https://raw.githubusercontent.com/marvin-garcia/IoTGateway/master/Images/WebhookSite.png)

 

> [!NOTE]: If you are interested in understanding how Azure Event Grid works and create your own webhook, take a look at this Azure Event Grid viewer [sample solution](https://github.com/Azure-Samples/azure-event-grid-viewer/tree/master/).

 

# Architecture

![Architecture reference](https://raw.githubusercontent.com/marvin-garcia/IoTGateway/master/Images/Architecture.png)

 

# Getting started

Clone the repository:

```powershell
git clone https://github.com/marvin-garcia/IoTGateway.git
cd IoTGateway
```

Start the deployment:

```powershell
. ./Scripts/deploy.ps1 -webhook_url <webhook url> -deploy_time_series_insights $true
```



> [!IMPORTANT]: If you don’t want to include Time Series Insights in the deployment, set *deploy_time_series_insights* to **$false**

 

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

