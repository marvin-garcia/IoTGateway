# Azure Stream Analytics Cloud job

There are multiple patterns to process data coming from Azure IoT Hub. [Azure Functions](https://docs.microsoft.com/en-us/azure/azure-functions/functions-overview) and [Stream Analytics](https://docs.microsoft.com/en-us/azure/stream-analytics/stream-analytics-introduction) are two of the most common tools in this scenario, and even though both are capable of scaling out to handle high volumes of events, there are two main differences: Azure Functions "tend" to be less expensive than Stream Analytics but require certain coding skills in any of its supported languages (C#, Java, Python, NodeJS, PowerShell, etc.), and Stream Analytics uses a [subset of T-SQL](https://docs.microsoft.com/en-us/stream-analytics-query/stream-analytics-query-language-reference) as querying language; which is very appealing to data analysts and non developer audiences.



> [!NOTE]: If you want to understand and learn how to process data from IoT Hub with Azure Functions, take a look at this sample [solution](https://docs.microsoft.com/en-us/samples/azure-samples/functions-js-iot-hub-processing/processing-data-from-iot-hub-with-azure-functions/).



In this deployment, once messages arrive to the IoT Hub, they are processed by a Stream Analytics job. The solution for the ASA cloud job can be found [here](../StreamAnalytics/CloudASA/). It contains some files that are worth mentioning:

- ASA [Query job](../StreamAnalytics/CloudASA/CloudASA.asaql)
- Job [IoT Hub input file](../StreamAnalytics/CloudASA/Inputs/iothub.json)
- Job [telemetry output file](../StreamAnalytics/CloudASA/Outputs/telemetryhub.json)
- Job [notifications output file](../StreamAnalytics/CloudASA/Outputs/notificationshub.json)
- Job [alerts output file](../StreamAnalytics/CloudASA/Outputs/alertshub.json)
- Deployment ARM [template](../StreamAnalytics/CloudASA/Deploy/CloudASA.JobTemplate.json)



> [!NOTE]: This Stream Analytics Solution was created using VS Code Stream Analytics [extension](https://marketplace.visualstudio.com/items?itemName=ms-bigdatatools.vscode-asa) because it facilitates the creation and testing of the solution in your local environment. If you want to know more about how to use VS Code for Stream Analytics, check out this [tutorial](https://docs.microsoft.com/en-us/azure/stream-analytics/quick-create-visual-studio-code).



## Stream Analytics job query

> [!IMPORTANT]: Stream Analytics is capable of handling many different data handling requirements that we won't cover in this tutorial. If you want to learn more, you might want to start with typical [solution patterns](https://docs.microsoft.com/en-us/azure/stream-analytics/stream-analytics-solution-patterns), [query patterns](https://docs.microsoft.com/en-us/azure/stream-analytics/stream-analytics-stream-analytics-query-patterns) and [supported outputs](https://docs.microsoft.com/en-us/azure/stream-analytics/stream-analytics-define-outputs).



For illustration purposes, this query focuses on redirecting events based on their nature to different outputs:

- All events not labeled as *alerts* will be sent to the `telemetry` event hub
- All events labeled as *alerts* will be sent to the `alerts` event hub
- All events where the tag `AlternatingBoolean` is set to `true` will be sent to the `notifications` event hub

