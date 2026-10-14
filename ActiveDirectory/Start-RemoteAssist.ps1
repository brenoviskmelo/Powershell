<#
.SYNOPSIS
    Promover assistência remota a usuários, em ambiente corporativo, que utilizam Ambiente de Trabalho Remoto.

.DESCRIPTION
    Atenção:
        Executar script com privilégios administrativos no servidor de destino para assumir o controle da sessão.
    
    Contexto:
        Usuários com sessões RDP iniciadas em um Pool de Host Sessions, distribuídas por um Broker Server.
    
    Destaques:
        1. Script solicita conta do usuário da rede, sessão é localizada em um dos servidores e assistência remota iniciada.
        2. Script não é encerrado ao fim de uma assistência, permitindo início de nova assistência em sequência.
        3. As assistências são registradas em arquivos de log.

.VERSION
    1.0.0

.NOTES
    Autor : Breno Melo
    E-mail: bmmelo@hotmail.com

    Histórico de alterações:
        v1.0.0. (11/09/2026) - Criação do script.
#>

# Bloco 1: Define caminho, nome do arquivo de log e cria pasta para os logs.
# -------------------------------------------------------------------------------------------------------------------
$logPath = "$PSScriptRoot\PSLog"
$logFile = "Start-RemoteAssist_$((Get-Date).ToString('yyyyMMdd_HHmmss')).log"
$logPathFile = Join-Path $logPath $logFile

try {
    # Cria a pasta de log, caso ela ainda não exista.
    if (-not (Test-Path $logPath -ErrorAction Stop)) {
        New-Item -ItemType Directory -Path $logPath -Force -ErrorAction Stop | Out-Null
    }
} catch {
    Write-Error "Erro ao criar pasta de log: $($_.Exception.Message)"
    return
}


# Registra no arquivo de log eventos que são passados como parâmetro, com data e hora que ocorrem.
function Write-Log {
    param(
        [string]$level, 
        [string]$message
    )
    $currentDateTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    "$($currentDateTime) [$($level)] $($message)" | Out-File -Append -FilePath $logPathFile -Encoding utf8

    if ($level -eq "F") {
        "----------------------------------------------------------------------------------" |
        Out-File -Append -FilePath $logPathFile -Encoding utf8
    }
}

# ----------------------------------------------------------------------------------------------------------------------

$countSession = 1

# Lista de servidores para localizar a sessão do usuário.
$servidores = @("f10ts01", "f10ts02")

