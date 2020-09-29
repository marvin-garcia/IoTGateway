function New-IIoTEnvironment(
    [string]$location = "eastus",
    [string]$resource_group = "IIoTRG",
    [string]$iot_hub_name = "iiot-hub",
    [string]$iot_hub_sku = "S1",
    [string]$edge_vm_size = "Standard_D2s_v3",
    [string]$acr_login_server = "marvacr.azurecr.io",
    [string]$acr_username = "marvacr",
    [string]$acr_password = "29+U=lLvcnADESCbTUSwcn9XL0qiCyrN"
)
{
    $password_length = 12
    $hash_length = 8
    $Bytes = [System.Text.Encoding]::Unicode.GetBytes($resource_group)
    $env_hash = [Convert]::ToBase64String($Bytes).Substring($hash_length).ToLower()

    # create resource group
    az group create --name $resource_group --location $location

    #region create Linux VM (IoT edge device)
    $edge_vm_name = "linux-edge-vm-1"
    $edge_device_id = $edge_vm_name
    $edge_vm_image = "microsoft_iot_edge:iot_edge_vm_ubuntu:ubuntu_1604_edgeruntimeonly:latest"
    $edge_vm_username = "azureuser"
    $edge_vm_password = Get-RandomCharacters -length $password_length 'abcdef12345678-.!?'
    $edge_vm_dns = "$($edge_vm_name)-$($env_hash)"

    az vm image terms accept `
        --urn $edge_vm_image

    az vm create `
        --location $location `
        --resource-group $resource_group `
        --name $edge_vm_name `
        --size $edge_vm_size `
        --image $edge_vm_image `
        --admin-username $edge_vm_username `
        --public-ip-address-dns-name $edge_vm_dns `
        --generate-ssh-keys
    #endregion

    #region iot hub
    $iot_hub_name = "$($iot_hub_name)-$($env_hash)"

    # create iot hub
    az iot hub create `
        --resource-group $resource_group `
        --name $iot_hub_name `
        --sku $iot_hub_sku

    # create edge device in hub
    az iot hub device-identity create `
        --hub-name $iot_hub_name `
        --device-id $edge_device_id `
        --edge-enabled

    # get edge device connection string
    $device_connection_string = az iot hub device-identity show-connection-string `
        --device-id $edge_device_id `
        --hub-name $iot_hub_name `
        --query connectionString -o tsv

    # set the connection string on the edge device
    az vm run-command invoke `
        --resource-group $resource_group `
        --name $edge_vm_name `
        --command-id runshellscript `
        --script "/etc/iotedge/configedge.sh '$device_connection_string'"

    # set edge device twin tag
    $device_tags = '{ "environment": "dev" }'
    az iot hub device-twin update --hub-name $iot_hub_name --device-id $edge_device_id --set tags=$device_tags

    # create built-in events route
    az iot hub route create `
        --resource-group $resource_group `
        --hub-name $iot_hub_name `
        --endpoint-name "events" `
        --name "built-in-events-route" `
        --source devicemessages `
        --condition true
    
    # Create main deployment
    $deployment_condition = "tags.environment='dev'"
    
    (Get-Content -Path EdgeSolution/deployment.template.json -Raw) | ForEach-Object {
        $_ -replace '\$CONTAINER_REGISTRY_NAME', $acr_username `
           -replace '\$CONTAINER_REGISTRY_LOGIN_SERVER', $acr_login_server `
           -replace '\$CONTAINER_REGISTRY_USERNAME', $acr_username `
           -replace '\$CONTAINER_REGISTRY_PASSWORD', $acr_password
    } | Set-Content -Path EdgeSolution/deployment.json

    az iot edge deployment create `
        -d main-deployment `
        --hub-name $iot_hub_name `
        --content EdgeSolution/deployment.json `
        --target-condition=$deployment_condition

    # Create OPC layered deployment
    $opc_deployment_name = "opc"
    $priority = 1
    az iot edge deployment create `
        --layered `
        -d "$opc_deployment_name-$priority" `
        --hub-name $iot_hub_name `
        --content EdgeSolution/modules/OPC/Plc/layered.deployment.json `
        --target-condition=$deployment_condition `
        --priority $priority
    #endregion

    #region Database

    # Create a Cosmos account for SQL API
    $cosmos_account_name = "cosmos-$($env_hash)"
    $database_name = "iiotdb"
    $container_name = "telemetry"
    $container_partition_key = "/NodeId"
    $ttl_days = 15

    az cosmosdb create `
        --resource-group $resource_group `
        --name $cosmos_account_name `
        --default-consistency-level Eventual `
        --locations regionName=$location failoverPriority=0 isZoneRedundant=False

    # Create a SQL API database
    az cosmosdb sql database create `
        --resource-group $resource_group `
        --account-name $cosmos_account_name `
        --name $database_name

    # Create SQL API container
    az cosmosdb sql container create `
        --resource-group $resource_group `
        --account-name $cosmos_account_name `
        --database-name $database_name `
        --name $container_name `
        --partition-key-path $container_partition_key `
        --ttl ($ttl_days * 24 * 3600)
    #endregion

    #region stream analytics
    $asa_name = "asa-$($env_hash)"
    $asa_input_job_name = "asaiotinput"
    $asa_output_job_name = "asacosmosoutput"
    $asa_consumer_group = "streamanalytics"
    $asa_policy_name = "streamanalytics"

    # create iot hub policy
    az iot hub policy create `
        --hub-name $iot_hub_name `
        --name $asa_policy_name `
        --permissions ServiceConnect
    
    $policy_shared_key = (az iot hub show-connection-string `
        --hub-name $iot_hub_name `
        --policy-name $asa_policy_name `
        --query 'connectionString' `
        -o tsv).Split(';')[2].Split('SharedAccessKey=')[1]

    # create iot hub consumer group
    az iot hub consumer-group create `
        --hub-name $iot_hub_name `
        --name $asa_consumer_group

    # create ASA job
    az stream-analytics job create `
        --resource-group $resource_group `
        --name $asa_name `
        --location $location `
        --compatibility-level 1.2 `
        --output-error-policy "Drop" `
        --events-outoforder-policy "Drop" `
        --events-outoforder-max-delay 5 `
        --events-late-arrival-max-delay 16 `
        --data-locale "en-US"

    # create ASA input
    $input_job = @{
        "type" = "Microsoft.Devices/IotHubs"
        "properties" = @{
            "iotHubNamespace" = $iot_hub_name
            "sharedAccessPolicyName" = $asa_policy_name
            "sharedAccessPolicyKey" = $policy_shared_key
            "consumerGroupName" = $asa_consumer_group
            "endpoint" = "messages/events"
        }
    }
    Convertto-Json -InputObject $input_job | Set-Content ./input-datasource.json

    $input_serialization = @{
        "type" = "Json"
        "properties" = @{
            "encoding" = "UTF8"
        }
    }
    Convertto-Json -InputObject $input_serialization | Set-Content ./input-serialization.json

    az stream-analytics input create `
        --resource-group $resource_group `
        --job-name $asa_name `
        --name $asa_input_job_name `
        --type Stream `
        --datasource input-datasource.json `
        --serialization input-serialization.json
    
    # create ASA output
    $cosmos_key = az cosmosdb keys list --resource-group $resource_group --name $cosmos_account_name --query primaryMasterKey -o tsv

    $output_job = @{
        "type" = "Microsoft.Storage/DocumentDB"
        "properties" = @{
            "accountId" = $cosmos_account_name
            "accountKey" = $cosmos_key
            "database" = $database_name
            "collectionNamePattern" = $container_name
            "partitionKey" = $container_partition_key
            "documentId" = "documentId"
        }
    }
    Convertto-Json -InputObject $output_job | Set-Content -Path ./output-datasource.json

    $output_serialization = @{
        "type" = "Json"
        "properties" = @{
            "encoding" = "UTF8"
        }
    }
    Convertto-Json -InputObject $output_serialization | Set-Content ./output-serialization.json

    az stream-analytics output create `
        --resource-group $resource_group `
        --job-name $asa_name `
        --name $asa_output_job_name `
        --datasource ./output-datasource.json `
        --serialization ./output-serialization.json

    # Create ASA query
    $query = "SELECT
    GetMetadataPropertyValue($asa_input_job_name, 'EventId') AS id,
    SourceTimestamp,
    NodeId,
    ApplicationUri,
    IoTHub.ConnectionDeviceId,
    Status,
    DipData,
    AlternatingBoolean,
    NegativeTrendData,
    PositiveTrendData,
    RandomSignedInt32,
    RandomUnsignedInt32,
    SpikeData,
    StepUp
    INTO asacosmosoutput 
    FROM asaiotinput"

    az stream-analytics transformation create `
        --resource-group $resource_group `
        --job-name $asa_name `
        --name Transformation `
        --transformation-query $query
    
    # Start ASA job
    az stream-analytics job start `
        --resource-group $resource_group `
        --name $asa_name
    #endregion

    Write-Host ""
    Write-Host -foregroundColor Yellow "Edge VM Credentials:"
    Write-Host -foregroundColor Yellow "Username: $edge_vm_username"
    Write-Host -foregroundColor Yellow "Password: $edge_vm_password"
    Write-Host -foregroundColor Yellow "DNS: $($edge_vm_dns).$($location).cloudapp.azure.com"
    Write-Host ""
}

function New-IoTStoragePipeline(
    [string]$subscription_id,
    [string]$resource_group = "IoTEdgeDataStreaming",
    [string]$iot_hub_name = "TelemetryIoTHub",
    [string]$storage_account_name = "iottelemetrydatastorage",
    [string]$container_name = "telemetrydata",
    [string]$iot_hub_endpoint_name = "eventhub-endpoint",
    [string]$iot_hub_route_name = "eventhub-route"
)
{
    $connection_string = az storage account show-connection-string `
        --resource-group $resource_group `
        --name $storage_account_name `
        --query 'connectionString' -o tsv

    az iot hub routing-endpoint create `
        --resource-group $resource_group `
        --hub-name $iot_hub_name `
        --endpoint-subscription-id $subscription_id `
        --endpoint-resource-group $resource_group `
        --endpoint-type azurestoragecontainer `
        --endpoint-name $iot_hub_endpoint_name `
        --container $container_name `
        --connection-string $connection_string `
        --encoding json
    
    az iot hub route create `
        --resource-group $resource_group `
        --hub-name $iot_hub_name `
        --endpoint-name $iot_hub_endpoint_name `
        --name $iot_hub_route_name `
        --source devicemessages `
        --condition true
}

function New-IoTEventHubPipeline(
    [string]$subscription_id,
    [string]$resource_group = "IoTEdgeDataStreaming",
    [string]$iot_hub_name = "TelemetryIoTHub",
    [string]$namespace = "iottelemetrydatahub",
    [string]$hub_name = "telemetrydata",
    [string]$policy_name = $policy_name,
    [string]$partition_count = 4, # 2 - 32
    [string]$iot_hub_endpoint_name = "eventhub-endpoint",
    [string]$iot_hub_route_name = "eventhub-route"
)
{
    az eventhubs eventhub create `
        --resource-group $resource_group `
        --namespace-name $namespace `
        --name $hub_name `
        --partition-count $partition_count

    az eventhubs eventhub authorization-rule create `
        --resource-group $resource_group `
        --namespace-name $namespace `
        --eventhub-name $hub_name `
        --name $policy_name `
        --rights Listen Send Manage

    $connection_string = az eventhubs eventhub authorization-rule keys list `
        --resource-group $resource_group `
        --namespace-name $namespace `
        --eventhub-name $hub_name `
        --name $policy_name `
        --query primaryConnectionString -o tsv

    az iot hub routing-endpoint create `
        --resource-group $resource_group `
        --hub-name $iot_hub_name `
        --endpoint-subscription-id $subscription_id `
        --endpoint-resource-group $resource_group `
        --endpoint-type eventhub `
        --endpoint-name $iot_hub_endpoint_name `
        --connection-string $connection_string

    az iot hub route create `
        --resource-group $resource_group `
        --hub-name $iot_hub_name `
        --endpoint-name $iot_hub_endpoint_name `
        --name $iot_hub_route_name `
        --source devicemessages `
        --condition true

    az functionapp config appsettings set `
        --resource-group $resource_group `
        --name $function_app_name `
        --settings "EventHubConnectionString=$connection_string"

    Write-Host "Event hub connection string: $connection_string"
}

function New-IoTServiceBusPipeline(
    [string]$subscription_id,
    [string]$resource_group = "IoTEdgeDataStreaming",
    [string]$iot_hub_name = "TelemetryIoTHub",
    [string]$namespace = "iottelemetrydatasb",
    [string]$queue_name = "telemetrydata",
    [string]$policy_name = $policy_name,
    [bool]$enable_partitioning = $true,
    [string]$iot_hub_endpoint_name = "eventhub-endpoint",
    [string]$iot_hub_route_name = "eventhub-route"
)
{
    az servicebus queue create `
        --resource-group $resource_group `
        --namespace-name $namespace `
        --name $queue_name `
        --enable-partitioning $enable_partitioning

    az servicebus queue authorization-rule create `
        --resource-group $resource_group `
        --namespace-name $namespace `
        --queue-name $queue_name `
        --name $policy_name `
        --rights Listen Send Manage

    $connection_string = az servicebus queue authorization-rule keys list `
        --resource-group $resource_group `
        --namespace-name $namespace `
        --queue-name $queue_name `
        --name $policy_name `
        --query primaryConnectionString -o tsv
    
    az iot hub routing-endpoint create `
        --resource-group $resource_group `
        --hub-name $iot_hub_name `
        --endpoint-subscription-id $subscription_id `
        --endpoint-resource-group $resource_group `
        --endpoint-type servicebusqueue `
        --endpoint-name $iot_hub_endpoint_name `
        --connection-string $connection_string
    
    az iot hub route create `
        --resource-group $resource_group `
        --hub-name $iot_hub_name `
        --endpoint-name $iot_hub_endpoint_name `
        --name $iot_hub_route_name `
        --source devicemessages `
        --condition true

    az functionapp config appsettings set `
        --resource-group $resource_group `
        --name $function_app_name `
        --settings "ServiceBusConnectionString=$connection_string"
        
    Write-Host "Service bus connection string: $connection_string"
}

function Get-RandomCharacters(
    [string]$length,
    [string]$characters = 'abcedf1234567890!$%-_=+?'
)
{ 
    $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length } 
    $private:ofs="" 
    $array = [String]$characters[$random]
    return $array
}