# Script: zabbix_vbr_job
# Author: Felipe Galeti e Nathan Schiavon
# Description: Query Veeam job information - Full XML Mode
# Updated for Veeam v12/v13 & PowerShell 7

$pathxml = 'C:\Program Files\Zabbix Agent\scripts\TempXmlVeeam'
$days = '-31'

$ITEM = [string]$args[0]
$ID = [string]$args[1]
$ID0 = [string]$args[2]


$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

if ($ITEM -eq "ExportXml") {
    try {
        if (-not (Get-Module -Name Veeam.Backup.PowerShell)) {
            Import-Module Veeam.Backup.PowerShell -DisableNameChecking | Out-Null
        }
        Disconnect-VBRServer -Confirm:$false -ErrorAction SilentlyContinue 
        Connect-VBRServer -Server "localhost" -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Output "ERRO: $_"
        exit
    }
}
# ----------------------------------------

# Function ExportXml (MODO SÍNCRONO)
function ExportXml
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)][string]$switch,
        [Parameter(Mandatory = $true)][string]$name,
        [Parameter(Mandatory = $false)][string]$command,
        [Parameter(Mandatory = $false)][string]$type,
        [Parameter(Mandatory = $false)][string]$options
    )
    
    PROCESS
    {
        $path = "$pathxml\$name" + "temp.xml"
        $newpath = "$pathxml\$name" + ".xml"
        
        try {
            # EXPORTAÇÃO PADRÃO (JOBS, SESSIONS, TAPES)
            if ($switch -like "normal")
            {
                [System.DateTime]$Date = (Get-Date).adddays($days)
                $data = Invoke-Expression "$command -WarningAction SilentlyContinue"
                if ($options -like "true") {
                    $data = $data | Where-Object { $_.CreationTime -ge $Date }
                }
                $data | Export-Clixml $path -Depth 2
            }
            
            # EXPORTAÇÃO VMS
            if ($switch -like "byvm")
            {
                $rawJobs = Invoke-Expression "$command -WarningAction SilentlyContinue"
                $data = $rawJobs | Where-Object { $_.JobType -eq $type } | ForEach-Object {
                    $JobName = $_.Name
                    $_ | Get-VBRJobObject -WarningAction SilentlyContinue | Where-Object { $_.Object.Type -eq "VM" } | Select-Object @{ L = "Job"; E = { $JobName } }, Name | Sort-Object -Property Job, Name
                }
                $data | Export-Clixml $path -Depth 2
            }
            
            # EXPORTAÇÃO RETRYS
            if ($switch -like "bytaskswithretry")
            {
                 $StartDate = (Get-Date).adddays($command)
                 $BackupSessions = [Veeam.Backup.Core.CBackupSession]::GetAll() | Where-Object { $_.CreationTime -ge $StartDate } | Sort-Object JobName, CreationTime
                 $Result = & {
                    ForEach ($BackupSession in ($BackupSessions | Where-Object { $_.IsRetryMode -eq $false }))
                    {
                        [System.Collections.ArrayList]$TaskSessions = @($BackupSession | Get-VBRTaskSession)
                        If ($BackupSession.Result -eq "Failed")
                        {
                            $RetrySessions = $BackupSessions | Where-Object { ($_.IsRetryMode -eq $true) -and ($_.OriginalSessionId -eq $BackupSession.Id) }
                            ForEach ($RetrySession in $RetrySessions)
                            {
                                [System.Collections.ArrayList]$RetryTaskSessions = @($RetrySession | Get-VBRTaskSession)
                                ForEach ($RetryTaskSession in $RetryTaskSessions)
                                {
                                    $PriorTaskSession = $TaskSessions | Where-Object { $_.Name -eq $RetryTaskSession.Name }
                                    If ($PriorTaskSession) { $TaskSessions.Remove($PriorTaskSession) }
                                    $TaskSessions.Add($RetryTaskSession) | Out-Null
                                }
                            }
                        }
                        $TaskSessions | Select-Object @{ N = "JobName"; E = { $BackupSession.JobName } }, @{ N = "JobId"; E = { $BackupSession.JobId } }, @{ N = "SessionName"; E = { $_.JobSess.Name } }, @{ N = "JobResult"; E = { $_.JobSess.Result } }, @{ N = "JobStart"; E = { $_.JobSess.CreationTime } }, @{ N = "JobEnd"; E = { $_.JobSess.EndTime } }, @{ N = "Date"; E = { $_.JobSess.CreationTime.ToString("yyyy-MM-dd") } }, name, status
                    }
                }
                $Result | Export-Clixml $path -Depth 2
            }

            # --- EXPORTAÇÃO DE REPOSITÓRIOS (CORREÇÃO DE TIMEOUT) ---
            if ($switch -like "repos") {
                $repos = Get-VBRBackupRepository -WarningAction SilentlyContinue
                $repoExport = @()
                foreach ($r in $repos) {
                    try {
                        $cont = $r.GetContainer()
                        $free = $cont.CachedFreeSpace
                        if ($free.Value) { $free = $free.Value }
                        elseif ($free -match "\(([\d]+)\)") { $free = $matches[1] }
                        
                        $total = $cont.CachedTotalSpace
                        if ($total.Value) { $total = $total.Value }
                        elseif ($total -match "\(([\d]+)\)") { $total = $matches[1] }

                        $repoExport += [PSCustomObject]@{
                            Name = $r.Name
                            FreeSpace = $free
                            TotalSpace = $total
                        }
                    } catch {}
                }
                $repoExport | Export-Clixml $path -Depth 2
            }
            # -------------------------------------------------------------
            
            if (Test-Path $path) {
                Copy-Item -Path $path -Destination $newpath -Force
                Remove-Item $path -Force
            }
        } catch {
            Write-Error "Erro ao exportar XML $name : $_"
        }
    }
}

