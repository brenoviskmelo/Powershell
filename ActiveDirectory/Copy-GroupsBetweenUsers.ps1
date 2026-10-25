
<#
.SYNOPSIS
    Copia grupos do Active Directory de um usuário de origem para um usuário de destino.

.DESCRIPTION
    O script solicita as contas de origem e destino e confirma que ambas existem no Active Directory.
    É feita a verificação de que as contas foram informadas e são diferentes entre si.
    
    Após validar as contas, é feita a pergunta ao usuário se deve remover grupos atuais da conta de destino.
    Se confirmado, remove os grupos retornados por Get-ADPrincipalGroupMembership, exceto 'Domain Users'.
    Em seguida, adiciona à conta de destino os grupos listados na propriedade MemberOf do usuário de origem.

    O resultado das operações é registrado em um arquivo de log na pasta PSLog, criada junto ao script.
    O relatório inclui os grupos processados, falhas e totais de operações concluídas.

    Durante a execução do script, nas interações com o usuário, ao informa a palavra 'sair' encerra o script.

    Requisitos:
        - Módulo ActiveDirectory disponível.
        - Permissões no domínio para consultar contas de usuários e alterar as associações dos grupos.
       
.VERSION
    1.1.0

.NOTES
    Autor : Breno Melo
    E-mail: bmmelo@hotmail.com

    Histórico de alterações:
        v1.0.0 (24/07/2026) - Criação do script.
        v1.1.0 (23/10/2026) - Implementada rotina de testes no preenchimento dos campos durante as interações.
                            - Implementada rotina de log para guardar os grupos excluídos e removidos.
#>


# Bloco 1: Validar conta de usuário e verificar se as contas existem no Active Directory.
# -------------------------------------------------------------------------------------------------------------------
Write-Host "`nCopia Grupos de Segurança entre Dois Usuários | Origem > Destino" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Digite 'sair' nos prompts a qualquer momento para fechar o script." -ForegroundColor DarkGray

do {
    $continueLoop = $true
    $userNameSource = (Read-Host -Prompt "`nInforme a conta do usuário que deseja consultar os grupos (Origem)").Trim()
    
    if ($userNameSource -eq "sair") {
        Write-Host "Script encerrado!`n" -ForegroundColor Yellow 
        return
    } 
    else {
        $userNameTarget = (Read-Host -Prompt "Informe a conta do usuário que vai receber os grupos (Destino)").Trim()
        if ($userNameTarget -eq "sair") {
            Write-Host "Script encerrado!`n" -ForegroundColor Yellow 
            return
        } 
        else {
            # Testa se os valores informados são nulos ou branco.
            if (([string]::IsNullOrEmpty($userNameSource)) -or ([string]::IsNullOrEmpty($userNameTarget))) {
                Write-Warning "`nAs contas de origem e destino não podem ficam em BRANCO. Tente novamente!"
            } 
            # Testa se as contas informadas são iguais.
            elseif ($userNameSource -eq $userNameTarget) {
                Write-Warning "`nAs contas de origem e destino devem ser DIFERENTES. Tente novamente!"
            }
            else {
                try {
                    # Verifica se as contas informadas existem no Active Directory
                    $userSourceExist = Get-ADUser -Identity $userNameSource -ErrorAction Stop
                    if (-not $userSourceExist) {
                        Write-Warning "Conta de usuário <$($userNameSource)> não foi localizada no domínio $($env:USERDOMAIN)."
                    } 
                    else {
                        Write-Host "Usuário <$($userNameSource)> encontrado." -ForegroundColor Green
                    }
                    
                    $userTargetExist = Get-ADUser -Identity $userNameTarget -ErrorAction Stop
                    if (-not $userTargetExist) {
                        Write-Warning "Conta de usuário <$($userNameTarget)> não foi localizada no domínio $($env:USERDOMAIN)."
                    }
                    else {
                        Write-Host "Usuário <$($userNameTarget)> encontrado." -ForegroundColor Green
                    }

                    if ($userSourceExist -and $userTargetExist) {
                        $continueLoop = $false
                    }
                }
                catch {
                    $userSourceExist = $null
                    $userTargetExist = $null
                    Write-Host "Ocorreu um erro ao buscar o usuário: $($_.Exception.Message)" -ForegroundColor Red
                }   
            }
        }
    } 
} while ($continueLoop)


