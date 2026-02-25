# Script: zabbix_vbr_job
# Author: Felipe Galeti e Nathan Schiavon
# Description: Query Veeam job information - 100% XML Cache Mode
# Updated for Veeam v13 & PowerShell 7

$pathxml = 'C:\Program Files\Zabbix Agent\scripts\TempXmlVeeam'
$days = '-31'

$ITEM = [string]$args[0]
$ID   = [string]$args[1]
$ID0  = [string]$args[2]

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# --- TRADUÇÃO DE STATUS ---
function VeeamStatusReplace {
    Param ([Parameter(ValueFromPipeline = $true)]$item)
    process {
        $status = "$item".Trim()
        if ([string]::IsNullOrWhiteSpace($status)) { return "4" }
        switch -regex ($status) {
            "(?i)Failed"             { "0" }
            "(?i)Warning"            { "1" }
            "(?i)Success|None"       { "2" }
            "(?i)idle"               { "3" }
            "(?i)InProgress|Working" { "5" }
            "(?i)Pending"            { "6" }
            "(?i)Pausing"            { "7" }
            "(?i)Postprocessing"     { "8" }
            "(?i)Resuming"           { "9" }
            "(?i)Starting"           { "10" }
            "(?i)Stopped"            { "11" }
            "(?i)Stopping"           { "12" }
            "(?i)Waiting"            { "13" }
            default                  { "4" }
        }
    }
}

# --- FUNÇÃO EXPORTAÇÃO XML ---
function ExportXml {
    Param ([string]$switch, [string]$name, [string]$command, [string]$type, [string]$options)
    PROCESS {
        $path = "$pathxml\$name" + "temp.xml"; $newpath = "$pathxml\$name" + ".xml"
        try {
            if ($switch -eq "normal") {
                [System.DateTime]$Date = (Get-Date).AddDays([int]$days)
                $data = Invoke-Expression "$command -WarningAction SilentlyContinue"
                if ($options -eq "true") { $data = $data | Where-Object { $_.CreationTimeUTC -ge $Date } }
                $data | Export-Clixml $path -Depth 3
            }
            if ($switch -eq "byvm") {
                $rawJobs = Invoke-Expression "$command -WarningAction SilentlyContinue"
                $data = $rawJobs | Where-Object { $_.JobType -eq $type } | ForEach-Object {
                    $JobName = $_.Name
                    $_ | Get-VBRJobObject | Where-Object { $_.Object.Type -eq "VM" } | 
                    Select-Object @{ L = "Job"; E = { $JobName } }, Name
                }
                $data | Export-Clixml $path -Depth 3
            }
            if ($switch -eq "bytaskswithretry") {
                 $StartDate = (Get-Date).AddDays([int]$days)
                 $BackupSessions = Get-VBRBackupSession | Where-Object { $_.CreationTimeUTC -ge $StartDate }
                 $Result = foreach ($BS in ($BackupSessions | Where-Object { $_.IsRetryMode -eq $false })) {
                        [System.Collections.ArrayList]$TaskSessions = @($BS | Get-VBRTaskSession)
                        if ($BS.Result -eq "Failed") {
                            $RetrySessions = $BackupSessions | Where-Object { ($_.IsRetryMode -eq $true) -and ($_.OriginalSessionId -eq $BS.Id) }
                            foreach ($RS in $RetrySessions) {
                                foreach ($RT in ($RS | Get-VBRTaskSession)) {
                                    $Prior = $TaskSessions | Where-Object { $_.Name -eq $RT.Name }
                                    if ($Prior) { $TaskSessions.Remove($Prior) }
                                    $TaskSessions.Add($RT) | Out-Null
                                }
                            }
                        }
                        $TaskSessions | Select-Object @{N="JobName";E={$BS.JobName}}, @{N="JobId";E={$BS.JobId}}, 
                        @{N="JobResult";E={[string]$_.JobSess.Result}}, @{N="JobStart";E={$_.JobSess.CreationTimeUTC}}, name, status
                 }
                 $Result | Export-Clixml $path -Depth 3
            }
            if ($switch -eq "repos") {
                $repos = Get-VBRBackupRepository
                $repoExport = foreach ($r in $repos) {
                    try {
                        $cont = $r.GetContainer()
                        # Correção: Forçando o valor para long (64-bit integer) para evitar strings formatadas
                        $freeVal = if ($cont.CachedFreeSpace.Value -ne $null) { $cont.CachedFreeSpace.Value } else { $cont.CachedFreeSpace }
                        $totalVal = if ($cont.CachedTotalSpace.Value -ne $null) { $cont.CachedTotalSpace.Value } else { $cont.CachedTotalSpace }
                        
                        [PSCustomObject]@{
                            Name       = $r.Name
                            FreeSpace  = [int64]$freeVal
                            TotalSpace = [int64]$totalVal
                        }
                    } catch {}
                }
                $repoExport | Export-Clixml $path -Depth 2
            }
            if (Test-Path $path) { Move-Item -Path $path -Destination $newpath -Force }
        } catch { Write-Error "Erro XML $name : $_" }
    }
}

