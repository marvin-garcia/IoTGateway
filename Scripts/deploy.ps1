## https://docs.microsoft.com/en-us/azure/stream-analytics/stream-analytics-cicd-api

function New-IIoTEnvironment(
    [string]$location = "eastus",
    [string]$resource_group = "IIoTRG",
    [string]$iot_hub_name = "iiot-hub",
    [string]$iot_hub_sku = "S1",
    [string]$edge_vm_size = "Standard_D2s_v3"
)
{
    $env_hash = Get-EnvironmentHash -resource_group $resource_group
    $iot_hub_name = "$($iot_hub_name)-$($env_hash)"
    $deployment_condition = "tags.environment='dev'"

    # create resource group
    az group create --name $resource_group --location $location

    #region create IoT edge VM
    $edge_vm_name = "linux-edge-vm-1"
    $edge_device_id = $edge_vm_name
    $edge_vm_image = "microsoft_iot_edge:iot_edge_vm_ubuntu:ubuntu_1604_edgeruntimeonly:latest"
    $edge_vm_username = "azureuser"
    $password_length = 12
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
    az iot edge deployment create `
        -d main-deployment `
        --hub-name $iot_hub_name `
        --content EdgeSolution/deployment.json `
        --target-condition=$deployment_condition
    #endregion

    #region Database
    $cosmos_account_name = "cosmos-$($env_hash)"
    $database_name = "iiotdb"
    $container_name = "telemetry"
    $container_partition_key = "/NodeId"
    $ttl_days = 7

    New-CosmosDBSQLAccount `
        -location $location `
        -resource_group $resource_group `
        -account_name $cosmos_account_name `
        -database_name $database_name `
        -container_name $container_name `
        -partition_key $container_partition_key `
        -ttl_days = $ttl_days
    
    $cosmos_key = az cosmosdb keys list `
        --resource-group $resource_group `
        --name $cosmos_account_name `
        --query primaryMasterKey `
        -o tsv
    #endregion

    #region event hubs
    $eh_name = "eh-$($env_hash)"
    $eh_notifications_name = "notifications"
    $eh_notifications_consumer_group = "consumer1"
    $eh_alerts_name = "alerts"
    $eh_alerts_consumer_group = "consumer1"
    $eh_send_policy_name = "send"
    $eh_listen_policy_name = "listen"
    
    # create namespace
    az eventhubs namespace create `
        --location $location `
        --resource-group $resource_group `
        --name $eh_name `
        --sku Standard
    
    #region Create notifications event hub
    
    # create event hub
    az eventhubs eventhub create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --name $eh_notifications_name

    # create consumer group
    az eventhubs eventhub consumer-group create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_notifications_name `
        --name $eh_notifications_consumer_group

    # create shared key to Listen to events
    az eventhubs eventhub authorization-rule create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_notifications_name `
        --name $eh_listen_policy_name `
        --rights Listen

    # Retrieve shared key for Listen
    $eh_notifications_listen_key = az eventhubs eventhub authorization-rule keys list `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_notifications_name `
        --name $eh_listen_policy_name `
        --query primaryKey -o tsv

    # create shared key to send events
    az eventhubs eventhub authorization-rule create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_notifications_name `
        --name $eh_send_policy_name `
        --rights Send

    # retrieve shared key for Send
    $eh_notifications_send_key = az eventhubs eventhub authorization-rule keys list `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_notifications_name `
        --name $eh_send_policy_name `
        --query primaryKey -o tsv
    #endregion

    #region Create alerts event hub
    
    # create event hub
    az eventhubs eventhub create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --name $eh_alerts_name

    # create consumer group
    az eventhubs eventhub consumer-group create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_alerts_name `
        --name $eh_alerts_consumer_group

    # create shared key to Listen to events
    az eventhubs eventhub authorization-rule create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_alerts_name `
        --name $eh_listen_policy_name `
        --rights Listen

    # Retrieve shared key for Listen
    $eh_alerts_listen_key = az eventhubs eventhub authorization-rule keys list `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_alerts_name `
        --name $eh_listen_policy_name `
        --query primaryKey -o tsv

    # create shared key to send events
    az eventhubs eventhub authorization-rule create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_alerts_name `
        --name $eh_send_policy_name `
        --rights Send

    # retrieve shared key for Send
    $eh_alerts_send_key = az eventhubs eventhub authorization-rule keys list `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_alerts_name `
        --name $eh_send_policy_name `
        --query primaryKey -o tsv
    #endregion

    #endregion

    #region stream analytics

    #region cloud job
    $asa_name = "asa-$($env_hash)"
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

    $asa_parameters = @{
        "ASAApiVersion" = @{ "value" = "2017-04-01-preview" }
        "OutputStartMode" = @{ "value" = "JobStartTime" }
        "OutputStartTime" = @{ "value" = "2019-01-01T00:00:00Z" }
        "DataLocale" = @{ "value" = "en-US" }
        "OutputErrorPolicy" = @{ "value" = "Stop" }
        "EventsLateArrivalMaxDelayInSeconds" = @{ "value" = 5 }
        "EventsOutOfOrderMaxDelayInSeconds" = @{ "value" = 0 }
        "EventsOutOfOrderPolicy" = @{ "value" = "Adjust" }
        "StreamingUnits" = @{ "value" = 3 }
        "CompatibilityLevel" = @{ "value" = "1.2" }
        "StreamAnalyticsJobName" = @{ "value" = $asa_name }
        "Location" = @{ "value" = $location }
        "Input_iothub_iotHubNamespace" = @{ "value" = $iot_hub_name }
        "Input_iothub_consumerGroupName" = @{ "value" = $asa_consumer_group }
        "Input_iothub_endpoint" = @{ "value" = "messages/events" }
        "Input_iothub_sharedAccessPolicyName" = @{ "value" = $asa_policy_name }
        "Input_iothub_sharedAccessPolicyKey" = @{ "value" = $policy_shared_key }
        "Output_cosmosdb_accountId" = @{ "value" = $cosmos_account_name }
        "Output_cosmosdb_accountKey" = @{ "value" = $cosmos_key }
        "Output_cosmosdb_database" = @{ "value" = $database_name }
        "Output_cosmosdb_collectionNamePattern" = @{ "value" = $container_name }
        "Output_cosmosdb_documentId" = @{ "value" = "id" }
        "Output_NotificationsEventHub_serviceBusNamespace" = @{ "value" = $eh_name }
        "Output_NotificationsEventHub_eventHubName" = @{ "value" = $eh_notifications_name }
        "Output_NotificationsEventHub_partitionKey" = @{ "value" = "" }
        "Output_NotificationsEventHub_sharedAccessPolicyName" = @{ "value" = $eh_send_policy_name }
        "Output_NotificationsEventHub_sharedAccessPolicyKey" = @{ "value" = $eh_notifications_send_key }
    }
    Set-Content -Value (ConvertTo-Json $asa_parameters) -Path StreamAnalytics/CloudASA/Deploy/params.json

    $asa_deployment_name = "CloudASAJob"
    az deployment group create `
        --resource-group $resource_group `
        --name $asa_deployment_name `
        --mode Incremental `
        --template-file StreamAnalytics/CloudASA/Deploy/CloudASA.JobTemplate.json `
        --parameters StreamAnalytics/CloudASA/Deploy/params.json
    #endregion

    #region stream analytics edge
    $asa_edge_name = "asa-edge-$($env_hash)"
    $asa_edge_storage_name = "asaedgestorage$($env_hash)"
    $asa_edge_container_name = "edgeanomaly"

    # create storage account to publish job
    az storage account create `
        --location $location `
        --resource-group $resource_group `
        --name $asa_edge_storage_name `
        --access-tier Cool `
        --kind StorageV2 `
        --sku Standard_LRS

    # retrieve storage key
    $asa_edge_storage_key = az storage account keys list `
        --resource-group $resource_group `
        --account-name $asa_edge_storage_name `
        --query '[0].value' `
        -o tsv

    [Array]$input_files = ((Get-Content ./StreamAnalytics/EdgeASA/asaproj.json `
        | ConvertFrom-Json).configurations | `
        ? { $_.subType -eq "Input" -and $_.filePath -notlike "*iothub.json" }).filePath
    [Array]$asa_edge_input_names = @()
    foreach ($file in $input_files)
    {
        $asa_edge_input_names += $file.Split('/')[1].Split('.')[0]
    }

    [Array]$output_files = ((Get-Content ./StreamAnalytics/EdgeASA/asaproj.json `
        | ConvertFrom-Json).configurations | `
        ? { $_.subType -eq "Output" }).filePath
    [Array]$asa_edge_output_names = @()
    foreach ($file in $output_files)
    {
        $asa_edge_output_names += $file.Split('/')[1].Split('.')[0]
    }
    
    # read edge job query
    $asa_edge_query = Get-Content -Path StreamAnalytics/EdgeASA/EdgeASA.asaql -Raw

    # create edge job
    $edge_create = New-StreamAnalyticsEdgeJob `
        -location $location `
        -resource_group $resource_group `
        -job_name $asa_edge_name `
        -storage_name $asa_edge_storage_name `
        -storage_key $asa_edge_storage_key `
        -storage_container $asa_edge_container_name `
        -input_name $asa_edge_input_names `
        -output_name $asa_edge_output_names `
        -query $asa_edge_query
    
    # publish edge job
    $edge_package = Publish-StreamAnalyticsEdgeJob `
        -resource_group $resource_group `
        -job_name $asa_edge_name
    #endregion

    #endregion

    #region Edge deployment
    (Get-Content -Path EdgeSolution/modules/OPC/layered.deployment.template.json -Raw) | ForEach-Object {
        $_ -replace '__ASA_ENV__', (ConvertTo-Json -InputObject $edge_package.env -Depth 10) `
           -replace '__ASA_INPUT_NAME__', $edge_package.endpoints.inputs[0] `
           -replace '__ASA_DESIRED_PROPERTIES__', (ConvertTo-Json -InputObject $edge_package.twin.content.properties_desired -Depth 10)
    } | Set-Content -Path EdgeSolution/modules/OPC/layered.deployment.json

    # Create OPC layered deployment
    $opc_deployment_name = "opcsim"
    $priority = 1
    az iot edge deployment create `
        --layered `
        -d "$opc_deployment_name-$priority" `
        --hub-name $iot_hub_name `
        --content EdgeSolution/modules/OPC/layered.deployment.json `
        --target-condition=$deployment_condition `
        --priority $priority
    #endregion

    #region time series insight
    # $tsi_name = "tsi-$($env_hash)"

    # az timeseriesinsights environment standard create `
    #     --resource-group $resource_group `
    #     --
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
    [string]$resource_group,
    [string]$iot_hub_name,
    [string]$iot_hub_endpoint_name,
    [string]$iot_hub_route_name,
    [string]$storage_account_name,
    [string]$container_name
)
{
    $connection_string = az storage account show-connection-string `
        --resource-group $resource_group `
        --name $storage_account_name `
        --query 'connectionString' -o tsv

    if (!$subscription_id)
    {
        $subscription_id = az account show --query id -o tsv
    }

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
    [string]$resource_group,
    [string]$iot_hub_name,
    [string]$namespace,
    [string]$hub_name,
    [string]$policy_name,
    [string]$partition_count = 4, # 2 - 32
    [string]$iot_hub_endpoint_name,
    [string]$iot_hub_route_name
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
    [string]$resource_group,
    [string]$iot_hub_name,
    [string]$namespace,
    [string]$queue_name,
    [string]$policy_name,
    [bool]$enable_partitioning,
    [string]$iot_hub_endpoint_name,
    [string]$iot_hub_route_name
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

function Get-EnvironmentHash(
    [string]$resource_group
)
{
    $hash_length = 8
    $Bytes = [System.Text.Encoding]::Unicode.GetBytes($resource_group)
    $env_hash = [Convert]::ToBase64String($Bytes).Substring($hash_length).ToLower()

    return $env_hash
}

function New-StreamAnalyticsEdgeJob(
    [string]$location,
    [string]$subscription_id,
    [string]$resource_group,
    [string]$job_name,
    [string]$storage_name,
    [string]$storage_key,
    [string]$storage_container,
    [Array]$input_names,
    [Array]$output_names,
    [string]$query
)
{
    #region request
    $request = @{
        "location" = $location
        "tags" = @{
            "key" = "value"
            "ms-suppressjobstatusmetrics" = "true"
        }
        "sku" = @{
            "name" = "Standard"
        }
        "properties" = @{
            "sku" = @{
                "name" = "standard"
            }
            "eventsLateArrivalMaxDelayInSeconds" = 1
            "jobType" = "edge"
            "transformation" = @{
                "name" = "edgequery"
                "properties" = @{
                    "query" = $query
                }
            }
            "package" = @{
                "storageAccount" = @{
                    "accountName" = $storage_name
                    "accountKey" = $storage_key
                }
                "container" = $storage_container
            }
            "inputs" = @()
            "outputs" = @()
        }
    }

    foreach ($input_name in $input_names)
    {
        $request.properties.inputs += @{
            "name" = $input_name
            "properties" = @{
                "type" = "stream"
                "serialization" = @{
                    "type" = "JSON"
                    "properties" = @{
                        "encoding" = "UTF8"
                    }
                }
                "datasource" = @{
                    "type" = "GatewayMessageBus"
                    "properties" = @{}
                }
            }
        }
    }

    foreach ($output_name in $output_names)
    {
        $request.properties.outputs += @{
            "name" = $output_name
            "properties" = @{
                "serialization" = @{
                    "type" = "JSON"
                    "properties" = @{
                        "encoding" = "UTF8"
                    }
                }
                "datasource" = @{
                    "type" = "GatewayMessageBus"
                    "properties" = @{}
                }
            }
        }
    }
    #endregion

    if (!$subscription_id)
    {
        $subscription_id = az account show --query id -o tsv
    }
    $token = az account get-access-token --resource-type arm --query accessToken -o tsv
    $secure_token = ConvertTo-SecureString $token -AsPlainText -Force
    $content = ConvertTo-Json -InputObject $request -Depth 8
    Write-Host $content
    $create_uri = "https://management.azure.com/subscriptions/$($subscription_id)/resourcegroups/$($resource_group)/providers/Microsoft.StreamAnalytics/streamingjobs/$($job_name)?api-version=2017-04-01-preview"
    $create_response = Invoke-RestMethod $create_uri `
        -Method PUT `
        -Body $content `
        -ContentType "application/json" `
        -Authentication Bearer -Token $secure_token

    return $create_response
}

function Publish-StreamAnalyticsEdgeJob(
    [string]$subscription_id,
    [string]$resource_group,
    [string]$job_name
)
{
    if (!$subscription_id)
    {
        $subscription_id = az account show --query id -o tsv
    }
    $token = az account get-access-token --resource-type arm --query accessToken -o tsv
    $secure_token = ConvertTo-SecureString $token -AsPlainText -Force
    $publish_uri = "https://management.azure.com/subscriptions/$($subscription_id)/resourceGroups/$($resource_group)/providers/Microsoft.StreamAnalytics/streamingjobs/$($job_name)/publishedgepackage?api-version=2017-04-01-preview"
    $publish_response = Invoke-WebRequest $publish_uri `
        -Method POST `
        -Authentication Bearer -Token $secure_token

    do
    {
        $package_response = Invoke-RestMethod $publish_response.Headers.Location[0] `
            -Authentication Bearer -Token $secure_token
        
        Start-Sleep -Seconds 30
    } until (!!$package_response)
        
    $package = ConvertFrom-Json `
        -InputObject (($package_response.manifest | Out-String) -replace 'properties.desired', 'properties_desired') `
        -Depth 15

    return $package
}

function New-CosmosDBSQLAccount(
    [string]$location,
    [string]$resource_group,
    [string]$account_name,
    [string]$database_name,
    [string]$container_name,
    [string]$partition_key,
    [int]$throughput = 400,
    [int]$ttl_days = 7
)
{
    # Create account
    az cosmosdb create `
        --resource-group $resource_group `
        --name $account_name `
        --default-consistency-level Eventual `
        --locations regionName=$location failoverPriority=0 isZoneRedundant=False

    # Create a SQL API database
    az cosmosdb sql database create `
        --resource-group $resource_group `
        --account-name $account_name `
        --name $database_name

    # Create SQL API container
    az cosmosdb sql container create `
        --resource-group $resource_group `
        --account-name $account_name `
        --database-name $database_name `
        --name $container_name `
        --partition-key-path $partition_key `
        --ttl ($ttl_days * 24 * 3600)
}