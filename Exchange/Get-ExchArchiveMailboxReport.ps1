<#
.SYNOPSIS
    Lista todas as caixas de correio com o Archive habilitado.

.DESCRIPTION
    Este script conecta-se ao Exchange Online, verifica todas as caixas de correio que possuem o recurso de Archive
    habilitado e gera um relatório detalhado com informações sobre o tamanho da caixa principal e do arquivo, bem
    como a porcentagem de uso em relação à cota definida.

.VERSION
    1.0.0

.NOTES
    Autor : Breno Melo

    Histórico de alterações:
        1.0.0 (09/10/2026) - Criação do script.
#>

# -------------------------------------------------------------------------------------------------------------------

# Instala, atualiza e importa o módulo Exchange Online Management.
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
            Update-Module ExchangeOnlineManagement -Force
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

# Solicita a conta de usuário para conexão com o Exchange Online.
do {
    $inputMailAddress = Read-Host "`nDigite o e-mail da conta de usuário para conexão com Exchange"

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
        throw "Não foi possível confirmar uma sessão conectada ao Exchange Online."
    } else {
        Write-Host "Conexão com Exchange Online estabelecida com sucesso!" -ForegroundColor Green
    }
} catch {
    Write-Error "Falha ao conectar ao Exchange Online: $($_.Exception.Message)"
    return
}

# -------------------------------------------------------------------------------------------------------------------

# Extrai bytes do formato de texto do Exchange
function ConvertTo-Bytes ($PropriedadeTamanho) {
     if ($PropriedadeTamanho -and $PropriedadeTamanho.ToString() -match '\(([\d.,\s]+)\s+bytes\)') {
        return [long]($Matches[1] -replace '[^\d]', '')
    }
    return 0
}

try {
    # Pesquisa todas as caixas de correio com o Archive habilitado.
    Write-Host "Pesquisando caixas de correio com o Archive habilitado no Exchange Online..."

    $ArchivedMailboxes = Get-Mailbox -Archive -ResultSize Unlimited -errorAction Stop

    Write-Host "Calculando o tamanho, em GB, das caixas de correio principal e de arquivo..."

    $Report = foreach ($Mailbox in $ArchivedMailboxes) {
        # Obtém as estatísticas da mailbox principal e do arquivo
        $MainStats    = Get-MailboxStatistics -Identity $Mailbox.UserPrincipalName -ErrorAction Stop
        $ArchiveStats = Get-MailboxStatistics -Identity $Mailbox.UserPrincipalName -Archive -ErrorAction Stop
        
        # --- Processamento da caixa principal ---
        # Extrai o tamanho da caixa.
        $BytesMain     = ConvertTo-Bytes $MainStats.TotalItemSize
        $TamanhoMainGB = [math]::Round($BytesMain / 1GB, 2)

        # Extrai a cota máxima, em bytes.
        $QuotaMainBytes = ConvertTo-Bytes $Mailbox.ProhibitSendQuota
        $PorcentagemMain = 0
        if ($QuotaMainBytes -gt 0) {
            $PorcentagemMain = [math]::Round(($BytesMain / $QuotaMainBytes) * 100, 2)
        }

        # --- Processamento da caixa de arquivo ---
        # Extrai o tamanho da caixa.
        $BytesArchive     = ConvertTo-Bytes $ArchiveStats.TotalItemSize
        $TamanhoArchiveGB = [math]::Round($BytesArchive / 1GB, 2)

        # Extrai a cota máxima do arquivo, em bytes.
        # O campo ArchiveQuota pode refletir melhor a cota real do arquivo, mas o ProhibitSendQuota é mais confiável para cálculos.
        $QuotaArchiveBytes = ConvertTo-Bytes $Mailbox.ArchiveQuota 
        $PorcentagemArchive = 0
        if ($QuotaArchiveBytes -gt 0) {
            $PorcentagemArchive = [math]::Round(($BytesArchive / $QuotaArchiveBytes) * 100, 2)
        }

        # --- Criação do objeto de saída ---
        [PSCustomObject]@{
            "Nome"                  = $Mailbox.DisplayName
            "EmailPrincipal"        = $Mailbox.PrimarySmtpAddress
            
            # Dados Caixa Principal
            "QuotaMain_GB"          = [long]($QuotaMainBytes / 1GB)
            "SizeMain_GB"           = $TamanhoMainGB
            "PercentualMain"        = "$PorcentagemMain%"
            "ItensMain"             = if ($MainStats.ItemCount) { $MainStats.ItemCount } else { 0 }
            
            # Dados Caixa Arquivo
            "QuotaArchive_GB"       = [long]($QuotaArchiveBytes / 1GB)
            "SizeArchive_GB"        = $TamanhoArchiveGB
            "PercentualArchive"     = "$PorcentagemArchive%"
            "ItensArchive"          = if ($ArchiveStats.ItemCount) { $ArchiveStats.ItemCount } else { 0 }
        }
    }
} catch {
        Write-Error "Erro ao processar as caixas de correio: $($_.Exception.Message)"
        return
}

# Define o caminho e o nome do arquivo de log.
$logPath = "C:\PSLog"
$logFile = "Mailboxes_with_archive_enabled_$(Get-Date -Format "yyyyMMdd_HHmmss").csv"
$logPathFile = Join-Path $logPath $logFile

try {
    # Cria a pasta de log, caso ela ainda não exista.
    if (-not (Test-Path -LiteralPath $logPath -ErrorAction Stop)) {
        New-Item -ItemType Directory -Path $logPath -Force -ErrorAction Stop | Out-Null
    }

    # Ordena pelo tamanho do Archive, do maior para o menor.
    $Report = $Report | Sort-Object -Property SizeArchive_GB -Descending

    # A falha do Grid View é avisada, mas não impede a exportação do CSV.
    try {
        $Report | Out-GridView -Title "Contas com Archive - Ordenado por Tamanho do Archive (descendente)" -ErrorAction Stop
    } catch {
        Write-Warning "Não foi possível abrir o Grid View: $($_.Exception.Message)"
    }

    # Exporta o relatório completo para CSV.
    $Report | Export-Csv -Path $logPathFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "Concluído!" -ForegroundColor Green
    Write-Host "Relatório salvo em $logPathFile."
    Write-Host "Total de contas processadas: $($Report.Count)"
} catch {
    Write-Error "Erro ao gerar ou exportar o relatório: $($_.Exception.Message)"
}

# -------------------------------------------------------------------------------------------------------------------

## Encerra sessão como Exchange Online, caso o usuário deseje.
do { 
    $inputExist = Read-Host "`nDeseja encerrar a sessão do Exchange Online? (S/N)"
    
    $inputExist = $inputExist.Trim()
    
    if ($inputExist -match "^[sn]$") {

        if ($inputExist -eq 's') {
            Disconnect-ExchangeOnline -Confirm:$false
            Write-Host "Conexão encerrada!" -ForegroundColor Green
        } else {
            Write-Host "Manter conexão ativa." -ForegroundColor Yellow

        }

        $isValid = $true
    } else {
        Write-Warning "Resposta inválida! Digite S ou N."
        $isValid = $false
    }
} while (-not $isValid)