function ImportXml { Param ($item) $path = "$pathxml\$item.xml"; if (!(Test-Path $path)) { return $null }; try { Import-Clixml $path } catch { $null } }

function ConvertTo-ZabbixDiscoveryJson {
    param ($InputObject, [String[]]$Property)
    $out = foreach ($obj in $InputObject) {
        if ($obj) {
            $Element = @{ }; foreach ($P in $Property) { $Element["{#$($P.ToUpper())}"] = [String]$obj.$P }
            $Element["{#IFALIAS}"] = "ignore"; $Element["{#FSLABEL}"] = "ignore"; $Element
        }
    }
    @{ 'data' = $out } | ConvertTo-Json -Compress
}

# --- SWITCH PRINCIPAL ---
switch ($ITEM) {
    "DiscoveryBackupJobs" {
        $xml = ImportXml -item backupjob
        $xml | Where-Object { $_.JobType -match "Backup|EpAgentBackup|EpAgentPolicy" } | 
        Select-Object @{N="JOBID";E={$_.ID}}, @{N="JOBNAME";E={$_.NAME}} | ConvertTo-ZabbixDiscoveryJson -Property JOBNAME, JOBID
    }
    "DiscoveryBackupSyncJobs" {
        $xml = ImportXml -item backupjob
        $xml | Where-Object { $_.IsScheduleEnabled -eq "true" -and $_.JobType -eq "BackupSync" } | 
        Select-Object @{N="JOBBSID";E={$_.ID}}, @{N="JOBBSNAME";E={$_.NAME}} | ConvertTo-ZabbixDiscoveryJson -Property JOBBSNAME, JOBBSID
    }
    "DiscoveryTapeJobs" {
        $xml = ImportXml -item backuptape
        $xml | Select-Object @{N="JOBTAPEID";E={$_.ID}}, @{N="JOBTAPENAME";E={$_.NAME}} | ConvertTo-ZabbixDiscoveryJson -Property JOBTAPENAME, JOBTAPEID
    }
    "DiscoveryEndpointJobs" {
        $xml = ImportXml -item backupendpoint
        $xml | Select-Object @{N="JOBENDPOINTID";E={$_.ID}}, @{N="JOBENDPOINTNAME";E={$_.NAME}} | ConvertTo-ZabbixDiscoveryJson -Property JOBENDPOINTNAME, JOBENDPOINTID
    }
    "DiscoveryAgentJobs" {
        $xml = ImportXml -item backupendpoint
        $xml | Select-Object @{N="JOBAGENTID";E={$_.ID}}, @{N="JOBAGENTNAME";E={$_.NAME}} | ConvertTo-ZabbixDiscoveryJson -Property JOBAGENTNAME, JOBAGENTID
    }
    "DiscoveryReplicaJobs" {
        $xml = ImportXml -item backupjob
        $xml | Where-Object { $_.IsScheduleEnabled -eq "true" -and $_.JobType -eq "Replica" } | 
        Select-Object @{N="JOBREPLICAID";E={$_.ID}}, @{N="JOBREPLICANAME";E={$_.NAME}} | ConvertTo-ZabbixDiscoveryJson -Property JOBREPLICANAME, JOBREPLICAID
    }
    "DiscoveryRepo" {
        $xml = ImportXml -item backuprepo
        $xml | Select-Object @{N="REPONAME";E={$_.Name}} | ConvertTo-ZabbixDiscoveryJson -Property REPONAME
    }
    "DiscoveryBackupVmsByJobs" {
        $file = if ($ID -like "BackupSync") { "backupsyncvmbyjob" } else { "backupvmbyjob" }
        $xml = ImportXml -item $file
        $xml | Select-Object @{N="JOBNAME";E={$_.Job}}, @{N="JOBVMNAME";E={$_.NAME}} | ConvertTo-ZabbixDiscoveryJson -Property JOBVMNAME, JOBNAME
    }
    "ExportXml" {
        if (!(Test-Path $pathxml)) { New-Item -ItemType Directory -Path $pathxml -Force | Out-Null }
        if (-not (Get-Module Veeam.Backup.PowerShell)) { Import-Module Veeam.Backup.PowerShell -DisableNameChecking | Out-Null }
        if (-not (Get-VBRServerSession)) { Connect-VBRServer -Server "localhost" | Out-Null }
        ExportXml -command "Get-VBRBackupSession" -name backupsession -switch normal -options true
        ExportXml -command "Get-VBRJob" -name backupjob -switch normal
        ExportXml -command "Get-VBRTapeJob" -name backuptape -switch normal
        ExportXml -command "Get-VBRComputerBackupJob" -name backupendpoint -switch normal
        ExportXml -command "Get-VBRJob" -name backupvmbyjob -switch byvm -type Backup
        ExportXml -command "Get-VBRJob" -name backupsyncvmbyjob -switch byvm -type BackupSync
        ExportXml -name backuptaskswithretry -switch bytaskswithretry
        ExportXml -name backuprepo -switch repos
        Write-Output "1"
    }
    "ResultBackup" {
        $xml = ImportXml -item backuptaskswithretry
        $res = $xml | Where-Object { $_.jobId -eq $ID -or $_.JobName -eq $ID } | Sort-Object JobStart -Descending | Select-Object -First 1
        if (!$res) { "4" } else { ([string]$res.JobResult) | VeeamStatusReplace }
    }
    "VmResultBackup" {
        $xml = ImportXml -item backuptaskswithretry
        $res = $xml | Where-Object { $_.Name -eq $ID -and $_.JobName -eq $ID0 } | Sort-Object JobStart -Descending | Select-Object -First 1
        if (!$res) { "4" } else { ([string]$res.Status) | VeeamStatusReplace }
    }
    "ResultReplica" {
        $xml = ImportXml -item backupsession
        $res = $xml | Where-Object { $_.jobId -eq $ID -or $_.JobName -eq $ID } | Sort-Object CreationTimeUTC -Descending | Select-Object -First 1
        if (!$res) { "4" } else { ([string]$res.Result) | VeeamStatusReplace }
    }
    "RunStatus" {
        $xml = ImportXml -item backupjob
        if (($xml | Where-Object { $_.Id -eq $ID -or $_.Name -eq $ID }).IsRunning) { "1" } else { "0" }
    }
    "LastRunTime" {
        $xml = ImportXml -item backupsession
        $res = $xml | Where-Object { $_.JobId -eq $ID -or $_.JobName -eq $ID } | Sort-Object CreationTimeUTC -Descending | Select-Object -First 1
        if ($res) { [int64](New-TimeSpan -Start (Get-Date "01/01/1970") -End $res.CreationTimeUTC).TotalSeconds } else { "0" }
    }
    "JobsCount" { $xml = ImportXml -item backupjob; [string]($xml | Measure-Object).Count }
    "RepoFree" { 
        $xml = ImportXml -item backuprepo
        $repo = $xml | Where-Object { $_.Name -eq $ID }
        if ($repo.FreeSpace -ne $null) { Write-Output $repo.FreeSpace } else { Write-Output 0 } 
    }
    "RepoCapacity" { 
        $xml = ImportXml -item backuprepo
        $repo = $xml | Where-Object { $_.Name -eq $ID }
        if ($repo.TotalSpace -ne $null) { Write-Output $repo.TotalSpace } else { Write-Output 0 } 
    }
    default { write-output "4" }
}