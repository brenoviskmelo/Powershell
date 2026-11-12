<#
invoke-Command -ComputerName nb061 `
    -Credential 'user@domain.local' `
    -ScriptBlock {
        Get-ChildItem -Path 'HKCU:\Network' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $item = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue

            [PSCustomObject]@{
                Unidade      = $_.PSChildName
                CaminhoRemoto = $item.RemotePath
                Utilizador   = $item.UserName
            }
        }
    }
#>

Write-Host "`nLista Mapeamentos de Unidades de Rede" -ForegroundColor Cyan
Write-Host "------------------------------------------------------" -ForegroundColor Cyan

try {
    # Define a pasta dos relatorios.
    $currentPath = if ($PSScriptRoot) {
        $PSScriptRoot
    }
    else {
        Split-Path -Parent $PSCommandPath
    }

    $reportPath = Join-Path $currentPath "PSReport"
    $reportFile = "Get-MapNetwork-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $reportPathFile = Join-Path $reportPath $reportFile

    # Cria a pasta de report, caso ela ainda não exista.
    if (-not (Test-Path -LiteralPath $reportPath -ErrorAction Stop)) {
        New-Item -ItemType Directory -Path $reportPath -Force -ErrorAction Stop | Out-Null
    }
catch {
    Write-Error "Não foi possível criar a pasta de relatório: $($_.Exception.Message)"
    return
}

$inputComputerName = (Read-Host "Informe o nome do computador").Trim()
$credential = Get-Credential -Message "Informe as credenciais para conexão remota ao computador $inputComputerName"


$report = Invoke-Command -ComputerName $inputComputerName `
-Credential $credential `
-ScriptBlock {
    # Procura em todos os perfis carregados no HKEY_USERS (ignorando contas de sistema)
    Get-ChildItem -Path 'Registry::HKEY_USERS' | Where-Object { $_.PSChildName -match '^S-1-5-21-' -and $_.PSChildName -notmatch '_Classes$' } | ForEach-Object {
        $sidString = $_.PSChildName
        $networkPath = Join-Path -Path $_.PSPath -ChildPath 'Network'

        # Tenta traduzir o SID para o nome de utilizador (Dominio\Utilizador)
        try {
            $objSID = New-Object System.Security.Principal.SecurityIdentifier($sidString)
            $nomeUtilizador = $objSID.Translate([System.Security.Principal.NTAccount]).Value
        } catch {
            $nomeUtilizador = $sidString
        }

        if (Test-Path $networkPath) {
            Get-ChildItem -Path $networkPath | ForEach-Object {
                $item = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue

                [PSCustomObject]@{
                    UtilizadorPerfil = $nomeUtilizador
                    Unidade          = $_.PSChildName
                    CaminhoRemoto    = $item.RemotePath
                    ContaUsadaNoMap  = $item.UserName
                }
            }
        }
    }
} | Select-Object PSComputerName, UtilizadorPerfil, Unidade, CaminhoRemoto, ContaUsadaNoMap | Format-Table -AutoSize

$report | Export-Csv -Path $reportPathFile -NoTypeInformation -Encoding utf8BOM -ErrorAction Stop

