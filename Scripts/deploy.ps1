function New-IIoTEnvironment(
    [string]$location = "eastus",
    [string]$resource_group = "IIoTRG",
    [string]$iot_hub_name = "iiot-hub",
    [string]$iot_hub_sku = "S1",
    #[string]$opc_vm_size = "Standard_D2s_v3",
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

    #region create Windows VM (OPC simulator)
    # $opc_vm_name = "opc-sim-vm"
    # $opc_vm_password = [System.Web.Security.Membership]::GeneratePassword($password_length, $password_non_alpha_chars)

    # az vm create `
    #     --resource-group $resource_group `
    #     --name $opc_vm_name `
    #     --image win2016datacenter `
    #     --size $opc_vm_size `
    #     --admin-username azureuser `
    #     --admin-password $opc_vm_password

    # # Open ports
    # # RDP
    # az vm open-port `
    # --resource-group $resource_group `
    # --name $opc_vm_name `
    # --port 3389

    # # OPC
    # az vm open-port `
    # --resource-group $resource_group `
    # --name $opc_vm_name `
    # --port 53530

    # # Use CustomScript extension to install IIS.
    # az vm extension set `
    # --resource-group $resource_group `
    # --vm-name $opc_vm_name `
    # --publisher Microsoft.Compute `
    # --version 1.8 `
    # --name CustomScriptExtension `
    # --settings '{"fileUris": "", "commandToExecute":"powershell.exe Install-WindowsFeature -Name Web-Server"}'
    #endregion

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
    
    # Create OPC layered deployment
    $deployment_name = "opc"
    $deployment_condition = "tags.environment='dev'"
    az iot edge deployment create --layered -d $deployment_name --hub-name $iot_hub_name --content ../EdgeSolution/modules/OPC/Plc/layered.deployment.json --target-condition=$deployment_condition

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