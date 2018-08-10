#Powershell script to manage maintenance mode of objects using the vRops Suite-api
#v1.0 vMan.ch, 21.06.2016 - Initial Version

<#

    .SYNOPSIS

    This script will put objects into maintenenace mode for X minutes, until X date / time or permanently until removed

    Script requires Powershell v3 and above.

    Run the command below to store user and pass in secure credential XML for each environment

        $cred = Get-Credential
        $cred | Export-Clixml -Path "c:\vRops\config\HOME.xml"

#>

param
(
    [String]$vRopsAddress,
    [String]$creds,
    [Array]$ResourceByName,
    [String]$resourceKind,
    [String]$SetType,
    [DateTime]$EndDate,
    [int]$Duration
)

#Logging Function
Function Log([String]$message, [String]$LogType, [String]$LogFile){
    $date = Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
    $message = $date + "`t" + $LogType + "`t" + $message
    $message >> $LogFile
}

#Get Stored Credentials

$ScriptPath = (Get-Item -Path ".\" -Verbose).FullName

if($creds -gt ""){

    $cred = Import-Clixml -Path "$ScriptPath\config\$creds.xml"

    $vRopsUser = $cred.GetNetworkCredential().Username
    $vRopsPassword = $cred.GetNetworkCredential().Password
    }
    else
    {
    echo "environment not specified, stop hammer time!"
    Exit
    }

#vars
$RunDateTime = (Get-date)


If ($EndDate){
    if ($RunDateTime -gt $EndDate){
    Echo "EndDate specified occurs in the past, terminating script"
    Exit
    }
}
$RunDateTime = $RunDateTime.tostring("yyyyMMddHHmmss") 
$LogFileLoc = $ScriptPath + '\Log\Logfile.log'

#Lookup ResourceId from Name

Function GetObject([String]$vRopsObjName, [String]$resourceKindKey, [String]$vRopsServer, $User, $Password){

$vRopsObjName = $vRopsObjName -replace ' ','%20'

$wc = new-object system.net.WebClient
$wc.Credentials = new-object System.Net.NetworkCredential($User, $Password)
[xml]$Checker = $wc.DownloadString("https://$vRopsServer/suite-api/api/resources?resourceKind=$resourceKindKey&name=$vRopsObjName")

$AlertReport = @()

# Check if we get more than 1 result and apply some logic
    If ([Int]$Checker.resources.pageInfo.totalCount -gt '1') {

        $DataReceivingCount = $Checker.resources.resource.resourceStatusStates.resourceStatusState.resourceStatus -eq 'DATA_RECEIVING'

            If ($DataReceivingCount.count -gt 1){
            $CheckerOutput = ''
            return $CheckerOutput 
            }
            
            Else 
            {

            ForEach ($Result in $Checker.resources.resource){


                    $CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Result.identifier; resourceKindKey=$Result.resourceKey.resourceKindKey}

                    Return $CheckerOutput
                    
                }   
            }
 }
    else
    {
    
    $CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Checker.resources.resource.identifier; resourceKindKey=$Checker.resources.resource.resourceKey.resourceKindKey}


                    Return $CheckerOutput

    }
}

#Take all certs.
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

#Lookup Name and map to resourceId Table

$ObjectLookupTable = @()

Log -Message "Looking stuff up" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

ForEach ($ResourceName in $ResourceByName){

Log -Message "Looking up resourceID for $ResourceName" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

    #Map name to resourceId for lookup
        $resourceLookup = GetObject $ResourceName $resourceKind $vRopsAddress $vRopsUser $vRopsPassword

            If ($resourceLookup.resourceId -gt ''){

            Log -Message "Resource ID Found for $ResourceName" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

                $ObjectLookupTable += New-Object PSObject -Property @{
                resourceId = $resourceLookup.resourceId
                resourceName = $ResourceName
                resourceKindKey = $resourceLookup.resourceKindKey
                }

            }
            else {

                  Log -Message "Resource ID NOT Found for $ResourceName" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

            }


}

