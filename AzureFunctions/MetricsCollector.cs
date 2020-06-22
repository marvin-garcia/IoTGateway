using System;
using System.Linq;
using System.Text;
using System.Net.Http;
using System.Threading.Tasks;
using System.Collections.Generic;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.EventHubs;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using System.Security.Cryptography;
using System.Net;
using System.IO;

namespace IoTGateway.Functions
{
    public static class MetricsCollector
    {
        [FunctionName("MetricsCollector")]
        public static async Task Run([EventHubTrigger("%EventHubName%", Connection = "EventHubConnection")] EventData[] events, ILogger log)
        {
            var exceptions = new List<Exception>();

            foreach (EventData eventData in events)
            {
                try
                {
                    string messageBody = Encoding.UTF8.GetString(eventData.Body.Array, eventData.Body.Offset, eventData.Body.Count);

                    // Replace these two lines with your processing logic.
                    log.LogInformation($"C# Event Hub trigger function processed a message: {messageBody}");
                    // await Task.Yield();

                    await Post(
                        messageBody,
                        Environment.GetEnvironmentVariable("LogType"),
                        Environment.GetEnvironmentVariable("LogAnalyticsWorkspaceId"),
                        Environment.GetEnvironmentVariable("LogAnalyticsWorkspaceKey"),
                        Environment.GetEnvironmentVariable("LogAnalyticsApiVersion"));
                    
                    log.LogInformation($"Log Analytics Post call completed");
                }
                catch (Exception e)
                {
                    // We need to keep processing the rest of the batch - capture this exception and continue.
                    // Also, consider capturing details of the message that failed processing so it can be processed again later.
                    exceptions.Add(e);
                }
            }

            // Once processing of the batch is complete, if any messages in the batch failed processing throw an exception so that there is a record of the failure.

            if (exceptions.Count > 1)
                throw new AggregateException(exceptions);

            if (exceptions.Count == 1)
                throw exceptions.Single();
        }

        public static async Task Post(string log, string logType, string workspaceId, string sharedKey, string apiVersion = "2016-04-01")
        {
            try
            {
                string requestUriString = $"https://{workspaceId}.ods.opinsights.azure.com/api/logs?api-version={apiVersion}";
                DateTime dateTime = DateTime.UtcNow;
                string dateString = dateTime.ToString("r");
                string signature = GetSignature(workspaceId, sharedKey, "POST", log.Length, "application/json", dateString, "/api/logs");
                
                HttpWebRequest request = (HttpWebRequest)WebRequest.Create(requestUriString);
                request.ContentType = "application/json";
                request.Method = "POST";
                request.Headers["Log-Type"] = logType;
                request.Headers["x-ms-date"] = dateString;
                request.Headers["Authorization"] = signature;
                
                byte[] content = Encoding.UTF8.GetBytes(log);
                using (Stream requestStreamAsync = request.GetRequestStream())
                {
                    requestStreamAsync.Write(content, 0, content.Length);
                }

                HttpWebResponse responseAsync = null;
                using (responseAsync = (HttpWebResponse)await request.GetResponseAsync())
                {
                    if (responseAsync.StatusCode != HttpStatusCode.OK && responseAsync.StatusCode != HttpStatusCode.Accepted)
                    {
                        Stream responseStream = responseAsync.GetResponseStream();
                        if (responseStream != null)
                        {
                            using (StreamReader streamReader = new StreamReader(responseStream))
                            {
                                throw new Exception(streamReader.ReadToEnd());
                            }
                        }
                    }
                }
            }
            catch (Exception e)
            {
                throw e;
            }
        }

        private static string GetSignature(string workspaceId, string sharedKey, string method, int contentLength, string contentType, string date, string resource)
        {
            string message = $"{method}\n{contentLength}\n{contentType}\nx-ms-date:{date}\n{resource}";
            byte[] bytes = Encoding.UTF8.GetBytes(message);
            using (HMACSHA256 encryptor = new HMACSHA256(Convert.FromBase64String(sharedKey)))
            {
                return $"SharedKey {workspaceId}:{Convert.ToBase64String(encryptor.ComputeHash(bytes))}";
            }
        }
    }
}
