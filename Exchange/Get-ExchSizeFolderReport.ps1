<#
.SYNOPSIS
    Lista todas as pastas de uma caixa de correio, incluindo o Archive, e gera um relatório com informações sobre o tamanho de cada pasta.

.DESCRIPTION
    Este script conecta-se ao Exchange Online, verifica todas as pastas de uma caixa de correio especificada, incluindo o Archive (se houver),
    e gera um relatório com informações sobre o tamanho de cada pasta.

.VERSION
    1.0.0

.NOTES
    Autor : Breno Melo
    E-mail: bmmelo@hotmail.com

    Histórico de alterações:
        1.0.0 (13/10/2026) - Criação do script.
#>

# Garante TLS 1.2 (necessário em algumas máquinas)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Bloco 1: Instala, atualiza, importa o módulo Exchange Online Management e inicia a sessão.
# -------------------------------------------------------------------------------------------------------------------
try {
    $installedModule = Get-InstalledModule ExchangeOnlineManagement -ErrorAction SilentlyContinue

    if ($null -eq $installedModule) {
        Install-Module ExchangeOnlineManagement -Force -ErrorAction Stop
        $installedModule = Get-InstalledModule ExchangeOnlineManagement -ErrorAction Stop
    }

    $repositoryModule = Find-Module ExchangeOnlineManagement -ErrorAction Stop

    if ([version]$repositoryModule.Version -gt [version]$installedModule.Version) {
        Write-Host "Versão atual do módulo Exchange Online Management: $($installedModule.Version)"
        
        $inputUpdate = Read-Host "Nova versão do módulo disponível no repositório: $($repositoryModule.Version). Deseja atualizar? (S/N)"
        
        $inputUpdate = $inputUpdate.Trim()

        if ($inputUpdate -match "^[sn]$") {
            Update-Module ExchangeOnlineManagement -Force -ErrorAction Stop
            Write-Host "Atualização concluída." -ForegroundColor Green
        } else {
            Write-Warning "Atualização cancelada."
        }
    }
    Write-Host "`nImportando módulo para a sessão atual..." -ForegroundColor Cyan
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
} catch {
    Write-Error "Não foi possível preparar o módulo Exchange Online Management: $($_.Exception.Message)"
    return
}

# Solicita a conta de usuário com perfil administrativo para conexão com o Exchange Online.
do {
    $inputMailAddress = Read-Host "`nInforme conta de e-mail para conexão com o Exchange Online"

    $inputMailAddress = $inputMailAddress.Trim()

    try {
        $mailAddress = [System.Net.Mail.MailAddress]::new($inputMailAddress)
        $isValidEmail = $mailAddress.Address -eq $inputMailAddress
    } catch {
        $isValidEmail = $false
    }

    if (-not $isValidEmail) {
        Write-Warning "Formato de e-mail inválido. Tente novamente."
    }
} while (-not $isValidEmail)

# Inicia sessão do usuário com o Exchange Online.
try {
    Connect-ExchangeOnline -UserPrincipalName $inputMailAddress -ErrorAction Stop

    $connection = Get-ConnectionInformation |
        Where-Object { $_.Name -match 'ExchangeOnline' -and $_.State -eq 'Connected' }

    if (-not $connection) {
        throw "Não foi possível estabelecer uma sessão com o Exchange Online."
    } else {
        Write-Host "Conexão com Exchange Online estabelecida com sucesso!" -ForegroundColor Green
    }
} catch {
    Write-Error "Falha ao conectar ao Exchange Online: $($_.Exception.Message)"
    return
}

# Bloco 2: Define o caminho e o nome do arquivo de report.
# -------------------------------------------------------------------------------------------------------------------
$reportPath = "$PSScriptRoot\PSReport"
$reportFile = "Get-ExchSizeFolderReport_$(Get-Date -Format "yyyyMMdd_HHmmss").csv"
$reportPathFile = Join-Path $reportPath $reportFile

try {
    # Cria a pasta de report, caso ela ainda não exista.
    if (-not (Test-Path -LiteralPath $reportPath -ErrorAction Stop)) {
        New-Item -ItemType Directory -Path $reportPath -Force -ErrorAction Stop | Out-Null
    }
} catch {
    Write-Error "Erro ao criar pasta de report: $($_.Exception.Message)"
    return
}

