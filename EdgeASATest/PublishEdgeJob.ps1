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