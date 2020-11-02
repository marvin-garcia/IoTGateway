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
    # $sim_vm_dns = "$($sim_vm_name)-$($env_hash)"
    
    # IoT Edge VM parameters
    $edge_vm_name = "linuxgateway-1"
    $edge_device_id = $edge_vm_name
    $edge_vm_username = $vm_username
    $edge_vm_password = $vm_password
    $edge_vm_dns = "$($edge_vm_name)-$($env_hash)"
    $published_nodes_path = "/appdata/publishednodes.json"

    # virtual network parameters
    # $vnet_name = "iiot-$($env_hash)-vnet"
    # $vnet_prefix = "10.0.0.0/16"
    # $sim_subnet_name = "opc"
    # $sim_subnet_prefix = "10.0.0.0/24"
    # $edge_subnet_name = "iotedge"
    # $edge_subnet_prefix = "10.0.1.0/24"

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
    $edge_asa_name = "asa-edge-$($env_hash)"
    $edge_asa_query = Get-Content -Path ./StreamAnalytics/EdgeASA/EdgeASA.asaql -Raw
    $edge_asa_input_name = "streaminput"
    $edge_asa_telemetry_output_name = "telemetryoutput"
    $edge_asa_alerts_output_name = "alertsoutput"

    # cloud stream analytics job
    $cloud_asa_query = Get-Content -Path ./StreamAnalytics/CloudASA/CloudASA.asaql -Raw

    # data explorer
    $adx_cluster_name = "adx$($env_hash)"
    $adx_db_name = "TelemetryDB"
    $adx_principal_id = $username
    $adx_principal_type = "User"
    $adx_access_role = "Admin"

    $platform_parameters = @{
        "location" = @{ "value" = $location }
        "environmentHashId" = @{ "value" = $env_hash }
        "simVmName" = @{ "value" = $sim_vm_name }
        "simVmSize" = @{ "value" = $simulation_vm_size }
        "edgeVmName" = @{ "value" = $edge_vm_name }
        "edgeVmSize" = @{ "value" = $edge_vm_size }
        "edgeVmPublishedNodesPath" = @{ "value" = $published_nodes_path }
        "adminUsername" = @{ "value" = $sim_vm_username }
        "adminPassword" = @{ "value" = $sim_vm_password }
        "vnetName" = @{ "value" = $vnet_name }
        "vnetAddressPrefix" = @{ "value" = $vnet_prefix }
        "simSubnetName" = @{ "value" = $sim_subnet_name}
        "simSubnetAddressRange" = @{ "value" = $sim_subnet_prefix }
        "edgeSubnetName" = @{ "value" = $edge_subnet_name }
        "edgeSubnetAddressRange" = @{ "value" = $edge_subnet_prefix }
        #"iotHubName" = @{ "value" = $iot_hub_name }
        #"dpsName" = @{ "value" = "dps-$($env_hash)" }
        "branchName" = @{ "value" = "opc-plc" }
        #"datalakeName" = @{ "value" = $persistent_storage_name }
        #"datalakeContainerName" = @{ "value" = $persistent_storage_container }
        #"eventHubNamespaceName" = @{ "value" = $eh_name }
        "eventHubRetentionInDays" = @{ "value" = $eventhubs_message_retention }
        "deployTsiEnvironment"= @{ "value" = $deploy_time_series_insights }
        "tsiEnvironmentName" = @{ "value" =  $tsi_name }
        "tsiEnvironmentSku" = @{ "value" =  $tsi_sku }
        "tsiEnvironmentKind" = @{ "value" =  $tsi_kind }
        "tsiEnvironmentSkuCapacity" = @{ "value" =  $tsi_capacity }
        "tsiEnvironmentTimeSeriesIdProperties" = @{ "value" = $tsi_id_properties }
        "tsiTimestampPropertyName" = @{ "value" =  $tsi_timestamp_property }
        "tsiAccessPolicyObjectId" = @{ "value" = $userid }
        "adxClusterName" = @{ "value" = $adx_cluster_name }
        "adxDatabaseName" = @{ "value" = $adx_db_name }
        "adxAccessPolicyPrincipalId" = @{ "value" = $adx_principal_id }
        "adxAccessPolicyPrincipalType" = @{ "value" = $adx_principal_type }
        "adxAccessPolicyRole" = @{ "value" = $adx_access_role }
        "adxAccessPrincipalAssignmentId" = @{ "value" = $userid }
        "notificationsWebhookUrl" = @{ "value" = $notifications_webhook }
        "alertsWebhookUrl" = @{ "value" = $alerts_webhook }
        "edgeASAJobName" = @{ "value" = $edge_asa_name }
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

    #region edge deployment
    $opc_deployment_name = "opc"
    $priority = 1

    # publish edge stream analytics job
    Write-Host -ForegroundColor Yellow "`r`nPublishing edge stream analytics job "

    $edge_package = Publish-StreamAnalyticsEdgeJob `
        -resource_group $resource_group `
        -job_name $edge_asa_name

    # update IoT edge deployment with stream analytics job details
    (Get-Content -Path EdgeSolution/modules/OPC/layered.deployment.template.json -Raw) | ForEach-Object {
        $_ -replace '__ASA_ENV__', (ConvertTo-Json -InputObject $edge_package.env -Depth 10) `
           -replace '__ASA_INPUT_NAME__', $edge_package.endpoints.inputs[0] `
           -replace '__ASA_DESIRED_PROPERTIES__', (ConvertTo-Json -InputObject $edge_package.twin.content.properties_desired -Depth 10)
    } | Set-Content -Path EdgeSolution/modules/OPC/layered.deployment.json

    # Create main deployment
    Write-Host -ForegroundColor Yellow "`r`nCreating main IoT edge device deployment"

    az iot edge deployment create `
        -d "main-deployment" `
        --hub-name $iot_hub_name `
        --content ./EdgeSolution/deployment.template.json `
        --target-condition=$deployment_condition

    # Create OPC layered deployment
    Write-Host -ForegroundColor Yellow "`r`nCreating IoT edge layered deployment $opc_deployment_name-$priority"

    az iot edge deployment create `
        --layered `
        -d "$opc_deployment_name-$priority" `
        --hub-name $iot_hub_name `
        --content EdgeSolution/modules/OPC/layered.deployment.json `
        --target-condition=$deployment_condition `
        --priority $priority
    #endregion

    #region Tsime series insights modeling
    if ($deploy_time_series_insights)
    {
        Add-TimeSeriesInsightsModel `
            -resource_group $resource_group `
            -tsi_name $tsi_name `
            -tsi_types (Get-Content -Path ./TimeSeriesInsights/Model/types.json) `
            -tsi_hierarchies (Get-Content -Path ./TimeSeriesInsights/Model/hierarchies.json) `
            -tsi_instances (Get-Content -Path ./TimeSeriesInsights/Model/instances.json)
    }
    #endregion

    Write-Host ""
    Write-Host -foregroundColor Yellow "OPC Sim & IoT Edge VM Credentials:"
    Write-Host -foregroundColor Yellow "Username: $vm_username"
    Write-Host -foregroundColor Yellow "Password: $vm_password"
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