<#
.SYNOPSIS
    Lista os mapeamentos de unidades de rede configurados para os perfis de usuário em um computador remoto.

.DESCRIPTION
    O script solicita o nome do computador remoto e as credenciais para conexão via WinRM/PowerShell remota.
    Em seguida, executa o comando no host informado e percorre todos os perfis de usuário registrados em HKEY_USERS,
    ignorando contas de sistema e perfis sem associação válida.

    Para cada perfil encontrado, o script verifica se há chaves na pasta Network e captura as informações de cada
    unidade mapeada, como o usuário do perfil, a letra da unidade, o caminho remoto e a conta usada para o mapeamento.

    Os dados são exibidos em tabela no console e exportados para um arquivo CSV na pasta PSReport, criada junto ao script.

    Requisitos:
        - O computador remoto deve estar acessível pela sessão remota do PowerShell.
        - As credenciais informadas devem ter permissão para consultar o registro do sistema remoto.
       
.VERSION
    1.0.0

.NOTES
    Autor : Breno Melo
    E-mail: bmmelo@hotmail.com

    Histórico de alterações:
        v1.0.0 (12/11/2026) - Criação do script.
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