# Bloco 3: Geração do relatório no formato CSV 
# -------------------------------------------------------------------------------------------------------------------
# Solicita o e-mail do usuário para gerar o relatório.
do {
    $inputUserMailbox = Read-Host "`nInforme o e-mail que deseja gerar o relatório"

    $inputUserMailbox = $inputUserMailbox.Trim()

    try {
        $userMailBox = [System.Net.Mail.MailAddress]::new($inputUserMailbox)
        $isValidEmail = $userMailBox.Address -eq $inputUserMailbox
    } catch {
        $isValidEmail = $false
    }

    if (-not $isValidEmail) {
        Write-Warning "Formato de e-mail inválido. Tente novamente."
    }
} while (-not $isValidEmail)


function Get-FolderSizeReport {
    param(
        [string]$Mailbox,
        [switch]$Archive
    )

    $params = @{
        Identity    = $Mailbox
        ErrorAction = 'Stop'
    }
    if ($Archive) { $params['Archive'] = $true }

    Get-EXOMailboxFolderStatistics @params |
        Select-Object `
            @{Name="MailboxType"; Expression={ if ($Archive) {"Archive"} else {"Principal"} }},
            FolderPath,
            ItemsInFolder,
            @{Name="FolderSize_MB"; Expression={
                if ($_.FolderSize -match '\(([\d,]+)\s*bytes\)') {
                    [math]::round(([double]($Matches[1] -replace ',', '') / 1MB), 2)
                } else {
                    $null
                }
            }},
            @{Name="FolderSize_Readable"; Expression={$_.FolderSize.ToString()}}
}

try {
    # Coleta as estatísticas das pastas - Caixa Principal
    $MainStats = Get-FolderSizeReport -Mailbox $inputUserMailbox

    # Coleta o Archive somente quando ele estiver ativo.
    $mailboxInfo = Get-Mailbox -Identity $inputUserMailbox -ErrorAction Stop

    $ArchiveStats = @()
    if ($mailboxInfo.ArchiveStatus -eq "Active" -or ($mailboxInfo.ArchiveGuid.ToString() -and $mailboxInfo.ArchiveGuid.ToString() -ne "00000000-0000-0000-0000-000000000000")) {
        $ArchiveStats = Get-FolderSizeReport -Mailbox $inputUserMailbox -Archive
    } else {
        Write-Warning "A caixa '$inputUserMailbox' não possui Archive habilitado. O relatório conterá somente as pastas da caixa principal."
    }

    # Une os dois resultados - Caixa Principal + Archive
    $Report = @()
    $Report += $MainStats
    $Report += $ArchiveStats

    if (-not $Report -or $Report.Count -eq 0) {
        Write-Warning "Nenhuma pasta foi retornada para '$inputUserMailbox'. Verifique se o e-mail está correto e se você tem permissão de acesso à caixa."
    } else {
       
        # Exibe o relatório em Grid View. A falha do Grid View é avisada, mas não impede a exportação do CSV.
        try {
            $Report | Out-GridView -Title "Relatório de Tamanho das Pastas da Caixa de Correio: $inputUserMailbox" -ErrorAction Stop
        } catch {
            Write-Warning "Não foi possível abrir o Grid View: $($_.Exception.Message)"
        }

        try {
            # Exporta os resultados para um arquivo CSV
            $Report | Export-Csv -Path $ReportPathFile -NoTypeInformation -Encoding UTF8  -ErrorAction Stop

            Write-Host "`nConcluído!" -ForegroundColor Green
            Write-Host "Relatório salvo em $($reportPathFile)."
            Write-Host "Processadas ($($Report.Count) pastas no total: $($MainStats.Count) principal + $($ArchiveStats.Count) archive)" -ForegroundColor Green
        } catch {
            Write-Error "Erro ao gerar ou exportar o relatório: $($_.Exception.Message)"
        }
    }    
    
} catch {
    Write-Error "Ocorreu um erro ao coletar os dados: $($_.Exception.Message)"
}


# Bloco 4: Encerra sessão do Exchange Online, caso o usuário deseje.
# -------------------------------------------------------------------------------------------------------------------
do { 
    $inputExist = Read-Host "`nDeseja encerrar a sessão do Exchange Online? (S/N)"
    
    $inputExist = $inputExist.Trim()
    
    if ($inputExist -match "^[sn]$") {

        if ($inputExist -eq 's') {
            try {
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop
                Write-Host "Conexão encerrada!" -ForegroundColor Green
            } catch {
                Write-Error "Erro ao encerrar a sessão do Exchange Online: $($_.Exception.Message)"
            }
        } else {
            Write-Host "Manter conexão ativa." -ForegroundColor Yellow
        }
        
        $isValid = $true
    } else {
        Write-Warning "Resposta inválida! Digite S ou N."
        $isValid = $false
    }
    
    Write-Host ""

} while (-not $isValid)