# Function import xml
function ImportXml
{
    [CmdletBinding()]
    Param ([Parameter(ValueFromPipeline = $true)]$item)
    
    $path = "$pathxml\$item" + ".xml"
    if (!(Test-Path -Path $path)) { return $null }
    
    try {
        $xmlquery = Import-Clixml "$path" -ErrorAction Stop
        return $xmlquery
    }
    catch { return $null }
}

# Replace Function for Veeam Correlation
function VeeamStatusReplace
{
    [CmdletBinding()]
    Param ([Parameter(ValueFromPipeline = $true)]$item)
    $item.replace('Failed', '0').replace('Warning', '1').replace('Success', '2').replace('None', '2').replace('idle', '3').replace('InProgress', '5').replace('Pending', '6').replace('Pausing', '7').replace('Postprocessing', '8').replace('Resuming', '9').replace('Starting', '10').replace('Stopped', '11').replace('Stopping', '12').replace('WaitingRepository', '13').replace('WaitingTape', '13').replace('Working', '13')
}

# Function Sort-Object VMs by jobs on last backup
function veeam-backuptask-unique
{
    [CmdletBinding()]
    Param ([Parameter(Mandatory = $true)]$jobtype, [Parameter(Mandatory = $true)]$ID)
    $xml1 = ImportXml -item backuptaskswithretry | Where-Object { $_.$jobtype -like "$ID" }
    $unique = $xml1.Name | Sort-Object -Unique
    
    $output = & {
        foreach ($object in $unique)
        {
            $query = $xml1 | Where-Object { $_.Name -like $object } | Sort-Object JobStart -Descending | Select-Object -First 1
            foreach ($object1 in $query)
            {
                $query | Select-Object @{ N = "JobName"; E = { $object1.JobName } }, @{ N = "JobId"; E = { $object1.JobId } }, @{ N = "SessionName"; E = { $object1.SessionName } }, @{ N = "JobResult"; E = { $object1.JobResult } }, @{ N = "JobStart"; E = { $object1.JobStart } }, @{ N = "JobEnd"; E = { $object1.JobEnd } }, @{ N = "Date"; E = { $object1.Date.ToString("yyyy-MM-dd") } }, @{ N = "Name"; E = { $object1.Name } }, @{ N = "Status"; E = { $object1.Status } }
            }
        }
    }
    $output
}
function ConvertTo-ZabbixDiscoveryJson
{
    [CmdletBinding()]
    param ([Parameter(ValueFromPipeline = $true)]$InputObject, [Parameter(Position = 0)][String[]]$Property = @("ID", "NAME", "JOBTYPE"))
    begin { $out = @() }
    process {
        if ($InputObject) {
            $InputObject | ForEach-Object {
                if ($_) {
                    $Element = @{ }
                    # Cria as tags solicitadas (ex: {#JOBNAME})
                    foreach ($P in $Property) { $Element["{#$($P.ToUpper())}"] = [String]$_.$P }
                    
                    # --- FIX: FORÇA AS TAGS PARA EVITAR ERRO NO ZABBIX ---
                    $Element["{#IFALIAS}"] = "ignore"
                    $Element["{#FSLABEL}"] = "ignore"
                    # -----------------------------------------------------

                    $out += $Element
                }
            }
        }
    }
    end { @{ 'data' = $out } | ConvertTo-Json -Compress }
}

            