while ($true) {
    # Solicita o nome do usuário com instrução de saída.
    Write-Host "`nAssistência Remota | Sessão $countSession" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Digite 'sair' a qualquer momento para fechar o script." -ForegroundColor DarkGray
   
    $userName = Read-Host -Prompt "`nIntroduza a conta do usuário (ex: administ.marf)"
    $userName = $userName.Trim()

    # Verifica se o usuário deseja sair do script.
    if ($userName -eq "sair") {
        Write-Log "F" "Script encerrado pelo usuário"
        Write-Host  "`nScript encerrado pelo usuário" -ForegroundColor Yellow
        Write-Host "`n"
        Break
    }

    # Valida se o nome do usuário informado está em branco.
    if ([string]::IsNullOrWhiteSpace($userName)) {
        Write-Host "O nome não pode estar em branco. Tente novamente." -ForegroundColor Yellow
        Continue # Volta ao início do ciclo while e pede o nome outra vez
    }

    $sessaoEncontrada = $false
    
    Write-Log "S" "Iniciando Assistência Remota | Sessão $countSession"
    Write-Log "I" "Procurando a sessão do usuário $userName nos servidores..."
    Write-Host  "`nProcurando a sessão do usuário $userName nos servidores..." -ForegroundColor Cyan

    # Percorrer a lista de servidores
    foreach ($servidor in $servidores) {
        Write-Host "Verificando $servidor..." -ForegroundColor Gray
        
        # Executa o comando query user filtrando pelo utilizador
        $resultado = query user $userName /server:$servidor 2>$null
        
        if ($resultado) {
            foreach ($linha in $resultado) {
                # Ignora a linha de cabeçalho do comando
                if ($linha -match "UTILIZADOR" -or $linha -match "USERNAME") { continue }
                
                # Divide a linha por múltiplos espaços em branco
                $colunas = $linha -split '\s+' | Where-Object { $_ -ne "" }
                
                # Localiza o usuário como um campo completo, removendo o marcador da sessão ativa.
                $indiceUsuario = -1
                for ($indiceColuna = 0; $indiceColuna -lt $colunas.Count; $indiceColuna++) {
                    if (($colunas[$indiceColuna] -replace '^>', '') -ieq $userName) {
                        $indiceUsuario = $indiceColuna
                        break
                    }
                }

                if ($indiceUsuario -ge 0) {
                    # O ID é o primeiro campo numérico depois do usuário e do nome da sessão.
                    $idSessao = $null
                    $indiceIdSessao = -1
                    for ($indiceColuna = $indiceUsuario + 1; $indiceColuna -lt $colunas.Count; $indiceColuna++) {
                        if ($colunas[$indiceColuna] -match '^\d+$') {
                            $idSessao = $colunas[$indiceColuna]
                            $indiceIdSessao = $indiceColuna
                            break
                        }
                    }

                    $logonTime = 'Indisponível'
                    $indiceLogonTime = $indiceIdSessao + 3
                    if ($indiceIdSessao -ge 0 -and $indiceLogonTime -lt $colunas.Count) {
                        $logonTime = $colunas[$indiceLogonTime..($colunas.Count - 1)] -join ' '
                    }
                    
                    if ($idSessao) {
                        $sessaoEncontrada = $true

                        # Exibe os dados da sessão encontrada.
                        Write-Host "`nSessão encontrada!" -ForegroundColor Cyan
                        Write-Host "Servidor........: $servidor"  -ForegroundColor Gray
                        Write-Host "ID da Sessão....: $idSessao"  -ForegroundColor Gray
                        Write-Host "Início da Sessão: $logonTime" -ForegroundColor Gray
                        Write-Log  "I" "Sessão encontrada em $servidor ID $idSessao TL $logonTime"
                                               
                        # Iniciar a sessão RDP Shadow com o /no_consent_prompt incluído
                        Write-Log  "I" "Iniciando a ligação remota shadow..." 
                        Write-Host "`nIniciando a ligação remota shadow..." -ForegroundColor Yellow
                        Write-Host "`n"
                        
                        try {
                            # Inicia o processo mstsc
                            $statusProcesso = Start-Process -FilePath "mstsc.exe" -ArgumentList "/v:$servidor /shadow:$idSessao /control /noconsentprompt" -PassThru -ErrorAction Stop
                            
                            Write-Log "I" "Ligação remota iniciada com ID $($statusProcesso.Id) processo $($statusProcesso.ProcessName)" 
                            
                            # Aguarda processo até ser encerrado
                            $statusProcesso.WaitForExit()    
                            
                            # Registra dados da sessão no log e trata erros caso ocorram
                            if ($statusProcesso.ExitCode -eq 0) {
                                $statusProcesso.Refresh()

                                Write-Log "I" "Tempos de sessão $($statusProcesso.StartTime) - $($statusProcesso.ExitTime)"
                                Write-Log "F" "Conexão remota com $($userName) encerrada."
                                Write-Host "Conexão remota com $($userName) encerrada."
                                
                                $countSession += 1

                            } else {
                                Write-Log "E" "mstsc.exe terminou com código de saída $($statusProcesso.ExitCode)"
                                Write-Host "A ligação remota terminou com código de saída $($statusProcesso.ExitCode)." -ForegroundColor Red
                            }
                        } catch {
                            Write-Log "E" "Não foi possível iniciar ligação. Erro: $($_.Exception.Message)"
                        }
                        
                        break
                    }
                }
            }
        }
        
        if ($sessaoEncontrada) { break }
    }
    
    if (-not $sessaoEncontrada) {
        Write-Log "F" "Nenhuma sessão ativa foi encontrada para o usuário $userName"
        Write-Host  "`nNenhuma sessão ativa foi encontrada para o usuário $userName" -ForegroundColor Red
    }
}