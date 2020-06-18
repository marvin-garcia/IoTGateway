<#
    IMPORTANT!

    If a Personal Access Token (PAT) is passed among the script parameters (not recommended),
    it will be used to authenticate with the DevOps site. The token must have
    at least read&create permissions for variable groups.

    If a PAT is not provided (recommended), the script will authenticate using the OAuth access token,
    in order to be successful, two things need to be configured:
    1- The agent phase must have the option 'Allow scripts to access the OAuth token' enabled.
    2- The variable group must grant the Administrator role to the user
    'Project Collection Build Service (xxxx)', where xxxx is the project name. You can change
    the role by going to Security under the variable group you want to edit.

    More info at https://stackoverflow.com/questions/52986076/having-no-permission-for-updating-variable-group-via-azure-devops-rest-api-from
#>

Param(
    [string]$PAToken = $null,
    [string]$VariableGroupName,
    [string]$VariableName,
    [bool]$VariableIsSecret = $false,
    [string]$VariableValue)

#region Request authentication header
if (!!$PAToken)
{
    # Base64-encodes the Personal Access Token (PAT) appropriately
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f "", $PAToken)))
    $headers = @{ Authorization=("Basic {0}" -f $base64AuthInfo) }
}
else
{
    $headers = @{ Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN" } 
}
#endregion

#region Get variable group
$getVarGroupsUrl = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$env:SYSTEM_TEAMPROJECTID/_apis/distributedtask/variablegroups?api-version=5.1-preview.1"
Write-Host "URL: $getVarGroupsUrl"

$response = Invoke-RestMethod -Uri $getVarGroupsUrl -Method Get -Headers $headers
$variableGroups = $response.value
Write-Host "Available variable groups: $($variableGroups.name -Join ', ')"

$variableGroup = $variableGroups | ? { $_.name -eq $VariableGroupName }
if (!$variableGroup)
{
    throw "Unable to get variable group $VariableGroupName"
}
Write-Host "variable group: $($variableGroup.name | Out-String)"
#endregion

# Edit variable
$variableGroup.variables.$VariableName.value = $VariableValue
if ($VariableIsSecret) { $variableGroup.variables.$VariableName.isSecret = $true }
$json = ConvertTo-Json -InputObject $variableGroup -Depth 10

$editVariableUrl = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$env:SYSTEM_TEAMPROJECTID/_apis/distributedtask/variablegroups/$($variableGroup.id)?api-version=5.1-preview.1"
Write-Host "URL: $editVariableUrl"

$response = Invoke-RestMethod -Uri $editVariableUrl -Method Put -Body $json -ContentType "application/json" -Headers $headers
#$response
#Write-Host "New Variable Value: $($pipeline.variables.$VariableName.value)"
