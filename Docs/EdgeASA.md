# Azure Stream Analytics on IoT Edge

Azure Stream Analytics (ASA) on IoT Edge empowers developers to deploy near-real-time analytical intelligence closer to IoT devices so that they can unlock the full value of device-generated data. Azure Stream Analytics is designed for low latency, resiliency, efficient use of bandwidth, and compliance. Enterprises can now deploy control logic close to the industrial operations and complement Big Data analytics done in the cloud.

Azure Stream Analytics on IoT Edge runs within the [Azure IoT Edge](https://azure.microsoft.com/campaigns/iot-edge/) framework. Once the job is created in ASA, it can be [deployed and managed](https://docs.microsoft.com/en-us/azure/iot-edge/tutorial-deploy-stream-analytics) using IoT Hub.



## Stream Analytics Edge solution

The solution for the Stream Analytics Edge job can be found [here](../StreamAnalytics/EdgeASA/). It contains some files that are worth mentioning:

- ASA [Query job](../StreamAnalytics/EdgeASA/EdgeASA.asaql)
- Job [stream input file](../StreamAnalytics/EdgeASA/Inputs/streaminput.json)
- Job [telemetry output file](../StreamAnalytics/EdgeASA/Outputs/telemetryoutput.json)
- Job [alerts output file](../StreamAnalytics/EdgeASA/Outputs/alertsoutput.json)
- Deployment ARM [template](../StreamAnalytics/EdgeASA/Deploy/EdgeASA.JobTemplate.json)



> [!NOTE]: This Stream Analytics Solution was created using VS Code Stream Analytics [extension](https://marketplace.visualstudio.com/items?itemName=ms-bigdatatools.vscode-asa) because it facilitates the creation and testing of the solution in your local environment. If you want to know more about how to use VS Code for Stream Analytics, check out this [tutorial](https://docs.microsoft.com/en-us/azure/stream-analytics/quick-create-visual-studio-code).



### Stream Analytics job query

As mentioned previously, ASA on IoT Edge provides near-real-time analytical intelligence closer to IoT devices, so critical decisions can be made immediately to remediate issues or prevent operations going out of control. Since the purpose of this repository is to provide a solution accelerator for Industrial IoT deployments and also learn about the different components, the ASA edge job [query ](../StreamAnalytics/EdgeASA/EdgeASA.asaql) contains three sections:

- [Telemetry forwarding statement](../StreamAnalytics/EdgeASA/EdgeASA.asaql#L36). All events received by the ASA edge job will be forwarded to the [telemetryoutput](../StreamAnalytics/EdgeASA/Outputs/telemetryoutput.json) output.

- . All `DipData` and `SpikeData` events received by the ASA edge job will be analyzed against a built-in machine learning based anomaly detection model for spikes and dips.

  > [!NOTE]: You can find more information about anomaly detection in Azure Stream Analytics [here](https://docs.microsoft.com/en-us/azure/stream-analytics/stream-analytics-machine-learning-anomaly-detection).

- [Alert forwarding statement](../StreamAnalytics/EdgeASA/EdgeASA.asaql#L17). All results from the `AnomalyDetection` statement will be forwarded to the [alertsoutput](../StreamAnalytics/EdgeASA/Outputs/alertsoutput.json) output.



You can find common query patterns for Azure Stream Analytics [here](https://docs.microsoft.com/en-us/azure/stream-analytics/stream-analytics-stream-analytics-query-patterns).



## Publishing Stream Analytics Edge job

Since the edge job will be running on an IoT Edge device instead of a cloud instance, there isn't an option to start/stop the job. In this case, the job query, input and output information will be packaged and uploaded to an Azure storage account, to be downloaded by the ASA edge module at startup.



>  [!NOTE:] In a production environment, changes to the edge job and its publishing should be managed through CI/CD pipelines. For more information about implementing automated pipelines for Azure Stream Analytics, visit the links below:
>
> -  https://docs.microsoft.com/en-us/azure/stream-analytics/cicd-overview
> - https://docs.microsoft.com/en-us/azure/stream-analytics/stream-analytics-cicd-api



This solution creates the ASA edge job and the storage account via [ARM template](../Templates/azuredeploy.json), and then it is published using [Azure APIs](https://docs.microsoft.com/en-us/azure/stream-analytics/stream-analytics-cicd-api#publish-edge-package). To understand how the publish request is made, you can take a look at the function `Publish-StreamAnalyticsEdgeJob` in the [deployment script](../Scripts/deploy.ps1). The output of this function is a JSON payload like the one presented below:

```json
{
  "name": "__job_name__",
  "version": "1.0.0.0",
  "type": "docker",
  "settings": {
    "image": "mcr.microsoft.com/azure-stream-analytics/azureiotedge:1.0.8",
    "createOptions": null
  },
  "env": {
    "PlanId": {
      "value": "stream-analytics-on-iot-edge"
    }
  },
  "endpoints": {
    "inputs": [
      "streaminput"
    ],
    "outputs": [
      "alertsoutput",
      "telemetryoutput"
    ]
  },
  "twin": {
    "contentType": "assignments",
    "content": {
      "properties_desired": {
        "ASAJobInfo": "https://__storage_acount_name__.blob.core.windows.net/__container_name__/ASAEdgeJobs/__unique_guid__/ASAEdgeJobDefinition.zip?__sas_token__",
        "ASAJobResourceId": "/subscriptions/__subscription_id__/resourceGroups/__resource_group_name__/providers/Microsoft.StreamAnalytics/streamingjobs/__job_name__",
        "ASAJobEtag": "__job_etag__",
        "PublishTimestamp": "__publish_time__"
      }
    }
  }
}

```

This output contains important information for the edge job module to run: 

- Docker image name and tag
- endpoints: inputs and outputs
- Module [desired properties](https://docs.microsoft.com/en-us/azure/iot-edge/module-composition#define-or-update-desired-properties) specifying edge job package SAS URL that will be used in the IoT edge deployment manifest, explained [here](./IoTEdgeDeployment.md).