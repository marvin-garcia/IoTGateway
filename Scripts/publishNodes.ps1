param(
    [Parameter(Mandatory)]
    [string]$serverFqdn,
    [Parameter(Mandatory)]
    [string]$serverPorts,
    [Parameter(Mandatory)]
    [string]$opcNodesPath,
    [Parameter(Mandatory)]
    [string]$publishedNodesPath
)

Set-Content -Path ./logs.txt -Value "ServerFQDN: $($serverFqdn), ServerPorts: $($serverPorts). OpcNodesPath: $($opcNodesPath). PublishNodesPath: $($publishedNodesPath)"

[Array]$serverPortList = $serverPorts.Split(',')
$opcNodes = ConvertFrom-Json -InputObject (Get-Content -Path $opcNodesPath -Raw)
$publishedNodes = @()

foreach ($port in $serverPortList)
{
    $publishedNodes += @{
        "EndpointUrl" = "opc.tcp://$($serverFqdn):$($port)/"
        "UseSecurity" = $false
        "OpcNodes" = $opcNodes.OpcNodes
    }
}

$filePath = Split-Path $publishedNodesPath -ErrorAction Stop
if (!(Test-Path -Path $filePath -ErrorAction Stop))
{
    New-Item -Path $filePath -ItemType directory -ErrorAction Stop
}
Set-Content -Path $publishedNodesPath -Value (ConvertTo-Json -InputObject $publishedNodes -Depth 5 -ErrorAction Stop) -ErrorAction Stop