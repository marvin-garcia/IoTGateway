using System;
using System.IO;
using System.Threading.Tasks;
using System.Collections.Generic;
using Azure;
using Azure.Identity;
using Azure.DigitalTwins.Core;
using Microsoft.Extensions.Configuration;
using Microsoft.Azure.DigitalTwins.Parser;

namespace DigitalTwins
{
    class Program
    {
        async static Task Main(string[] args)
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
                .AddJsonFile("appsettings.dev.json", optional: true, reloadOnChange: true);
            var configuration = builder.Build();

            #region ADT app Sign-in
            string clientId = configuration["AADClientId"];
            string clientSecret = configuration["AADClientSecret"];
            string tenantId = configuration["AADTenantId"];
            string adtInstanceUrl = configuration["ADTInstanceUrl"];
            // var credentials = new InteractiveBrowserCredential(tenantId, clientId);
            var credentials = new ClientSecretCredential(tenantId, clientId, clientSecret);

            DigitalTwinsClient client = new DigitalTwinsClient(new Uri(adtInstanceUrl), credentials);
            Console.WriteLine($"Service client created – ready to go");
            #endregion

            #region Upload ADT model
            Console.WriteLine();
            Console.WriteLine($"Uploading model");
            var typeList = new List<string>();
            string dtdl = File.ReadAllText("Models/Autoclave.json");
            typeList.Add(dtdl);

            // Upload the model to the service
            await client.CreateModelsAsync(typeList);
            #endregion
        }
    }
}
