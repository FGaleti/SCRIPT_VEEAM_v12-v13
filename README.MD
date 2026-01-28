# Veeam Backup & Replication Monitoring for Zabbix

This PowerShell script provides an advanced integration between **Veeam Backup & Replication (v12/v13)** and **Zabbix**. It utilizes a **Synchronous XML Export Mode** to ensure high performance, avoiding database lockups, timeouts, and high CPU spikes during monitoring polls.

## 🚀 Key Features

* **Low Impact:** Data is exported to local XML files periodically, allowing Zabbix to read results instantly without querying the Veeam API/DB every time.
* **Comprehensive Discovery:** Automatic discovery of Backup Jobs, Replication, Backup Sync, Tape Jobs, and Agent-based jobs.
* **Granular VM Monitoring:** Tracks the status of individual Virtual Machines within jobs.
* **Repository Insights:** Monitors Capacity and Free Space for Backup Repositories.
* **Modern Compatibility:** Fully updated for Veeam v12/v13 and optimized for PowerShell 7.

## 🛠️ Prerequisites

1. **Veeam Backup & Replication:** Version 12 or 13.
2. **PowerShell:** Version 7.x (pwsh) is highly recommended.
3. **Veeam Module:** The `Veeam.Backup.PowerShell` module must be installed on the server.
4. **Zabbix Agent:** Installed and configured to execute scripts (e.g., `AllowKey=system.run[*]`).

## 📁 Directory Structure

The script uses a temporary directory to store the cache.

* **Default Path:** `C:\Program Files\Zabbix Agent\scripts\TempXmlVeeam`

> **Note:** Ensure the Zabbix Agent service user has Read/Write permissions to this folder.

## ⚙️ Installation & Setup

### 1. Script Placement

Save the `zabbix_vbr_job.ps1` script into your Zabbix Agent scripts directory (e.g., `C:\Program Files\Zabbix Agent\scripts\`).

### 2. Configure UserParameter

Add the following line to your `zabbix_agentd.conf` or a dedicated `.conf` file in the `zabbix_agentd.d/` directory:

```conf
UserParameter=veeam.vbr[*],pwsh.exe -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" "$1" "$2" "$3"

```

### 3. Schedule the Data Export

The monitoring relies on an exported XML cache. You must schedule the `ExportXml` task to run every 5 to 15 minutes via **Windows Task Scheduler** or a **Zabbix Item**:

```powershell
pwsh.exe -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" "ExportXml"

```

## 📊 Command Reference

| Item (Arg 0) | Description |
| --- | --- |
| `ExportXml` | Refreshes the XML cache (Run this first!). |
| `DiscoveryBackupJobs` | JSON output for Backup Job LLD. |
| `DiscoveryRepo` | JSON output for Repository LLD. |
| `ResultBackup` | Returns the status of a Job (Requires Job ID). |
| `RepoFree` | Returns Free Space in bytes (Requires Repo Name). |
| `VmResultBackup` | Returns the status of a specific VM. |
| `NextRunTime` | Returns the scheduled time for the next run. |

## 📝 Status Mapping

To facilitate Triggers and Dashboards, textual statuses are converted to integers:

* **0:** Failed
* **1:** Warning
* **2:** Success / None
* **3:** Idle
* **5:** In Progress
* **13:** Waiting (Repository/Tape) / Working
* **4:** Error / Not Found

## 🤝 Authors

* **Felipe Galeti** 
* **Nathan Schiavon** 