switch($SetType)
    {

DateTime {

if ($ObjectLookupTable.resourceId -gt ''){

$ContentType = "application/xml;charset=utf-8"
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/xml')

    [int64]$EndDateEpoc = Get-Date -Date $EndDate.ToUniversalTime() -UFormat %s
    $EndDateEpoc = $EndDateEpoc*1000 

        Log -Message "Putting all objects into Maintenance Mode until $EndDate" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

            Foreach ($member in $ObjectLookupTable){

                $ResName = $member.resourceName
                $ResID = $member.resourceId
                $ResKind = $member.resourceKindKey

                    Log -Message "Putting $ResName into Maintenance Mode " -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc
                
                    $PUTURL = "https://$vRopsAddress/suite-api/api/resources/$ResID/maintained?end=$EndDateEpoc"

                    Invoke-RestMethod -Method PUT -uri $PUTURL -Credential $cred

                    $GETURL = "https://$vRopsAddress/suite-api/api/resources/$ResID"
                    
                    [xml]$Status = Invoke-RestMethod -Method GET -uri $GETURL -Credential $cred  -ContentType $ContentType -Headers $header

                    $MMState = $Status.resource.resourceStatusStates.resourceStatusState.resourceState

                    Log -Message "State is now in $MMState" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

                        While ($MMState -ne "MAINTAINED") {
                            [xml]$Status = Invoke-RestMethod -Method GET -uri $GETURL -Credential $vRopsCreds -ContentType $ContentType -Headers $header
                            Write-host 'Checking' $ResName ' until it has been placed in Maintenance mode'
                            Sleep 3
                              } # End of block statement


            }
}

}

Minutes {

if ($ObjectLookupTable.resourceId -gt ''){

$ContentType = "application/xml;charset=utf-8"
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/xml')

        Log -Message "Putting all objects into Maintenance Mode for $Duration minutes" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

            Foreach ($member in $ObjectLookupTable){

                $ResName = $member.resourceName
                $ResID = $member.resourceId
                $ResKind = $member.resourceKindKey

                    Log -Message "Putting $ResName into Maintenance Mode " -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc
                
                    $PUTURL = "https://$vRopsAddress/suite-api/api/resources/$ResID/maintained?duration=$Duration"

                    Invoke-RestMethod -Method PUT -uri $PUTURL -Credential $cred

                    $GETURL = "https://$vRopsAddress/suite-api/api/resources/$ResID"
                    
                    [xml]$Status = Invoke-RestMethod -Method GET -uri $GETURL -Credential $cred  -ContentType $ContentType -Headers $header

                    $MMState = $Status.resource.resourceStatusStates.resourceStatusState.resourceState

                    Log -Message "State is now in $MMState" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

                        While ($MMState -ne "MAINTAINED") {
                            [xml]$Status = Invoke-RestMethod -Method GET -uri $GETURL -Credential $vRopsCreds -ContentType $ContentType -Headers $header
                            Write-host 'Checking' $ResName ' until it has been placed in Maintenance mode'
                            Sleep 3
                              } # End of block statement


            }
}

}

Enter-MM {

if ($ObjectLookupTable.resourceId -gt ''){

$ContentType = "application/xml;charset=utf-8"
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/xml')

        Log -Message "Putting all objects into Manual Maintenance Mode" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

            Foreach ($member in $ObjectLookupTable){

                $ResName = $member.resourceName
                $ResID = $member.resourceId
                $ResKind = $member.resourceKindKey

                    Log -Message "Putting $ResName into Manual Maintenance Mode" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc
                
                    $PUTURL = "https://$vRopsAddress/suite-api/api/resources/$ResID/maintained"

                    Invoke-RestMethod -Method PUT -uri $PUTURL -Credential $cred

                    $GETURL = "https://$vRopsAddress/suite-api/api/resources/$ResID"
                    
                    [xml]$Status = Invoke-RestMethod -Method GET -uri $GETURL -Credential $cred  -ContentType $ContentType -Headers $header

                    $MMState = $Status.resource.resourceStatusStates.resourceStatusState.resourceState

                    Log -Message "State is now in $MMState" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

                        While ($MMState -ne "MAINTAINED_MANUAL") {
                            [xml]$Status = Invoke-RestMethod -Method GET -uri $GETURL -Credential $vRopsCreds -ContentType $ContentType -Headers $header
                            Write-host 'Checking' $ResName ' until it has been placed in Maintenance mode'
                            Sleep 3
                              } # End of block statement


            }
}

}

Exit-MM {

if ($ObjectLookupTable.resourceId -gt ''){

$ContentType = "application/xml;charset=utf-8"
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/xml')

        Log -Message "Putting all objects into Manual Maintenance Mode" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

            Foreach ($member in $ObjectLookupTable){

                $ResName = $member.resourceName
                $ResID = $member.resourceId
                $ResKind = $member.resourceKindKey

                    Log -Message "$ResName Exiting Manual Maintenance Mode" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc
                
                    $DELURL = "https://$vRopsAddress/suite-api/api/resources/$ResID/maintained"

                    Invoke-RestMethod -Method DELETE -uri $DELURL -Credential $cred

                    $GETURL = "https://$vRopsAddress/suite-api/api/resources/$ResID"
                    
                    [xml]$Status = Invoke-RestMethod -Method GET -uri $GETURL -Credential $cred  -ContentType $ContentType -Headers $header

                    $MMState = $Status.resource.resourceStatusStates.resourceStatusState.resourceState

                    Log -Message "State is now in $MMState" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

                        While ($MMState -eq "MAINTAINED_MANUAL") {
                            [xml]$Status = Invoke-RestMethod -Method GET -uri $GETURL -Credential $vRopsCreds -ContentType $ContentType -Headers $header
                            Write-host 'Checking' $ResName ' until it has EXITED Maintenance Mode'
                            Sleep 3
                              } # End of block statement


            }
}

}


default{"Usage:


.\vRops-Maintained.ps1 -vRopsAddress 'vrops.vman.ch' -creds 'HOME' -ResourceByName 'log','RuneCast' -resourceKind 'VirtualMachine' -SetType 'DateTime' -EndDate '2017/06/20 22:00'

.\vRops-Maintained.ps1 -vRopsAddress 'vrops.vman.ch' -creds 'HOME' -ResourceByName 'log','RuneCast' -resourceKind 'VirtualMachine' -SetType 'Minutes' -Duration '5'

.\vRops-Maintained.ps1 -vRopsAddress 'vrops.vman.ch' -creds 'HOME' -ResourceByName 'log','RuneCast' -resourceKind 'VirtualMachine' -SetType 'Enter-MM'

.\vRops-Maintained.ps1 -vRopsAddress 'vrops.vman.ch' -creds 'HOME' -ResourceByName 'log','RuneCast' -resourceKind 'VirtualMachine' -SetType 'Exit-MM'


"}

}