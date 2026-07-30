# Veeam Backup & Replication Monitoring for Zabbix

Este script PowerShell fornece uma integração avançada entre o **Veeam Backup & Replication (v12/v13)** e o **Zabbix**. Ele utiliza um modo de **Exportação Síncrona em XML** para garantir alta performance, evitando travamentos de banco de dados, timeouts e picos de CPU durante os polls de monitoramento.

---

## Principais Recursos

| Recurso | Descrição |
|---|---|
| **Baixo Impacto** | Os dados são exportados para arquivos XML locais periodicamente, permitindo que o Zabbix leia os resultados instantaneamente, sem consultar a API/DB do Veeam a cada polling |
| **Descoberta Abrangente** | Descoberta automática de Backup Jobs, Replication, Backup Sync, Tape Jobs e jobs baseados em Agent |
| **Monitoramento Granular de VMs** | Acompanha o status de máquinas virtuais individuais dentro dos jobs |
| **Insights de Repositório** | Monitora capacidade e espaço livre dos Backup Repositories |
| **Compatibilidade Moderna** | Totalmente atualizado para Veeam v12/v13 e otimizado para PowerShell 7 |

---

## Pré-requisitos

1. **Veeam Backup & Replication:** Versão 12 ou 13.
2. **PowerShell:** Versão 7.x (pwsh) altamente recomendada.
3. **Módulo Veeam:** O módulo `Veeam.Backup.PowerShell` deve estar instalado no servidor.
4. **Zabbix Agent:** Instalado e configurado para executar scripts (ex.: `AllowKey=system.run[*]`).

---

## Estrutura de Diretórios

O script utiliza um diretório temporário para armazenar o cache.

- **Caminho padrão:** `C:\Program Files\Zabbix Agent\scripts\TempXmlVeeam`

> **Nota:** Garanta que o usuário do serviço do Zabbix Agent possua permissões de leitura/escrita nessa pasta.

---

## Instalação e Configuração

### 1. Posicionamento do Script

Salve o script `zabbix_vbr_job.ps1` no diretório de scripts do Zabbix Agent (ex.: `C:\Program Files\Zabbix Agent\scripts\`).

### 2. Configurar o UserParameter

Adicione a linha a seguir ao `zabbix_agentd.conf` ou a um arquivo `.conf` dedicado dentro do diretório `zabbix_agentd.d/`:

```conf
UserParameter=veeam.vbr[*],pwsh.exe -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" "$1" "$2" "$3"
```

### 3. Agendar a Exportação de Dados

O monitoramento depende de um cache XML exportado. Agende a task `ExportXml` para ser executada a cada 5 a 15 minutos via **Windows Task Scheduler** ou um **Item do Zabbix**:

```powershell
pwsh.exe -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" "ExportXml"
```

---

## Referência de Comandos

| Item (Arg 0) | Descrição |
| --- | --- |
| `ExportXml` | Atualiza o cache XML (execute este primeiro!) |
| `DiscoveryBackupJobs` | Saída JSON para LLD de Backup Jobs |
| `DiscoveryRepo` | Saída JSON para LLD de Repositórios |
| `ResultBackup` | Retorna o status de um Job (requer Job ID) |
| `RepoFree` | Retorna o espaço livre em bytes (requer nome do Repo) |
| `VmResultBackup` | Retorna o status de uma VM específica |
| `NextRunTime` | Retorna o horário agendado da próxima execução |

---

## Mapeamento de Status

Para facilitar Triggers e Dashboards, os status textuais são convertidos em inteiros:

| Código | Status |
|---|---|
| 0 | Failed |
| 1 | Warning |
| 2 | Success / None |
| 3 | Idle |
| 4 | Error / Not Found |
| 5 | In Progress |
| 13 | Waiting (Repository/Tape) / Working |

---

## Autores

- **Felipe Galeti**
- **Nathan Schiavon**