switch ($ITEM)
{
    "DiscoveryBackupJobs" {
        $xml1 = ImportXml -item backupjob
        $query = $xml1 | Where-Object { ($_.JobType -like "Backup" -or $_.JobType -like "EpAgentBackup" -or $_.JobType -like "EpAgentPolicy") } | Select-Object @{ N = "JOBID"; E = { $_.ID } }, @{ N = "JOBNAME"; E = { $_.NAME } }
        $query | ConvertTo-ZabbixDiscoveryJson JOBNAME, JOBID
    }
    
    "DiscoveryBackupSyncJobs" {
        $xml1 = ImportXml -item backupjob
        $query = $xml1 | Where-Object { $_.IsScheduleEnabled -eq "true" -and $_.JobType -like "BackupSync" } | Select-Object @{ N = "JOBBSID"; E = { $_.ID } }, @{ N = "JOBBSNAME"; E = { $_.NAME } }
        $query | ConvertTo-ZabbixDiscoveryJson JOBBSNAME, JOBBSID
    }
    
    "DiscoveryTapeJobs" {
        $xml1 = ImportXml -item backuptape
        $query = $xml1 | Select-Object @{ N = "JOBTAPEID"; E = { $_.ID } }, @{ N = "JOBTAPENAME"; E = { $_.NAME } }
        $query | ConvertTo-ZabbixDiscoveryJson JOBTAPENAME, JOBTAPEID
    }
    
    "DiscoveryEndpointJobs" {
        $xml1 = ImportXml -item backupendpoint
        $query = $xml1 | Select-Object Id, Name | Select-Object @{ N = "JOBENDPOINTID"; E = { $_.ID } }, @{ N = "JOBENDPOINTNAME"; E = { $_.NAME } }
        $query | ConvertTo-ZabbixDiscoveryJson JOBENDPOINTNAME, JOBENDPOINTID
    }

    "DiscoveryAgentJobs" {
        $xml1 = ImportXml -item backupendpoint
        $query = $xml1 | Select-Object Id, Name | Select-Object @{ N = "JOBAGENTID"; E = { $_.ID } }, @{ N = "JOBAGENTNAME"; E = { $_.NAME } }
        $query | ConvertTo-ZabbixDiscoveryJson JOBAGENTNAME, JOBAGENTID
    }
    
    "DiscoveryReplicaJobs" {
        $xml1 = ImportXml -item backupjob
        $query = $xml1 | Where-Object { $_.IsScheduleEnabled -eq "true" -and $_.JobType -like "Replica" } | Select-Object @{ N = "JOBREPLICAID"; E = { $_.ID } }, @{ N = "JOBREPLICANAME"; E = { $_.NAME } }
        $query | ConvertTo-ZabbixDiscoveryJson JOBREPLICANAME, JOBREPLICAID
    }
    
    "DiscoveryRepo" {
        # Lê somente o nome do repositório para o Discovery
        $query = Get-VBRBackupRepository -WarningAction SilentlyContinue | Select-Object @{ N = "REPONAME"; E = { $_.Name }}
        $query | ConvertTo-ZabbixDiscoveryJson REPONAME
    }
    
    "DiscoveryBackupVmsByJobs" {
        if ($ID -like "BackupSync") {
            ImportXml -item backupsyncvmbyjob | Select-Object @{ N = "JOBNAME"; E = { $_.Job } }, @{ N = "JOBVMNAME"; E = { $_.NAME } } | ConvertTo-ZabbixDiscoveryJson JOBVMNAME, JOBNAME
        } else {
            ImportXml -item backupvmbyjob | Select-Object @{ N = "JOBNAME"; E = { $_.Job } }, @{ N = "JOBVMNAME"; E = { $_.NAME } } | ConvertTo-ZabbixDiscoveryJson JOBVMNAME, JOBNAME
        }
    }
    
    "ExportXml" {
        $test = Test-Path -Path "$pathxml"
        if ($test -like "False") { $query = New-Item -ItemType Directory -Force -Path "$pathxml" }
        
        
        ExportXml -command "Get-VBRBackupSession" -name backupsession -switch normal -options true
        ExportXml -command "Get-VBRJob" -name backupjob -switch normal
        ExportXml -command "Get-VBRTapeJob" -name backuptape -switch normal
        ExportXml -command "Get-VBRComputerBackupJob" -name backupendpoint -switch normal
        ExportXml -command "Get-VBRJob" -name backupvmbyjob -switch byvm -type Backup
        ExportXml -command "Get-VBRJob" -name backupsyncvmbyjob -switch byvm -type BackupSync
        ExportXml -name backuptaskswithretry -switch bytaskswithretry
        
        # EXPORTA REPOSITORIOS PARA XML
        ExportXml -name backuprepo -switch repos
        
        Write-Output "1"
    }
    
    "ResultBackup" {
        $xml = ImportXml -item backuptaskswithretry
        $query1 = $xml | Where-Object { $_.jobId -like "$ID" } | Sort-Object JobStart -Descending | Select-Object -First 1
        $query2 = $query1.JobResult
        if (!$query2.value) { write-output "4" }
        else {
            $query3 = $query2.value
            $query4 = "$query3" | VeeamStatusReplace
            write-output "$query4"
        }
    }
    
    "ResultTape" {
        if (!$ID) { write-output "4" } else {
            $xml1 = ImportXml -item backuptape
            $query = $xml1 | Where-Object { $_.Id -like "*$ID*" } | Sort-Object creationtime -Descending | Select-Object -First 1
            $status = $null
            if ($query.LastResult.Value) { $status = $query.LastResult.Value }
            elseif ($query.LastResult) { $status = $query.LastResult }

            if (!$status) { write-output "4" } else {
                if (($query.LastState.Value -like "WaitingTape") -and ($status -like "None")) { write-output "1" }
                else { $final = "$status" | VeeamStatusReplace; write-output "$final" }
            }
        }
    }
    
    "ResultEndpoint" {
        if (!$ID) { write-output "4" } else {
            $xml3 = ImportXml -item backupendpoint
            $query = $xml3 | Where-Object { $_.Id -like "*$ID*" }
            $query1 = $query | Where-Object { $_.Id -eq $query.Id } | Sort-Object creationtime -Descending | Select-Object -First 1
            $query2 = $query1.LastResult
            if (!$query2) { write-output "4" } else {
                $query4 = $query2.value
                $query3 = $query4 | VeeamStatusReplace
                write-output "$query3"
            }
        }
    }
    
    "ResultReplica" {
        $xml = ImportXml -item backupsession
        $query1 = $xml | Where-Object { $_.jobId -like "$ID" } | Sort-Object creationtime -Descending | Select-Object -First 1
        $query2 = $query1.Result
        if (!$query2.value) { write-output "4" } else {
            $query3 = $query2.value
            $query4 = "$query3" | VeeamStatusReplace
            write-output "$query4"
        }
    }
    
    "VmResultBackup" {
        $query = veeam-backuptask-unique -ID $ID0 -jobtype jobname
        $result = $query | Where-Object { $_.Name -like "$ID" }
        if (!$result) { write-output "4" } else {
            $query3 = $Result.Status.Value
            $query4 = $query3 | VeeamStatusReplace
            [string]$query4
        }
    }

    "RepoCapacity" {
       
        $xml = ImportXml -item backuprepo
        $repo = $xml | Where-Object { $_.Name -eq $ID }
        if ($repo -and $repo.TotalSpace) { [string]$repo.TotalSpace } else { "0" }
    }
    
    "RepoFree" {
       
        $xml = ImportXml -item backuprepo
        $repo = $xml | Where-Object { $_.Name -eq $ID }
        if ($repo -and $repo.FreeSpace) { [string]$repo.FreeSpace } else { "0" }
    }
    
    "RunStatus" {
        $xml1 = ImportXml -item backupjob
        $query = $xml1 | Where-Object { $_.Id -like "*$ID*" }
        if ($query.IsRunning) { return "1" } else { return "0" }
    }

    "JobsCount" { $xml1 = ImportXml -item backupjob | Measure-Object; [string]$xml1.Count }
    
    "Type" {
        $xml1 = ImportXml -item backupsession
        $query = $xml1 | Where-Object { $_.JobId -like "$ID" } | Select-Object -First 1
        [string]$query.JobType
    }
    
    "LastRunTime" {
        $xml1 = ImportXml -item backupsession
        $query = $xml1 | Where-Object { $_.JobId -like "*$ID*" } | Sort-Object creationtime -Descending | Select-Object -First 1
        [string]$query1 = $query.CreationTimeUTC.ToString('dd/MM/yyyy HH:mm:ss')
        $result1 = $nextdate, $nexttime = $query1.Split(" ")
        $newdate = ("$($nextdate -replace "(\d{2})-(\d{2})", "`$2-`$1") $nexttime")
        $date = get-date -date "01/01/1970"
        $result2 = (New-TimeSpan -Start $date -end $newdate).TotalSeconds
        [string]$result2
    }
    
    "LastEndTime" {
        $xml1 = ImportXml -item backupsession
        $query = $xml1 | Where-Object { $_.JobId -like "*$ID*" } | Sort-Object creationtime -Descending | Select-Object -First 1
        [string]$query1 = $query.EndTime
        $result1 = $nextdate, $nexttime = $query1.Split(" ")
        $newdate = [datetime]("$($nextdate -replace "(\d{2})-(\d{2})", "`$2-`$1") $nexttime")
        $date = get-date -date "01/01/1970"
        $result2 = (New-TimeSpan -Start $date -end $newdate).TotalSeconds
        [string]$result2
    } 
    
    "NextRunTime" {
        $xml1 = ImportXml -item backupjob
        $query = $xml1 | Where-Object { $_.Id -like "*$ID*" }
        $query1 = $query.ScheduleOptions
        $result = $query1.NextRun
        if (!$result) {
            $result = $query | Select-Object name, @{ N = 'RunAfter'; E = { ($xml1 | Where-Object { $_.id -eq $query.info.ParentScheduleId }).Name } }
            $result1 = 'After Job' + " : " + $result.RunAfter
            [string]$result1
        } else { [string]$result }
    }
    
    "RunningJob" {
        $xml1 = ImportXml -item backupjob
        $query = $xml1 | Where-Object { $_.IsRunning -eq $true } | Measure-Object
        if ($query) { [string]$query.Count } else { return "0" }
    }
    default { write-output "-- ERROR -- : Need an option !" }
}