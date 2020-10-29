## https://docs.microsoft.com/en-us/azure/stream-analytics/stream-analytics-cicd-api

function New-IIoTEnvironment(
    [string]$location = "eastus",
    [string]$resource_group,
    [string]$iot_hub_sku = "S1",
    [string]$simulation_vm_size = "Standard_D2s_v3",
    [string]$edge_vm_size = "Standard_D2s_v3",
    [int]$eventhubs_message_retention = 7,
    [string]$notifications_webhook,
    [string]$alerts_webhook,
    [bool]$deploy_time_series_insights = $true
)
{
    if (!$notifications_webhook)
    {
        Write-Error "You need to provide a notification webhook. If you don't have one yet, you can get one for free at https://webhook.site/"
        return $null
    }
    if (!$notifications_webhook)
    {
        Write-Error "You need to provide an alert webhook. If you don't have one yet, you can get one for free at https://webhook.site/"
        return $null
    }

    $env_hash = Get-EnvironmentHash -resource_group $resource_group
    $iot_hub_name = "iothub-$($env_hash)"
    $deployment_condition = "tags.__type__='iiotedge'"

    # create resource group
    Write-Host -ForegroundColor Yellow "`r`nCreating resource group $resource_group"
    
    az group create --name $resource_group --location $location

    #region create IoT platform

    # VMs' credentials
    $password_length = 12
    $vm_username = "azureuser"
    $vm_password = New-Password -length $password_length

    # OPC Sim VM parameters
    $sim_vm_name = "opc-sim"
    $sim_vm_username = $vm_username
    $sim_vm_password = $vm_password
    $sim_vm_dns = "$($sim_vm_name)-$($env_hash)"
    
    # IoT Edge VM parameters
    $edge_vm_name = "linuxgateway-1"
    $edge_device_id = $edge_vm_name
    $edge_vm_username = $vm_username
    $edge_vm_password = $vm_password
    $edge_vm_dns = "$($edge_vm_name)-$($env_hash)"

    # virtual network parameters
    $vnet_name = "iiot-$($env_hash)-vnet"
    $vnet_prefix = "10.0.0.0/16"
    $sim_subnet_name = "opc"
    $sim_subnet_prefix = "10.0.0.0/24"
    $edge_subnet_name = "iotedge"
    $edge_subnet_prefix = "10.0.1.0/24"

    # datalake storage
    $persistent_storage_name = "telemetrystrg$($env_hash)"
    $persistent_storage_container = "telemetry"

    # event hubs
    $eh_name = "eh-$($env_hash)"
    $eh_notifications_name = "notifications"
    $eh_notifications_la_consumer_group = "logicapp"
    $eh_alerts_name = "alerts"
    $eh_alerts_la_consumer_group = "logicapp"
    $eh_alerts_tsi_consumer_group = "timeseriesinsights"
    $eh_telemetry_name = "telemetry"
    $eh_telemetry_tsi_consumer_group = "timeseriesinsights"
    $eh_send_policy_name = "send"
    $eh_listen_policy_name = "listen"

    # time series insights
    $tsi_name = "tsi-$($env_hash)"
    $tsi_sku = "L1"
    $tsi_capacity = 1
    $tsi_kind = "LongTerm"
    $tsi_storage_account = "tsistorage$($env_hash)"
    $tsi_timestamp_property = "SourceTimestamp"
    $tsi_id_properties = @(
        @{ "name" = "ApplicationUri"; "type" = "string" }
    )

    $username = az account show --query 'user.name' -o tsv
    $userid = az ad user show --id $username --query objectId -o tsv
    if (!$userid)
    {
        Write-Host -ForegroundColor Yellow "Unable to retrieve current user id. Contributors will have to be added manually to the TSI environment through the Azure Portal"
    }

    # edge stream analytics job
    $edge_asa_query = Get-Content -Path ./StreamAnalytics/EdgeASA/EdgeASA.asaql -Raw
    $edge_asa_input_name = "streaminput"
    $edge_asa_telemetry_output_name = "telemetryoutput"
    $edge_asa_alerts_output_name = "alertsoutput"

    # cloud stream analytics job
    $cloud_asa_query = Get-Content -Path ./StreamAnalytics/CloudASA/CloudASA.asaql -Raw

    $platform_parameters = @{
        "location" = @{ "value" = $location }
        "environmentHashId" = @{ "value" = $env_hash }
        "simVmName" = @{ "value" = $sim_vm_name }
        "simVmSize" = @{ "value" = $simulation_vm_size }
        #"simVmDnsName" = @{ "value" = $sim_vm_dns }
        "edgeVmName" = @{ "value" = $edge_vm_name }
        "edgeVmSize" = @{ "value" = $edge_vm_size }
        #"edgeVmDnsName" = @{ "value" = $edge_vm_dns }
        "adminUsername" = @{ "value" = $sim_vm_username }
        "adminPassword" = @{ "value" = $sim_vm_password }
        #"vnetName" = @{ "value" = $vnet_name }
        #"vnetAddressPrefix" = @{ "value" = $vnet_prefix }
        #"simSubnetName" = @{ "value" = $sim_subnet_name}
        #"simSubnetAddressRange" = @{ "value" = $sim_subnet_prefix }
        #"edgeSubnetName" = @{ "value" = $edge_subnet_name }
        #"edgeSubnetAddressRange" = @{ "value" = $edge_subnet_prefix }
        #"iotHubName" = @{ "value" = $iot_hub_name }
        #"dpsName" = @{ "value" = "dps-$($env_hash)" }
        "branchName" = @{ "value" = "opc-plc" }
        #"datalakeName" = @{ "value" = $persistent_storage_name }
        #"datalakeContainerName" = @{ "value" = $persistent_storage_container }
        #"eventHubNamespaceName" = @{ "value" = $eh_name }
        "eventHubRetentionInDays" = @{ "value" = $eventhubs_message_retention }
        #"tsiEnvironmentName" = @{ "value" =  $tsi_name }
        "tsiEnvironmentSku" = @{ "value" =  $tsi_sku }
        "tsiEnvironmentKind" = @{ "value" =  $tsi_kind }
        "tsiEnvironmentSkuCapacity" = @{ "value" =  $tsi_capacity }
        "tsiEnvironmentTimeSeriesIdProperties" = @{ "value" = $tsi_id_properties }
        #"tsiStorageAccountName" = @{ "value" =  $tsi_storage_account }
        "tsiTimestampPropertyName" = @{ "value" =  $tsi_timestamp_property }
        "tsiAccessPolicyObjectId" = @{ "value" = $userid }
        "notificationsWebhookUrl" = @{ "value" = $notifications_webhook }
        "alertsWebhookUrl" = @{ "value" = $alerts_webhook }
        "edgeASAJobQuery" = @{ "value" = ($edge_asa_query | Out-String) }
        "edgeASAJobInputName" = @{ "value" = $edge_asa_input_name }
        "edgeASAJobOutput1Name" = @{ "value" = $edge_asa_telemetry_output_name }
        "edgeASAJobOutput2Name" = @{ "value" = $edge_asa_alerts_output_name }
        "cloudASAJobQuery" = @{ "value" = ($cloud_asa_query | Out-String) }
    }
    Set-Content -Path ./Templates/azuredeploy.parameters.json -Value (ConvertTo-Json $platform_parameters -Depth 5)

    $deployment_output = az deployment group create `
        --resource-group $resource_group `
        --name 'IIoT' `
        --mode Incremental `
        --template-file ./Templates/azuredeploy.json `
        --parameters ./Templates/azuredeploy.parameters.json
    #endregion

    #region create IoT edge VM
    # Write-Host -ForegroundColor Yellow "`r`nCreating IoT edge virtual machine $edge_vm_name"

    # az vm image terms accept `
    #     --urn $edge_vm_image

    # az vm create `
    #     --location $location `
    #     --resource-group $resource_group `
    #     --name $edge_vm_name `
    #     --size $edge_vm_size `
    #     --image $edge_vm_image `
    #     --admin-username $edge_vm_username `
    #     --public-ip-address-dns-name $edge_vm_dns `
    #     --generate-ssh-keys

    # $publishednodes_file = "https://raw.githubusercontent.com/marvin-garcia/IoTGateway/opc-plc/EdgeSolution/modules/OPC/publishednodes.json"
    # $vm_custom_script = "{\`"commandToExecute\`": \`"mkdir -p /appdata && wget $publishednodes_file -O /appdata/publishednodes.json\`"}"
    # az vm extension set `
    #     --resource-group $resource_group `
    #     --vm-name $edge_vm_name `
    #     --name customScript `
    #     --publisher Microsoft.Azure.Extensions `
    #     --protected-settings $vm_custom_script
    #endregion

    #region iot hub
    
    # create iot hub
    Write-Host -ForegroundColor Yellow "`r`nCreating IoT hub $iot_hub_name"

    az iot hub create `
        --resource-group $resource_group `
        --name $iot_hub_name `
        --sku $iot_hub_sku

    # create edge device in hub
    Write-Host -ForegroundColor Yellow "`r`nRegistering edge device id $edge_device_id"

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
    Write-Host -ForegroundColor Yellow "`r`nUpdating edge device's twin tags"

    $device_tags = '{ \"environment\": \"dev\" }'
    az iot hub device-twin update --hub-name $iot_hub_name --device-id $edge_device_id --set tags="$device_tags"

    # create built-in events route
    az iot hub route create `
        --resource-group $resource_group `
        --hub-name $iot_hub_name `
        --endpoint-name "events" `
        --name "built-in-events-route" `
        --source devicemessages `
        --condition true
    
    # Create main deployment
    # Write-Host -ForegroundColor Yellow "`r`nCreating main IoT edge device deployment"

    # az iot edge deployment create `
    #     -d main-deployment `
    #     --hub-name $iot_hub_name `
    #     --content ./EdgeSolution/deployment.template.json `
    #     --target-condition=$deployment_condition
    #endregion

    #region permanent storage
    
    #region storage blob
    $persistent_storage_name = "telemetrystrg$($env_hash)"
    $persistent_storage_container = "telemetry"

    Write-Host -ForegroundColor Yellow "`r`nCreating storage account $persistent_storage_name"

    az storage account create `
        --location $location `
        --resource-group $resource_group `
        --name $persistent_storage_name `
        --access-tier Hot `
        --kind StorageV2 `
        --sku Standard_LRS

    $persistent_storage_key = az storage account keys list `
        --resource-group $resource_group `
        --account-name $persistent_storage_name `
        --query '[0].value' `
        -o tsv
    
    az storage container create `
        --resource-group $resource_group `
        --account-name $persistent_storage_name `
        --account-key $persistent_storage_key `
        --name $persistent_storage_container
    
    # create IoT hub storage route
    New-IoTStoragePipeline `
        -resource_group $resource_group `
        -hub_name $iot_hub_name `
        -endpoint_name telemetrystorage `
        -route_name telemetrystorage `
        -storage_account_name $persistent_storage_name `
        -container_name $persistent_storage_container
    #endregion
    
    #endregion

    #region event hubs
    $eh_name = "eh-$($env_hash)"
    $eh_notifications_name = "notifications"
    $eh_notifications_la_consumer_group = "logicapp"
    $eh_alerts_name = "alerts"
    $eh_alerts_la_consumer_group = "logicapp"
    $eh_alerts_tsi_consumer_group = "timeseriesinsights"
    $eh_telemetry_name = "telemetry"
    $eh_telemetry_tsi_consumer_group = "timeseriesinsights"
    $eh_send_policy_name = "send"
    $eh_listen_policy_name = "listen"
    
    # create namespace
    Write-Host -ForegroundColor Yellow "`r`nCreating event hubs namespace $eh_name"

    az eventhubs namespace create `
        --location $location `
        --resource-group $resource_group `
        --name $eh_name `
        --sku Standard
    
    # create send authorization rule
    az eventhubs namespace authorization-rule create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --name $eh_send_policy_name `
        --rights Send

    # create listen authorization rule
    az eventhubs namespace authorization-rule create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --name $eh_listen_policy_name `
        --rights Listen

    #region notifications event hub
    
    # create event hub
    Write-Host -ForegroundColor Yellow "`r`nCreating event hub $eh_notifications_name"

    az eventhubs eventhub create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --name $eh_notifications_name `
        --message-retention $eventhubs_message_retention

    # create consumer group
    az eventhubs eventhub consumer-group create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_notifications_name `
        --name $eh_notifications_la_consumer_group
    #endregion

    #region alerts event hub
    
    # create event hub
    Write-Host -ForegroundColor Yellow "`r`nCreating event hub $eh_alerts_name"

    az eventhubs eventhub create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --name $eh_alerts_name `
        --message-retention $eventhubs_message_retention

    # create consumer groups
    az eventhubs eventhub consumer-group create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_alerts_name `
        --name $eh_alerts_la_consumer_group
    
    az eventhubs eventhub consumer-group create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_alerts_name `
        --name $eh_alerts_tsi_consumer_group
    #endregion

    #region telemetry event hub
    
    # create event hub
    Write-Host -ForegroundColor Yellow "`r`nCreating event hub $eh_telemetry_name"

    az eventhubs eventhub create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --name $eh_telemetry_name `
        --message-retention $eventhubs_message_retention

    # create consumer group
    az eventhubs eventhub consumer-group create `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --eventhub-name $eh_telemetry_name `
        --name $eh_telemetry_tsi_consumer_group
    #endregion

    #region retrieve details for event hubs
    $eh_alerts_id = az eventhubs eventhub show `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --name $eh_alerts_name `
        --query id `
        -o tsv

    $eh_telemetry_id = az eventhubs eventhub show `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --name $eh_telemetry_name `
        --query id `
        -o tsv

    $eh_listen_connectionstring = az eventhubs namespace authorization-rule keys list `
        --resource-group $resource_group `
        --namespace-name $eh_name `
        --name $eh_listen_policy_name `
        --query primaryConnectionString -o tsv

    $eh_listen_shared_key = $eh_listen_connectionstring.Split(';')[2].Split('SharedAccessKey=')[1]

    $eh_send_key = az eventhubs namespace authorization-rule keys list `
        --resource-group $resource_group `
        --namespace-name $eh_name `
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
        # "Output_storageblob_Storage1_accountName" = @{ "value" = $persistent_storage_name }
        # "Output_storageblob_Storage1_accountKey" = @{ "value" = $persistent_storage_key }
        # "Output_storageblob_container" = @{ "value" = $persistent_storage_container }
        # "Output_storageblob_pathPattern" = @{ "value" = "{ConnectionDeviceId}/{datetime:yyyy}/{datetime:MM}/{datetime:dd}/{datetime:HH}/{datetime:mm}" }
        # "Output_storageblob_dateFormat" = @{ "value" = "yyyy/MM/dd" }
        # "Output_storageblob_timeFormat" = @{ "value" = "HH" }
        # "Output_storageblob_authenticationMode" = @{ "value" = "ConnectionString" }
        "Output_notificationshub_serviceBusNamespace" = @{ "value" = $eh_name }
        "Output_notificationshub_eventHubName" = @{ "value" = $eh_notifications_name }
        "Output_notificationshub_partitionKey" = @{ "value" = "" }
        "Output_notificationshub_sharedAccessPolicyName" = @{ "value" = $eh_send_policy_name }
        "Output_notificationshub_sharedAccessPolicyKey" = @{ "value" = $eh_send_key }
        "Output_alertshub_serviceBusNamespace" = @{ "value" = $eh_name }
        "Output_alertshub_eventHubName" = @{ "value" = $eh_alerts_name }
        "Output_alertshub_partitionKey" = @{ "value" = "" }
        "Output_alertshub_sharedAccessPolicyName" = @{ "value" = $eh_send_policy_name }
        "Output_alertshub_sharedAccessPolicyKey" = @{ "value" = $eh_send_key }
        "Output_telemetryhub_serviceBusNamespace" = @{ "value" = $eh_name }
        "Output_telemetryhub_eventHubName" = @{ "value" = $eh_telemetry_name }
        "Output_telemetryhub_partitionKey" = @{ "value" = "" }
        "Output_telemetryhub_sharedAccessPolicyName" = @{ "value" = $eh_send_policy_name }
        "Output_telemetryhub_sharedAccessPolicyKey" = @{ "value" = $eh_send_key }
    }
    Set-Content -Value (ConvertTo-Json $asa_parameters) -Path StreamAnalytics/CloudASA/Deploy/params.json

    Write-Host -ForegroundColor Yellow "`r`nCreating cloud stream analytics job $asa_name"

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
    Write-Host -ForegroundColor Yellow "`r`nCreating edge stream analytics storage account $asa_edge_storage_name"

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

    # create storage container
    az storage container create `
        --resource-group $resource_group `
        --account-name $asa_edge_storage_name `
        --account-key $asa_edge_storage_key `
        --name $asa_edge_container_name

    [Array]$input_files = ((Get-Content ./StreamAnalytics/EdgeASA/asaproj.json `
        | ConvertFrom-Json).configurations | `
        Where-Object { $_.subType -eq "Input" -and $_.filePath -notlike "*iothub.json" }).filePath
    [Array]$asa_edge_input_names = @()
    foreach ($file in $input_files)
    {
        $asa_edge_input_names += $file.Split('/')[1].Split('.')[0]
    }

    [Array]$output_files = ((Get-Content ./StreamAnalytics/EdgeASA/asaproj.json `
        | ConvertFrom-Json).configurations | `
        Where-Object { $_.subType -eq "Output" }).filePath
    [Array]$asa_edge_output_names = @()
    foreach ($file in $output_files)
    {
        $asa_edge_output_names += $file.Split('/')[1].Split('.')[0]
    }
    
    # read edge job query
    $asa_edge_query = Get-Content -Path StreamAnalytics/EdgeASA/EdgeASA.asaql -Raw

    # create edge job
    Write-Host -ForegroundColor Yellow "`r`nCreating edge stream analytics job $asa_edge_name"

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
    Write-Host -ForegroundColor Yellow "`r`nPublishing edge stream analytics job $asa_edge_name"

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
    
    Write-Host -ForegroundColor Yellow "`r`nCreating IoT edge layered deployment $opc_deployment_name-$priority"

    az iot edge deployment create `
        --layered `
        -d "$opc_deployment_name-$priority" `
        --hub-name $iot_hub_name `
        --content EdgeSolution/modules/OPC/layered.deployment.json `
        --target-condition=$deployment_condition `
        --priority $priority
    #endregion

    #region notification & alerting

    #region notification

    #region event grid topic
    $notifications_topic_name = "eg-notifications-$($env_hash)"
    $notifications_subscription_name = "notifications"

    Write-Host -ForegroundColor Yellow "`r`nCreating event grid topic $notifications_topic_name"

    az eventgrid topic create `
        --location $location `
        --resource-group $resource_group `
        --name $notifications_topic_name

    $notifications_topic_id = az eventgrid topic show `
        --resource-group $resource_group `
        --name $notifications_topic_name `
        --query id -o tsv

    $notifications_topic_endpoint = az eventgrid topic show `
        --resource-group $resource_group `
        --name $notifications_topic_name `
        --query endpoint -o tsv

    $notifications_topic_key = az eventgrid topic key list `
        --resource-group $resource_group `
        --name $notifications_topic_name `
        --query key1 `
        -o tsv

    az eventgrid event-subscription create `
        --source-resource-id $notifications_topic_id `
        --endpoint $notifications_webhook `
        --name $notifications_subscription_name
    
    Write-Host -ForegroundColor Yellow "`r`n`r`nMake sure you use the Validation URL to enable the subscription for endpoint $notifications_webhook."
    #endregion

    #region logic app
    $notifications_app_name = "NotificationsApp"
    $notifications_app_parameters = @{
        "logicAppName" = @{ "value" = $notifications_app_name }
        "eventhubs_1_Consumer_Group" = @{ "value" = $eh_notifications_la_consumer_group }
        "eventhubs_1_connectionString" = @{ "value" = $eh_listen_connectionstring }
        "azureeventgridpublish_1_endpoint" = @{ "value" = $notifications_topic_endpoint }
        "azureeventgridpublish_1_api_key" = @{ "value" = $notifications_topic_key }
    }
    Set-Content -Path ./LogicApps/NotificationsApp/LogicApp.parameters.json -Value (ConvertTo-Json $notifications_app_parameters)

    Write-Host -ForegroundColor Yellow "`r`nCreating notifications logic app $notifications_app_name"

    az deployment group create `
        --resource-group $resource_group `
        --name $notifications_app_name `
        --mode Incremental `
        --template-file ./LogicApps/NotificationsApp/LogicApp.json `
        --parameters ./LogicApps/NotificationsApp/LogicApp.parameters.json
    #endregion

    #endregion

    #region alerting

    #region event grid topic
    $alerts_topic_name = "eg-alerts-$($env_hash)"
    $alerts_subscription_name = "alerts"

    Write-Host -ForegroundColor Yellow "`r`nCreating event grid topic $alerts_topic_name"

    az eventgrid topic create `
        --location $location `
        --resource-group $resource_group `
        --name $alerts_topic_name

    $alerts_topic_id = az eventgrid topic show `
        --resource-group $resource_group `
        --name $alerts_topic_name `
        --query id -o tsv

    $alerts_topic_endpoint = az eventgrid topic show `
        --resource-group $resource_group `
        --name $alerts_topic_name `
        --query endpoint -o tsv

    $alerts_topic_key = az eventgrid topic key list `
        --resource-group $resource_group `
        --name $alerts_topic_name `
        --query key1 `
        -o tsv

    az eventgrid event-subscription create `
        --source-resource-id $alerts_topic_id `
        --endpoint $alerts_webhook `
        --name $alerts_subscription_name
    
    Write-Host -ForegroundColor Yellow "`r`n`r`nMake sure you use the Validation URL to enable the subscription for endpoint $alerts_webhook."
    #endregion

    #region logic app
    $alerts_app_name = "AlertsApp"
    $alerts_app_parameters = @{
        "logicAppName" = @{ "value" = $alerts_app_name }
        "eventhubs_1_Consumer_Group" = @{ "value" = $eh_alerts_la_consumer_group }
        "eventhubs_1_connectionString" = @{ "value" = $eh_listen_connectionstring }
        "azureeventgridpublish_1_endpoint" = @{ "value" = $alerts_topic_endpoint }
        "azureeventgridpublish_1_api_key" = @{ "value" = $alerts_topic_key }
    }
    Set-Content -Path ./LogicApps/AlertsApp/LogicApp.parameters.json -Value (ConvertTo-Json $alerts_app_parameters)

    Write-Host -ForegroundColor Yellow "`r`nCreating alerting logic app $alerts_app_name"

    az deployment group create `
        --resource-group $resource_group `
        --name $alerts_app_name `
        --mode Incremental `
        --template-file ./LogicApps/AlertsApp/LogicApp.json `
        --parameters ./LogicApps/AlertsApp/LogicApp.parameters.json
    #endregion

    #endregion

    #endregion

    #region time series insight
    if ($deploy_time_series_insights)
    {
        $tsi_name = "tsi-opc-$($env_hash)"
        $tsi_storage_account = "tsistorage$($env_hash)"
        $tsi_id_properties = @(
            # @{ "name" = "ConnectionDeviceId"; "type" = "string" }
            @{ "name" = "ApplicationUri"; "type" = "string" }
        )

        $username = az account show --query 'user.name' -o tsv
        $userid = az ad user show --id $username --query objectId -o tsv
        if (!$userid)
        {
            Write-Host -ForegroundColor Yellow "Unable to retrieve current user id. Contributors will have to be added manually to the TSI environment through the Azure Portal"
        }

        $tsi_deployment = New-TimeSeriesInsightsEnvironment `
            -location $location `
            -resource_group $resource_group `
            -tsi_name $tsi_name `
            -tsi_storage_account $tsi_storage_account `
            -tsi_id_properties $tsi_id_properties `
            -contributor_object_id $userid `
            -event_source1_name "telemetryhub" `
            -event_source1_resource_id $eh_telemetry_id `
            -event_source1_resource_namespace $eh_name `
            -event_source1_resource_name $eh_telemetry_name `
            -event_source1_policy_name $eh_listen_policy_name `
            -event_source1_shared_key $eh_listen_shared_key `
            -event_source1_consumer_group $eh_telemetry_tsi_consumer_group `
            -event_source1_timestamp_property "SourceTimestamp" `
            -event_source2_name "alertshub" `
            -event_source2_resource_id $eh_alerts_id `
            -event_source2_resource_namespace $eh_name `
            -event_source2_resource_name $eh_alerts_name `
            -event_source2_policy_name $eh_listen_policy_name `
            -event_source2_shared_key $eh_listen_shared_key `
            -event_source2_consumer_group $eh_alerts_tsi_consumer_group `
            -event_source2_timestamp_property "SourceTimestamp"

        Add-TimeSeriesInsightsModel `
            -resource_group $resource_group `
            -tsi_name $tsi_name `
            -tsi_types (Get-Content -Path ./TimeSeriesInsights/Model/types.json) `
            -tsi_hierarchies (Get-Content -Path ./TimeSeriesInsights/Model/hierarchies.json) `
            -tsi_instances (Get-Content -Path ./TimeSeriesInsights/Model/instances.json)
    }
    #endregion

    Write-Host ""
    Write-Host -foregroundColor Yellow "Edge VM Credentials:"
    Write-Host -foregroundColor Yellow "Username: $edge_vm_username"
    Write-Host -foregroundColor Yellow "Password: $edge_vm_password"
    Write-Host -foregroundColor Yellow "DNS: $($edge_vm_dns).$($location).cloudapp.azure.com"
    
    if ($deploy_time_series_insights)
    {
        Write-Host -foregroundColor Yellow "`r`nTSI Environment:"
        Write-Host -foregroundColor Yellow "DNS: https://$($tsi_deployment.properties.outputs.dataAccessFQDN.value)"
        Write-Host -ForegroundColor Yellow "In order to access the TSI dashboard, you have to go to the Azure portal and add yourself as a data contributor in the Time Series Insights environment"
    }
}

