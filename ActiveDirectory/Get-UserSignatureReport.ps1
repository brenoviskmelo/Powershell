<#
.SYNOPSIS
    Gera relatório com dados de usuários do Active Directory, que são utilizados na assinatura do Outlook.

.DESCRIPTION
O script percorre as OUs definidas na variável $OUs, filtra apenas usuários ativos com e-mail cadastrado, coleta informações como
nome, e-mail, cargo, departamento, telefone do escritório e celular, e exporta os resultados em um arquivo CSV dentro da pasta PSReport.

Exemplo de definição das OUs:
    $OUs = @(
        (Get-ADOrganizationalUnit -identity "OU=Abais,OU=Filiais,DC=sergipe,DC=local"),
        (Get-ADOrganizationalUnit -identity "OU=Aracaju,OU=Filiais,DC=sergipe,DC=local"),
        (Get-ADOrganizationalUnit -identity "OU=Itabaiana,OU=Filiais,DC=sergipe,DC=local")
    )

.VERSION
    1.0.0

.NOTES
    Autor : Breno Melo
    E-mail: bmmelo@hotmail.com

    Histórico de alterações:
        v1.0.0. (15/10/2026) - Criação do script.
#>

try {
    # Define a pasta dos relatorios.
    $basePath = if ($PSScriptRoot) {
        $PSScriptRoot
    }
    else {
        (Get-Location).Path
    }

    $reportPath = Join-Path $basePath "PSReport"
    $reportFile = "Get-UserSignatureReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $reportPathFile = Join-Path $reportPath $reportFile

    # Cria a pasta de report, caso ela ainda não exista.
    if (-not (Test-Path -LiteralPath $reportPath -ErrorAction Stop)) {
        New-Item -ItemType Directory -Path $reportPath -Force -ErrorAction Stop | Out-Null
    }

    # Carrega o modulo Active Directory.
    Import-Module ActiveDirectory -ErrorAction Stop

    # Definição das OUs.
    $OUs = @(
        (Get-ADOrganizationalUnit -identity "OU=Abais,OU=Filiais,DC=sergipe,DC=local"),
        (Get-ADOrganizationalUnit -identity "OU=Aracaju,OU=Filiais,DC=sergipe,DC=local"),
        (Get-ADOrganizationalUnit -identity "OU=Itabaiana,OU=Filiais,DC=sergipe,DC=local")
    )

    $report = @(
        foreach ($OU in $OUs) { 
            try {
                Get-ADUser `
                -Filter '(Enabled -eq $true) -and (mail -like "*@*")' `
                -SearchBase $OU.DistinguishedName `
                -Properties Mail, DisplayName, Title, Department, OfficePhone, MobilePhone | 
                Select-Object SamAccountName, Mail, DisplayName, Title, Department, OfficePhone, MobilePhone
            } catch {
                Write-Warning "Erro ao processar a OU '$OU': $($_.Exception.Message)"
            }    
        }
    )

    $report = $report | Sort-Object -Property DisplayName

    # Exibi o relatório em Grid View. A falha do Grid View é avisada, mas não impede a exportação do CSV.
    try {
        $report | Out-GridView -Title "Dados Utilizados na Assinatura do Outlook" -ErrorAction Stop
    } catch {
        Write-Warning "Não foi possível abrir o Grid View: $($_.Exception.Message)"
    }

    # Exporta o relatório completo para CSV.
    $Report | Export-Csv -Path $reportPathFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "`nConcluído!" -ForegroundColor Green
    Write-Host "Relatório salvo em $($reportPathFile)."
    Write-Host "Total de contas processadas: $($report.Count)"
} catch {
    Write-Error "Erro ao gerar ou exportar o relatório: $($_.Exception.Message)"
}