# Bloco 2: Cria pasta onde será salvo o arquivo de log e defini nome do arquivo. 
# -------------------------------------------------------------------------------------------------------------------
try {
    $currentPath = if ($PSScriptRoot) {
        # Caminho onde o arquivo .ps1 foi salvo.
        $PSScriptRoot
    }
    else {
         # Pasta atual do terminal ($PWD) caso $PSCommandPath estiver vazio.
        $currentPath = if ([string]::IsNullOrEmpty($PSCommandPath)) {
             $PWD.Path
        } 
        else { 
            Split-Path -Parent $PSCommandPath 
        }
    }

    # Remove caracteres utilizados no nome da conta.
    $userNameSourceClean = $userNameSource -replace '[\.-]', ''
    $userNameTargetClean = $userNameTarget -replace '[\.-]', ''

    # Define no caminho e nome do arquivo que será salvo.
    $logPath = Join-Path $currentPath "PSLog"
    $logFile = "Copy-Groups-$($userNameSourceClean)-$($userNameTargetClean)-$((Get-Date).ToString('yyyyMMdd-HHmmss')).log"
    $logPathFile = Join-Path $logPath $logFile

    # Cria a pasta de log, caso ela ainda não exista.
    if (-not (Test-Path $logPath -ErrorAction Stop)) {
        New-Item -ItemType Directory -Path $logPath -Force -ErrorAction Stop | Out-Null
    }
} 
catch {
    Write-Error "Erro ao criar pasta de log: $($_.Exception.Message)"
    return
}

# Bloco 3: Copia grupos da conta origem para a conta destino. 
# -------------------------------------------------------------------------------------------------------------------
try {
    $report = @()
    $countTargetGroups = 0
    $countSourceGroups = 0

    # Elimina grupos existentes na conta destino caso o usuário confirme em REMOVER.
    $inputRemoveGroups = Read-Host "`nDeseja REMOVER os grupos existente na conta <$($userNameTarget)>? (S/N)"

    if ($inputRemoveGroups -eq "sair") {
        Write-Host "Script encerrado!`n" -ForegroundColor Yellow 
        return
    }
    elseif ($inputRemoveGroups -match '^[Ss]') {
        Write-Host "`nRemovendo grupos existente da conta <$($userNameTarget)> ..." -ForegroundColor Cyan
        
        $targetGroups = @(Get-ADPrincipalGroupMembership $userNameTarget -ErrorAction Stop | Where-Object {
            $_.Name -ne "Domain Users"
        })
        
        $report += "Lista de grupos a serem removidos da conta <$($userNameTarget)>"
        $report += $targetGroups | ForEach-Object {
            "$($_.Name) | $($_.DistinguishedName)"
        }
        $report += ""

        if ($targetGroups) {
            foreach ($group in $targetGroups) {
                try {
                    Remove-ADGroupMember -Identity $group -Members $userNameTarget -Confirm:$false -ErrorAction Stop
                    $countTargetGroups++
                    $report += "Removido: $($group.Name)"
                    Write-Host "Removido: $($group.Name)"
                }
                catch {
                    $report += "Falha ao remover $($group.Name): $($_.Exception.Message)"
                    Write-Warning "Falha ao remover $($group.Name): $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Host "Nenhum grupo foi encontrado." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Grupos do usuário foram mantidos." -ForegroundColor Yellow
    }

    # Copia grupos da conta de usuário origem para conta de usuário destino. 
    Write-Host "`nCopiando grupos da conta <$($userNameSource)> para <$($userNameTarget)> ..." -ForegroundColor Cyan

    $sourceGroups = @((Get-ADUser -Identity $userNameSource -Properties MemberOf -ErrorAction Stop).MemberOf | Get-ADGroup -ErrorAction Stop)

    $report += ""
    $report += "Lista de grupos a serem adicionados na conta <$($userNameTarget)>"
    $report += $sourceGroups | ForEach-Object {
        "$($_.Name) | $($_.DistinguishedName)"
    }
    $report += ""

    if ($sourceGroups) {
        foreach ($group in $sourceGroups) {
            try {
                Add-ADGroupMember -Identity $group -Members $userNameTarget -ErrorAction Stop
                $countSourceGroups++
                $report += "Adicionado: $($group.Name)"
                Write-Host "Adicionado: $($group.Name)"
            }
            catch {
                $report += "Falha ao adicionar $($group): $($_.Exception.Message)"
                Write-Warning "Falha ao adicionar $($group): $($_.Exception.Message)"
            }
        }
        Write-Host "`nCópia concluída." -ForegroundColor Green
        $report += ""
        $report += "Grupos removidos: $($countTargetGroups)" 
        $report += "Grupos adicionados: $($countSourceGroups)"
    }
    else {
        Write-Host "Usuário <$($userNameSource)> não é membro de nenhum grupo." -foregroundColor Yellow
    }

    $report | Out-File -FilePath $logPathFile -Encoding UTF8 -ErrorAction Stop
    Write-Host "Relatório salvo em: $($logPathFile)`n" -ForegroundColor DarkGray
}
catch {
    Write-Host "Ocorreu um erro inesperado: $($_.Exception.Message)" -ForegroundColor Red
}