function New-IoTStoragePipeline(
    [string]$subscription_id,
    [string]$resource_group,
    [string]$hub_name,
    [string]$endpoint_name,
    [string]$route_name,
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
        --hub-name $hub_name `
        --endpoint-subscription-id $subscription_id `
        --endpoint-resource-group $resource_group `
        --endpoint-type azurestoragecontainer `
        --endpoint-name $endpoint_name `
        --container $container_name `
        --connection-string $connection_string `
        --encoding json
    
    az iot hub route create `
        --resource-group $resource_group `
        --hub-name $hub_name `
        --endpoint-name $endpoint_name `
        --name $route_name `
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

Function New-Password() {
    param(
        $length = 15
    )
    $punc = 46..46
    $digits = 48..57
    $lcLetters = 65..90
    $ucLetters = 97..122
    $password = `
        [char](Get-Random -Count 1 -InputObject ($lcLetters)) + `
        [char](Get-Random -Count 1 -InputObject ($ucLetters)) + `
        [char](Get-Random -Count 1 -InputObject ($digits)) + `
        [char](Get-Random -Count 1 -InputObject ($punc))
    $password += get-random -Count ($length - 4) `
        -InputObject ($punc + $digits + $lcLetters + $ucLetters) |`
        ForEach-Object -begin { $aa = $null } -process { $aa += [char]$_ } -end { $aa }

    return $password
}

function Get-EnvironmentHash(
    
    [string]$subscription_id,
    [string]$resource_group,
    [string]$username
)
{
    if (!$subscription_id)
    {
        $subscription_id = az account show --query id -o tsv
    }
    if (!$username)
    {
        $username = az account show --query 'user.name' -o tsv
    }
    $hash_length = 8
    $Bytes = [System.Text.Encoding]::Unicode.GetBytes("$resource_group-$username")
    $env_hash = [Convert]::ToBase64String($Bytes).Substring(0, $hash_length).ToLower()

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
    [string][ValidateSet('Array', 'LineSeparated')]$output_format = "Array",
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
                        "format" = $output_format
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
    
    if ($package_response.status -eq 'Failed')
    {
        Write-Error "Failed to publish ASA edge job. $($package_response.error.message)"
        return $null
    }

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

function New-TimeSeriesInsightsEnvironment(
    [string]$location,
    [string]$resource_group,
    [string]$tsi_name,
    [string]$tsi_storage_account,
    [array]$tsi_id_properties,
    [string]$contributor_object_id,
    [string]$event_source1_name,
    [string]$event_source1_resource_id,
    [string]$event_source1_resource_namespace,
    [string]$event_source1_resource_name,
    [string]$event_source1_policy_name,
    [string]$event_source1_shared_key,
    [string]$event_source1_consumer_group,
    [string]$event_source1_timestamp_property,
    [string]$event_source2_name,
    [string]$event_source2_resource_id,
    [string]$event_source2_resource_namespace,
    [string]$event_source2_resource_name,
    [string]$event_source2_policy_name,
    [string]$event_source2_shared_key,
    [string]$event_source2_consumer_group,
    [string]$event_source2_timestamp_property
)
{
    $tsi_parameters = @{
        "location" = @{ "value" =  $location }
        "environmentName" = @{ "value" =  $tsi_name }
        "environmentSkuName" = @{ "value" =  "L1" }
        "environmentKind" = @{ "value" =  "LongTerm" }
        "environmentSkuCapacity" = @{ "value" =  1 }
        "environmentTimeSeriesIdProperties" = @{ "value" = $tsi_id_properties }
        "storageAccountName" = @{ "value" =  $tsi_storage_account }
        "eventSource_1_Name" = @{ "value" =  $event_source1_name }
        "eventSource_1_ResourceId" = @{ "value" = $event_source1_resource_id }
        "eventSource_1_ResourceNamespace" = @{ "value" =  $event_source1_resource_namespace }
        "eventSource_1_ResourceName" = @{ "value" =  $event_source1_resource_name }
        "eventSource_1_ConsumerGroupName" = @{ "value" =  $event_source1_consumer_group }
        "eventSource_1_PolicyName" = @{ "value" =  $event_source1_policy_name }
        "eventSource_1_SharedAccessKey" = @{ "value" = $event_source1_shared_key }
        "eventSource_1_TimestampPropertyName" = @{ "value" =  $event_source1_timestamp_property }
        "eventSource_2_Name" = @{ "value" =  $event_source2_name }
        "eventSource_2_ResourceId" = @{ "value" = $event_source2_resource_id }
        "eventSource_2_ResourceNamespace" = @{ "value" =  $event_source2_resource_namespace }
        "eventSource_2_ResourceName" = @{ "value" =  $event_source2_resource_name }
        "eventSource_2_ConsumerGroupName" = @{ "value" =  $event_source2_consumer_group }
        "eventSource_2_PolicyName" = @{ "value" =  $event_source2_policy_name }
        "eventSource_2_SharedAccessKey" = @{ "value" = $event_source2_shared_key }
        "eventSource_2_TimestampPropertyName" = @{ "value" =  $event_source2_timestamp_property }
    }

    if (!!$contributor_object_id)
    {
        $tsi_parameters["accessPolicyObjectId"] = @{ "value" = $contributor_object_id }
    }
    Set-Content -Path ./TimeSeriesInsights/azuredeploy.parameters.json -Value (ConvertTo-Json $tsi_parameters -Depth 10)

    Write-Host -ForegroundColor Yellow "`r`nCreating Time Series Insights environment $tsi_name"

    $tsi_deployment = az deployment group create `
        --resource-group $resource_group `
        --name $tsi_name `
        --mode Incremental `
        --template-file ./TimeSeriesInsights/azuredeploy.json `
        --parameters ./TimeSeriesInsights/azuredeploy.parameters.json

    $tsi_deployment = $tsi_deployment | ConvertFrom-Json

    return $tsi_deployment
}

function Add-TimeSeriesInsightsModel(
    [string]$resource_group,
    [string]$tsi_name,
    [string]$tsi_types,
    [string]$tsi_hierarchies,
    [string]$tsi_instances
)
{
    # Get auth token
    if (!$subscription_id)
    {
        $subscription_id = az account show --query id -o tsv
    }
    $token = az account get-access-token --resource='https://api.timeseries.azure.com/' --query accessToken -o tsv
    $secure_token = ConvertTo-SecureString $token -AsPlainText -Force
    
    #region types
    Write-Host -ForegroundColor Yellow "`r`nCreating Time Series Insights types"
    
    $tsi_fqdn = az timeseriesinsights environment show -g $resource_group -n $tsi_name --query dataAccessFqdn -o tsv
    $types_uri = "https://$($tsi_fqdn)/timeseries/types/`$batch?api-version=2020-07-31"
    
    Invoke-RestMethod $types_uri `
        -Method POST `
        -Body $tsi_types `
        -ContentType "application/json" `
        -Authentication Bearer -Token $secure_token
    #endregion

    #region hierarchies
    Write-Host -ForegroundColor Yellow "`r`nCreating Time Series Insights hierarchies"
    
    $hierarchies_uri = "https://$($tsi_fqdn)/timeseries/hierarchies/`$batch?api-version=2020-07-31"
    
    Invoke-RestMethod $hierarchies_uri `
        -Method POST `
        -Body $tsi_hierarchies `
        -ContentType "application/json" `
        -Authentication Bearer -Token $secure_token
    #endregion

    #region instances
    Write-Host -ForegroundColor Yellow "`r`nCreating Time Series Insights instances"
    
    $instances_uri = "https://$($tsi_fqdn)/timeseries/instances/`$batch?api-version=2020-07-31"
    
    Invoke-RestMethod $instances_uri `
        -Method POST `
        -Body $tsi_instances `
        -ContentType "application/json" `
        -Authentication Bearer -Token $secure_token
    #endregion
}