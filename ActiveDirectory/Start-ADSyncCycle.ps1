
<#
.SYNOPSIS
    Inicia ciclo de sincronização entre o Active Directory (AD) local e o Microsoft Entra ID (antigo Azure AD)
    através de um computador remoto.

.DESCRIPTION
    A sincronização, por padrão, utiliza a ferramenta Microsoft Entra Connect, que executa uma sincronização
    automaticamente a cada 30 minutos.
    No entanto, se você fizer uma alteração urgente (como criar um usuário ou atualizar a senha de um grupo)
    e precisar que ela seja refletida imediatamente na nuvem, poderá executar este comando.

    Comandos úteis, mas não utilizados no script:
    Get-ADSyncConnector > consultar os conectores configurados.
    Get-ADSyncScheduler > consultar o intervalo de sincronização, o status e quando o próximo ciclo está agendado.
    Set-ADSyncScheduler -SyncCycleEnabled $false > pausar a sincronização automática para realizar manutenção ou atualizar regras.
    Set-ADSyncScheduler -SyncCycleEnabled $true  > retomar os ciclos automáticos em segundo plano, realizados a cada 30 minutos.

.VERSION
    1.0.0

.NOTES
    Autor : Breno Melo
    E-mail: bmmelo@hotmail.com

    Histórico de alterações:
        v1.0.0. (15/10/2026) - Criação do script.
#>

# Bloco 1: Solicita UserAccount e Password para autenticação do usuário da rede.
# -------------------------------------------------------------------------------------------------------------------
$context = $null

try {
    # Carrega a assembly necessária do .NET para autenticação do Active Directory
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    
    # Prompt de credenciais para autenticação
    Write-Host "`nSyncCycle Active Directory <> Microsoft Entra ID" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Informe credenciais de acesso à rede para autenticação"
    
    $credential = Get-Credential

    if ($null -eq $credential -or $credential -eq "") {
        Write-Warning "Operação cancelada pelo usuário."
        return
    }

    $inputUserName = $credential.UserName
    $password = $credential.GetNetworkCredential().Password

    if ([string]::IsNullOrEmpty($inputUserName) -or [string]::IsNullOrEmpty($password)) {
        Write-Warning "`nUsuário ou senha não foram informados."
        return
    }

    # Define o contexto estritamente para o Domínio AD
    $contextType = [System.DirectoryServices.AccountManagement.ContextType]::Domain
    
    # Captura domínio informado durante a autenticação para acelerar a validação
    if ($inputUserName -like "*@*"){
        $parts = $inputUserName.Split('@')
        $userName = $parts[0]
        $domainName = $parts[1]
    } elseif ($inputUserName -like "*\*") {
        $parts = $inputUserName.Split('*\*')
        $userName = $parts[1]
        $domainName = $parts[0]
    } else {
        $userName = $inputUserName
        $domainName = $env:USERDOMAIN
    }    

    # Inicializa o contexto apontando diretamente para o domínio
    $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($contextType, $domainName)
    
    # Valida as credenciais no Active Directory
    $isValid = $context.ValidateCredentials($userName, $password)

    if ($isValid) {
        Write-Host "Login realizado com sucesso no domínio $domainName!" -ForegroundColor Green
    } 
    else {
        Write-Warning "Usuário ou senha incorretos para o domínio $domainName."
        return
    }
} 
catch [System.OperationCanceledException] {
    Write-Warning "O usuário clicou em Cancelar."
    return
}
catch {
    Write-Error "Erro ao tentar validar as credenciais <$($userName)> no domínio <$($domainName)>"
    Write-Error "$($_.Exception.Message)"
    return
}
finally {
    # Libera objeto do .NET da memória do sistema
    if ($null -ne $context) {
        $context.Dispose()
    }
    
    # Remove variável contendo a senha da memória
    if ($null -ne $password) {
        Remove-Variable -Name password -Force
    }
}

# Bloco 2: Solicita e valida o nome do servidor remoto.
# -------------------------------------------------------------------------------------------------------------------
do {
    $inputServerName = (Read-Host -Prompt "`nInforme nome do servidor remoto (ex: SRV01ADSync) ou <sair> para encerrar o script").Trim()

    if ($inputServerName -eq "sair") {
        Write-Host "Script encerrado." -ForegroundColor Yellow
        exit
    } else {
        $isValid = [String]::IsNullOrWhiteSpace($inputServerName)
        if ($isValid) {
            Write-Warning "Nome do servidor não pode ser vazio. Tente novamente."
        } else {
            $connectServer = test-connection -ComputerName $inputServerName -Count 1 -Quiet
            if (-not $connectServer) {
                $isValid = $false
                Write-Warning "`nServidor $($inputServerName) não encontrado. Tente novamente."
            } else {
                $isValid = $true
                Write-Host "`nServidor $($inputServerName) encontrado." -ForegroundColor Green
            }
        }
    }    
} while (-not $isValid)

# Bloco 3: Executa o ciclo de sincronização e permite iniciar novo ciclo. 
# -------------------------------------------------------------------------------------------------------------------
do {
    Write-Host "`nIniciando ciclo de sincronização..." -ForegroundColor Cyan

    $syncResult = Invoke-Command -ComputerName $inputServerName -Credential $credential -ScriptBlock {
        Start-ADSyncSyncCycle -PolicyType Delta
    }

    $syncResult | Out-Host

    $inputNewCycle = (Read-Host "`nDeseja iniciar novo ciclo de sincronização? (S/N)").Trim()

    if ($inputNewCycle -match "^[sn]$") {

        if ($inputNewCycle -eq "s") {
            $continueLoop = $true
        } 
        else {
            $continueLoop = $false
            Write-Host "Script encerrado!" -ForegroundColor Yellow
        }
    }
    else {
        $continueLoop = $true
        Write-Warning "Resposta inválida! Digite S ou N."
    }

} while ($continueLoop)