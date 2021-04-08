function New-IIoTEnvironment()
{
    Write-Host "Please provide a webhook URL for notifications and alerts. If you don't have one yet, you can get one for free at https://webhook.site/"
    $webhook_url = Read-Host -Prompt ">"
    
    $deploy_time_series_insights = $false
    $tsi_providers = $(az provider show -n 'Microsoft.TimeSeriesInsights')
    if ($tsi_providers)
    {
        $deploy_time_series_insights = $true
    }
    else
    {
        $deploy_time_series_insights = $false
        Write-Warning "Unable to find TimeSeriesInsights provider. Deploymend will skip the creation of Azure Time Series Insights"
    }

    #region obtain deployment location
    $locations = Get-ResourceGroupLocations -provider 'Microsoft.Devices' -typeName 'ProvisioningServices'
    
    Write-Host "Please choose a location for your deployment from this list (using its Index):"
    for ($index = 0; $index -lt $locations.Count; $index++)
    {
        Write-Host "$($index + 1): $($locations[$index])"
    }
    while ($true)
    {
        $option = Read-Host -Prompt ">"
        try
        {
            if ([int]$option -ge 1 -and [int]$option -le $locations.Count)
            {
                break
            }
        }
        catch
        {
            Write-Host "Invalid index '$($option)' provided."
        }
        Write-Host "Choose from the list using an index between 1 and $($locations.Count)."
    }
    $location_name = $locations[$option - 1]
    $location = $location_name.Replace(' ', '').ToLower()
    Write-Host "Using location $($location)"
    #endregion

    #region obtain resource group name
    $resource_group = $null
    $first = $true
    while ([string]::IsNullOrEmpty($resource_group) -or ($resource_group -notmatch "^[a-z0-9-_]*$"))
    {
        if ($first -eq $false)
        {
            Write-Host "Use alphanumeric characters as well as '-' or '_'."
        }
        else
        {
            Write-Host
            Write-Host "Please provide a name for the resource group."
            $first = $false
        }
        $resource_group = Read-Host -Prompt ">"
    }

    $resourceGroup = az group show --name $resource_group | ConvertFrom-Json
    if (!$resourceGroup)
    {
        Write-Host "Resource group '$resource_group' does not exist."
        
        $resourceGroup = az group create --name $resource_group --location $location | ConvertFrom-Json
        Write-Host "Created new resource group $($resource_group) in $($resourceGroup.location)."
    }
    #endregion

    $root_path = Split-Path $PSScriptRoot -Parent

    $env_hash = Get-EnvironmentHash
    $iot_hub_name = "iothub-$($env_hash)"
    $deployment_condition = "tags.__type__='iiotedge'"

    #region virtual machine details
    $skus = az vm list-skus | ConvertFrom-Json -AsHashtable
    $vm_skus = $skus | Where-Object { $_.resourceType -eq 'virtualMachines' -and $_.locations -contains $location -and $_.restrictions.Count -eq 0 }
    $vm_sku_names = $vm_skus | Select-Object -ExpandProperty Name -Unique
    #endregion

    #region create IoT platform

    # VMs' credentials
    $password_length = 12
    $vm_username = "azureuser"
    $vm_password = New-Password -length $password_length

    #region OPC Sim VM parameters
    $sim_vm_name = "opc-sim"

    # We will use VM with at least 1 core and 2 GB of memory for hosting OPC PLC simulatoin containers.
    $sim_vm_sizes = az vm list-sizes --location $location | ConvertFrom-Json `
    | Where-Object { $vm_sku_names -icontains $_.name } `
    | Where-Object {
        ($_.numberOfCores -ge 1) -and `
        ($_.memoryInMB -ge 2048) -and `
        ($_.osDiskSizeInMB -ge 1047552) -and `
        ($_.resourceDiskSizeInMB -ge 4096)
    } `
    | Sort-Object -Property `
        NumberOfCores, MemoryInMB, ResourceDiskSizeInMB, Name
    # Pick top
    if ($sim_vm_sizes.Count -ne 0)
    {
        $sim_vm_size = $sim_vm_sizes[0].Name
        Write-Host "Using $($sim_vm_size) as VM size for all edge simulation hosts..."
    }
    #endregion

    #region IoT Edge VM parameters
    $edge_vm_name = "linuxgateway-1"
    $published_nodes_path = "/appdata/publishednodes.json"
    
    # We will use VM with at least 2 cores and 8 GB of memory as gateway host.
    $edge_vm_sizes = az vm list-sizes --location $location | ConvertFrom-Json `
        | Where-Object { $vm_sku_names -icontains $_.name } `
        | Where-Object {
            ($_.numberOfCores -ge 2) -and `
            ($_.memoryInMB -ge 8192) -and `
            ($_.osDiskSizeInMB -ge 1047552) -and `
            ($_.resourceDiskSizeInMB -gt 8192)
        } `
        | Sort-Object -Property `
            NumberOfCores,MemoryInMB,ResourceDiskSizeInMB,Name
    # Pick top
    if ($edge_vm_sizes.Count -ne 0) {
        $edge_vm_size = $edge_vm_sizes[0].Name
        Write-Host "Using $($edge_vm_size) as VM size for all edge simulation gateway hosts..."
    }
    #endregion

    #region virtual network parameters
    $vnet_name = "iiot-vnet"
    $vnet_prefix = "10.0.0.0/16"
    $sim_subnet_name = "opc"
    $sim_subnet_prefix = "10.0.0.0/24"
    $edge_subnet_name = "iotedge"
    $edge_subnet_prefix = "10.0.1.0/24"
    #endregion

    # event hubs
    $eventhubs_message_retention = 7
    
    # time series insights
    $tsi_name = "tsi-$($env_hash)"
    $tsi_sku = "L1"
    $tsi_capacity = 1
    $tsi_kind = "LongTerm"
    $tsi_timestamp_property = "SourceTimestamp"
    $tsi_id_properties = @(
        @{ "name" = "ApplicationUri"; "type" = "string" }
    )

    $username = az account show --query 'user.name' -o tsv
    $userid = az ad user show --id $username --query objectId -o tsv
    if (!$userid)
    {
        Write-Host "Unable to retrieve current user id. Contributors will have to be added manually to the TSI environment through the Azure Portal"
    }

    # edge stream analytics job
    $edge_asa_name = "asa-edge-$($env_hash)"
    $edge_asa_query = Get-Content -Path "$($root_path)/StreamAnalytics/EdgeASA/EdgeASA.asaql" -Raw
    $edge_asa_input_name = "streaminput"
    $edge_asa_telemetry_output_name = "telemetryoutput"
    $edge_asa_alerts_output_name = "alertsoutput"

    # cloud stream analytics job
    $cloud_asa_query = Get-Content -Path "$($root_path)/StreamAnalytics/CloudASA/CloudASA.asaql" -Raw

    # data explorer
    $adx_cluster_name = "adx$($env_hash)"
    if ($location.StartsWith("usdod") -or $location.StartsWith("usgov"))
    {
        $adx_cluster_sku = "Dev(No SLA)_Standard_D11_v2"
    }
    else
    {
        $adx_cluster_sku = "Dev(No SLA)_Standard_E2a_v4"
    }

    $adx_db_name = "TelemetryDB"
    $adx_principal_id = $username
    $adx_principal_type = "User"
    $adx_access_role = "Admin"

    $platform_parameters = @{
        "location" = @{ "value" = $location }
        "environmentHashId" = @{ "value" = $env_hash }
        "simVmName" = @{ "value" = $sim_vm_name }
        "simVmSize" = @{ "value" = $sim_vm_size }
        "edgeVmName" = @{ "value" = $edge_vm_name }
        "edgeVmSize" = @{ "value" = $edge_vm_size }
        "edgeVmPublishedNodesPath" = @{ "value" = $published_nodes_path }
        "adminUsername" = @{ "value" = $vm_username }
        "adminPassword" = @{ "value" = $vm_password }
        "vnetName" = @{ "value" = $vnet_name }
        "vnetAddressPrefix" = @{ "value" = $vnet_prefix }
        "simSubnetName" = @{ "value" = $sim_subnet_name}
        "simSubnetAddressRange" = @{ "value" = $sim_subnet_prefix }
        "edgeSubnetName" = @{ "value" = $edge_subnet_name }
        "edgeSubnetAddressRange" = @{ "value" = $edge_subnet_prefix }
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
        "adxClusterSku" = @{ "value" = $adx_cluster_sku }
        "adxDatabaseName" = @{ "value" = $adx_db_name }
        "adxAccessPolicyPrincipalId" = @{ "value" = $adx_principal_id }
        "adxAccessPolicyPrincipalType" = @{ "value" = $adx_principal_type }
        "adxAccessPolicyRole" = @{ "value" = $adx_access_role }
        "adxAccessPrincipalAssignmentId" = @{ "value" = (New-Guid).Guid }
        "notificationsWebhookUrl" = @{ "value" = $webhook_url }
        "alertsWebhookUrl" = @{ "value" = $webhook_url }
        "edgeASAJobName" = @{ "value" = $edge_asa_name }
        "edgeASAJobQuery" = @{ "value" = ($edge_asa_query | Out-String) }
        "edgeASAJobInputName" = @{ "value" = $edge_asa_input_name }
        "edgeASAJobOutput1Name" = @{ "value" = $edge_asa_telemetry_output_name }
        "edgeASAJobOutput2Name" = @{ "value" = $edge_asa_alerts_output_name }
        "cloudASAJobQuery" = @{ "value" = ($cloud_asa_query | Out-String) }
    }
    Set-Content -Path "$($root_path)/Templates/azuredeploy.parameters.json" -Value (ConvertTo-Json $platform_parameters -Depth 5)

    Write-Host
    Write-Host "Creating resource group deployment"
    Write-Host -ForegroundColor Yellow "IMPORTANT: In a few minutes, the notification webhook you provided will receive two validation requests. You must copy their validation URLs and open them on a browser for the deployment to be successful."
    $deployment_output = az deployment group create `
        --resource-group $resource_group `
        --name 'IndustrialIoT' `
        --mode Incremental `
        --template-file "$($root_path)/Templates/azuredeploy.json" `
        --parameters "$($root_path)/Templates/azuredeploy.parameters.json" | ConvertFrom-Json
    
    if (!$deployment_output)
    {
        throw "Something went wrong with the resource group deployment. Ending script."        
    }

    $deployment_output | Out-String
    #endregion

    #region edge deployment
    $opc_deployment_name = "opc"
    $priority = 1

    # publish edge stream analytics job
    Write-Host "`r`nPublishing edge stream analytics job "

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
    Write-Host "`r`nCreating main IoT edge device deployment"

    az iot edge deployment create `
        -d "main-deployment" `
        --hub-name $iot_hub_name `
        --content "$($root_path)/EdgeSolution/deployment.template.json" `
        --target-condition=$deployment_condition

    # Create OPC layered deployment
    Write-Host "`r`nCreating IoT edge layered deployment $opc_deployment_name-$priority"

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
            -tsi_types (Get-Content -Path "$($root_path)/TimeSeriesInsights/Model/types.json") `
            -tsi_hierarchies (Get-Content -Path "$($root_path)/TimeSeriesInsights/Model/hierarchies.json") `
            -tsi_instances (Get-Content -Path "$($root_path)/TimeSeriesInsights/Model/instances.json")
    }
    #endregion

    Write-Host ""
    Write-Host "OPC Sim & IoT Edge VM Credentials:"
    Write-Host "Username: $vm_username"
    Write-Host "Password: $vm_password"
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
    [int]$hash_length = 8
)
{
    $env_hash = (New-Guid).Guid.Replace('-', '').Substring(0, $hash_length).ToLower()

    return $env_hash
}

Function Get-ResourceGroupLocations(
    $provider,
    $typeName
)
{
    $providers = $(az provider show --namespace $provider | ConvertFrom-Json)
    $resourceType = $providers.ResourceTypes | Where-Object { $_.ResourceType -eq $typeName }

    return $resourceType.locations
}

function Publish-StreamAnalyticsEdgeJob(
    [string]$subscription_id,
    [string]$resource_group,
    [string]$location,
    [string]$job_name
)
{
    if (!$subscription_id)
    {
        $subscription_id = az account show --query id -o tsv
    }
    if (!$location)
    {
        $location = az group show -n $resource_group --query location -o tsv
    }

    $token = az account get-access-token --resource-type arm --query accessToken -o tsv
    $secure_token = ConvertTo-SecureString $token -AsPlainText -Force
    
    if ($location.StartsWith("usdod") -or $location.StartsWith("usgov"))
    {
        $base_uri = "https://management.usgovcloudapi.net"
    }
    else
    {
        $base_uri = "https://management.azure.com"
    }

    $publish_uri = "$($base_uri)/subscriptions/$($subscription_id)/resourceGroups/$($resource_group)/providers/Microsoft.StreamAnalytics/streamingjobs/$($job_name)/publishedgepackage?api-version=2017-04-01-preview"
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
    Write-Host "`r`nCreating Time Series Insights types"
    
    $tsi_id = "/subscriptions/$($subscription_id)/resourceGroups/$($resource_group)/providers/Microsoft.TimeSeriesInsights/environments/$($tsi_name)"
    $tsi_fqdn = az resource show --id $tsi_id --query 'properties.dataAccessFqdn' -o tsv
    $types_uri = "https://$($tsi_fqdn)/timeseries/types/`$batch?api-version=2020-07-31"
    
    Invoke-RestMethod $types_uri `
        -Method POST `
        -Body $tsi_types `
        -ContentType "application/json" `
        -Authentication Bearer -Token $secure_token
    #endregion

    #region hierarchies
    Write-Host "`r`nCreating Time Series Insights hierarchies"
    
    $hierarchies_uri = "https://$($tsi_fqdn)/timeseries/hierarchies/`$batch?api-version=2020-07-31"
    
    Invoke-RestMethod $hierarchies_uri `
        -Method POST `
        -Body $tsi_hierarchies `
        -ContentType "application/json" `
        -Authentication Bearer -Token $secure_token
    #endregion

    #region instances
    Write-Host "`r`nCreating Time Series Insights instances"
    
    $instances_uri = "https://$($tsi_fqdn)/timeseries/instances/`$batch?api-version=2020-07-31"
    
    Invoke-RestMethod $instances_uri `
        -Method POST `
        -Body $tsi_instances `
        -ContentType "application/json" `
        -Authentication Bearer -Token $secure_token
    #endregion
}

New-IIoTEnvironment