function New-IIoTEnvironment(
    [string]$location = "eastus",
    [string]$resource_group = "IIoTRG",
    [string]$iot_hub_name = "iiot-hub",
    [string]$iot_hub_sku = "S1",
    [string]$edge_vm_size = "Standard_D2s_v3",
    [string]$acr_login_server = "marvacr.azurecr.io",
    [string]$acr_username = "marvacr",
    [SecureString]$acr_password = (ConvertTo-SecureString "29+U=lLvcnADESCbTUSwcn9XL0qiCyrN" -AsPlainText -Force)
)
{
    $env_hash = Get-EnvironmentHash -resource_group $resource_group
    $iot_hub_name = "$($iot_hub_name)-$($env_hash)"

    # create resource group
    az group create --name $resource_group --location $location

    #region create Linux VM (IoT edge device)
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
        --content EdgeSolution/modules/OPC/layered.deployment.json `
        --target-condition=$deployment_condition `
        --priority $priority
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

    #region stream analytics
    $asa_name = "asa-$($env_hash)"
    $asa_input_name = "iothub"
    $asa_output_name = "cosmosdb"
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

    # Define input settings
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

    $input_serialization = @{
        "type" = "Json"
        "properties" = @{
            "encoding" = "UTF8"
        }
    }

    # Define output settings
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

    $output_serialization = @{
        "type" = "Json"
        "properties" = @{
            "encoding" = "UTF8"
        }
    }

    # Define query
    $query = "SELECT
    GetMetadataPropertyValue($asa_input_name, 'EventId') AS id,
    SourceTimestamp,
    NodeId,
    ApplicationUri,
    IoTHub.ConnectionDeviceId,
    DipData,
    AlternatingBoolean,
    NegativeTrendData,
    PositiveTrendData,
    RandomSignedInt32,
    RandomUnsignedInt32,
    SpikeData,
    StepUp
    INTO $asa_input_name
    FROM $asa_output_name"

    # create ASA job
    New-StreamAnalyticsCloudJob `
        -location $location `
        -resource_group $resource_group `
        -job_name $asa_name `
        -input_name $asa_input_name `
        -input_datasource $input_job `
        -input_serialization $input_serialization `
        -output_name $asa_output_name `
        -output_datasource $output_datasource `
        -output_serialization $output_serialization `
        -query $query

    #region time series insight
    $tsi_name = "tsi-$($env_hash)"

    az timeseriesinsights environment standard create `
        --resource-group $resource_group `
        --
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

function Get-EnvironmentHash(
    [string]$resource_group)
)
{
    $hash_length = 8
    $Bytes = [System.Text.Encoding]::Unicode.GetBytes($resource_group)
    $env_hash = [Convert]::ToBase64String($Bytes).Substring($hash_length).ToLower()

    return $env_hash
}

function New-StreamAnalyticsEdgeJob(
    [string]$location = "eastus",
    [string]$resource_group = "IIoTRG",
    [string]$job_name,
    [string]$storage_name,
    [string]$storage_container
)
{
    $storage_key = az storage account keys list `
        --resource-group $resource_group `
        --account-name $storage_name `
        --query '[0].value' `
        -o tsv

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
            "inputs" = @(
                @{
                    "name" = "edgeinput"
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
            )
            "transformation" = @{
                "name" = "edgequery"
                "properties" = @{
                    "query" = "SELECT * INTO edgeoutput FROM edgeinput"
                }
            }
            "package" = @{
                "storageAccount" = @{
                    "accountName" = $storage_name
                    "accountKey" = $storage_key
                }
                "container" = $storage_container
            }
            "outputs" = @(
                @{
                    "name" = "edgeoutput"
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
            )
        }
    }

    $token = az account get-access-token --resource-type arm --query accessToken -o tsv
    $secure_token = ConvertTo-SecureString $token -AsPlainText -Force
    $content = ConvertTo-Json -InputObject $request -Depth 8
    $create_uri = "https://management.azure.com/subscriptions/$($subscription_id)/resourcegroups/$($resource_group)/providers/Microsoft.StreamAnalytics/streamingjobs/$($job_name)?api-version=2017-04-01-preview"
    $create_response = Invoke-RestMethod $create_uri `
        -Method PUT `
        -Body $content `
        -ContentType "application/json" `
        -Authentication Bearer -Token $secure_token

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
        
    return $package_response
}

function New-StreamAnalyticsCloudJob(
    [string]$location,
    [string]$resource_group,
    [string]$job_name,
    [string]$input_name,
    [string]$input_type = "Stream",
    [Hashtable]$input_datasource,
    [Hashtable]$input_serialization,
    [string]$output_name,
    [Hashtable]$output_datasource,
    [Hashtable]$output_serialization,
    [string]$query
)
{
    # create job
    az stream-analytics job create `
        --resource-group $resource_group `
        --name $job_name `
        --location $location `
        --compatibility-level 1.2 `
        --output-error-policy "Drop" `
        --events-outoforder-policy "Drop" `
        --events-outoforder-max-delay 5 `
        --events-late-arrival-max-delay 16 `
        --data-locale "en-US"

    # create job input
    Convertto-Json -InputObject $input_datasource | Set-Content ./input-datasource.json
    Convertto-Json -InputObject $input_serialization | Set-Content ./input-serialization.json

    az stream-analytics input create `
        --resource-group $resource_group `
        --job-name $job_name `
        --name $input_name `
        --type $input_type `
        --datasource input-datasource.json `
        --serialization input-serialization.json
    
    # create job output
    Convertto-Json -InputObject $output_datasource | Set-Content -Path ./output-datasource.json
    Convertto-Json -InputObject $output_serialization | Set-Content ./output-serialization.json

    az stream-analytics output create `
        --resource-group $resource_group `
        --job-name $job_name `
        --name $output_name `
        --datasource ./output-datasource.json `
        --serialization ./output-serialization.json

    # create transformation
    az stream-analytics transformation create `
        --resource-group $resource_group `
        --job-name $job_name `
        --name Transformation `
        --transformation-query $query
    
    # Start ASA job
    az stream-analytics job start `
        --resource-group $resource_group `
        --name $job_name
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