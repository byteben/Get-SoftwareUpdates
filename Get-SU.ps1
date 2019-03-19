<#
Get-SU.ps1
Get Required Software Updates for members of a collection and write to Host the results.
#######
Author: Ben Whitmore
Website: byteben.com
Disclaimer: I do not accept any liability this code may have in your Environment. Always test your scripts before using them in a Production Environment.
#######
Example: Get-SU.ps1 -SitServer PSS1 -SiteCode PS1 -Collection SU_Test
#######

Version 1.0 (30/12/18)
Original Script
-------
Version 1.1 (1/1/2019)
Used Array to store EvaluationStateStatus String in $SoftwareUpdates_Append Object instead of calling an If statement for each option - Thanks @GuyrLeech
-------
#>

#Set Parameters for Connection
Param (
	[Parameter(Mandatory = $True)]
	[string]$SiteServer = 'PSS1',
	[Parameter(Mandatory = $True)]
	[string]$SiteCode = 'PS1',
	[Parameter(Mandatory = $True)]
	[string]$Collection = 'SU_Test'
)
#Attempt Connection to Site Server and get Clients from Collection
#Gets the Collection ID and Stores in a Variable, stores the collection ID in a variable, and then performs a WMI Query using the Collection ID
Try
{
	$ErrorActionPreference = "Stop"
	$CollectionResult = Get-WmiObject -ComputerName $SiteServer -Namespace ROOT\SMS\Site_$SiteCode -Class SMS_Collection -Filter "Name = '$Collection'"
	$UpdateCollectionID = $CollectionResult.CollectionID
	$CollectionMembers = Get-WmiObject -ComputerName $SiteServer -NameSpace ROOT\SMS\SITE_$SiteCode -Class SMS_CollectionMember_A -Filter "CollectionID = '$UpdateCollectionID'"
}
#If Connection to Site Server fails, or an invalid Collection is specified Write-Host
Catch
{
	Write-Host 'Error Caught Connecting to Site Server. Please retry and check the values for:-' -ForegroundColor Magenta
	Write-Host 'SiteServer: ' -ForegroundColor Blue -NoNewLine; $SiteServer
	Write-Host 'SiteCode: ' -ForegroundColor Blue -NoNewLine; $SiteCode
	Write-Host 'Collection: ' -ForegroundColor Blue -NoNewLine; $Collection
}

#If connection to Site Server is successful and a valid Collection specified add collection members to $Members Object 
#Retrieves lists of devices using CollectionMembers.Name 

$Members = $CollectionMembers.Name
Write-Host "`n---------------------------------------------------------" -ForegroundColor Green
Write-Host "Attempting Connection to "$Members.Count"Clients in Collection "$Collection":" -ForegroundColor Green
Write-Host "---------------------------------------------------------" -ForegroundColor Green
$Members

#Create Catch Fail Array
$RPCFailArray = @()

#Connect to Clients in $Members Object
#For each Client in $Members object, connect to the CCM namespace and query Software Updates that are out of compliance
$SoftwareUpdates = ForEach ($Client in $Members)
{
	Try
	{
		Get-WmiObject -ComputerName $Client -Namespace "root\ccm\clientSDK" -Class CCM_SoftwareUpdate | Where-Object { $_.ComplianceState -eq "0" } | Select @{ Name = 'Client'; Expression = { $Client } }, Name, ComplianceState, EvaluationState, Deadline, URL -ErrorAction Stop
	}
	Catch
	{
		#If WMI connection fails, add the Client and Exception thrown into an array
		$RPCFailArray += New-object  PSObject -Property ([ordered]@{ Client = $Client; Exception = $_.Exception.Message })
	}
	
}

#If $RPCFailArray is not empty, Write-Host any failures to connect to Clients
If (@($RPCFailArray).Count -ne 0)
{
	$Format_RPCFailArray =
	@{ Name = 'Client'; Expression = { $_.Client } },
	@{ Name = 'Exception'; Expression = { $_.Exception } }
	$Format_RPCFailArrayResult = $RPCFailArray | Format-Table $Format_RPCFailArray -AutoSize | Out-String
	Write-Host "`n---------------------------------------------------------" -ForegroundColor Red
	Write-Host "Couldn't connect to"@($RPCFailArray).Count "Clients:" -ForegroundColor Red
	Write-Host "---------------------------------------------------------" -ForegroundColor Red
	Write-Host $Format_RPCFailArrayResult
}
#Create new Array to Append Evaluation State Status (Integer to String)
<# https://docs.microsoft.com/en-us/sccm/develop/reference/core/clients/sdk/ccm_softwareupdate-client-wmi-class
The EvaluationState property is only meant to evaluate progress, not to find the compliance state of a software update. When a software update is not in a progress state, the value of EvaluationState is none or available, depending on whether there was any progress at any point in the past. This is not related to compliance state. Also, if a software update was downloaded at activation time, the value of EvaluationState is none. This value only changes once an install is attempted on the software update.
#>
$SoftwareUpdates_Append = $SoftwareUpdates | Select *

#Create Array for EvaluationStateStatus
$EvaluationStateStatus = @('None', 'Available', 'Submitted', 'Detecting', 'PreDownload', 'Downloading', 'WaitInstall', 'Installing', 'PendingSoftReboot', 'PendingHardReboot', 'WaitReboot', 'Verifying', 'InstallComplete', 'Error', 'WaitServiceWindow')

$SoftwareUpdates_Append | ForEach-Object {
	
	If ($_.EvaluationState -ne $Null)
	{
		$_ | Add-Member -MemberType NoteProperty -Name 'EvaluationStateStatus' -Value $EvaluationStateStatus[$_.EvaluationState]
	}
	
}

#Formats Array for Output and display updates, per Client, that are out of compliance
$Format_SoftwareUpdatesArray =
@{ Name = 'Client'; Expression = { $_.Client }; Alignment = "Left" },
@{ Name = 'Name'; Expression = { $_.Name }; Alignment = "Left" },
@{ Name = 'ComplianceState'; Expression = { $_.ComplianceState }; Alignment = "Left" },
@{ Name = 'EvaluationState'; Expression = { $_.EvaluationState }; Alignment = "Left" },
@{ Name = 'EvaluationStateStatus'; Expression = { $_.EvaluationStateStatus }; Alignment = "Left" },
@{ Name = 'Deadline (en-GB)'; Expression = { $Date = $_.Deadline -replace ".{11}$"; $Date = [datetime]::parseexact($Date, 'yyyyMMddhhmmss', $null); $Date.ToString('dd/MM/yyyy hh:mm:ss') }; Alignment = "Left" },
@{ Name = 'URL'; Expression = { $_.URL }; Alignment = "Left" }
$Format_SoftwareUpdatesArrayResult = $SoftwareUpdates_Append | Format-Table $Format_SoftwareUpdatesArray -AutoSize | Out-String

Write-Host "`n---------------------------------------------------------" -ForegroundColor Green
Write-Host "Listing Non Compliant Updates for"($Members.Count - $RPCFailArray.Count)"/"$Members.Count"Clients:" -ForegroundColor Green
Write-Host "---------------------------------------------------------" -ForegroundColor Green
Write-Host $Format_SoftwareUpdatesArrayResult
