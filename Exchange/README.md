# 📂 Scripts do Exchange Online

Esta pasta contém ferramentas e scripts de automação PowerShell para a administração do Exchange Online.

## 🔒 Pré-requisitos Gerais
* Módulo `ExchangeOnlineManagement` instalado.
  ```powershell
  Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser
  ```

## 🛠️ Scripts Disponíveis

### 1. 📄 Get-ExchArchiveMailbox.ps1
* **Descrição:** Conecta-se ao Exchange Online e gera um relatório de uso das caixas de correio com Archive ativado.
* **Versão:** `1.1.1`
* **Como Executar:**
  ```powershell
  .\Get-ExchArchiveMailbox.ps1
  ```
  ## 🔒 Pré-requisitos
  - Windows PowerShell ou PowerShell com suporte ao módulo Exchange Online Management.
  - Permissão para instalar o módulo, caso ele ainda não esteja presente, e acesso à PowerShell Gallery.
  - Uma conta autorizada a conectar-se ao Exchange Online e consultar caixas de correio e estatísticas.
  - `Out-GridView` para a janela interativa. Se não estiver disponível ou ocorrer erro ao abri-lo, o script avisa e ainda tenta exportar o CSV.

---

### 2. 📄 Get-ExchSizeFolderReport.ps1
* **Descrição:** Conecta-se ao Exchange Online e gera um relatório do tamanho das pastas de uma caixa de correio, incluindo o Archive quando estiver habilitado.
* **Versão:** `1.0.0`
* **Como Executar:**
  ```powershell
  .\Get-ExchSizeFolderReport.ps1
  ```
* **Funcionamento:** Solicita a conta usada para conectar ao Exchange Online e o endereço da caixa a consultar. Exibe os resultados em `Out-GridView` e salva o CSV na pasta `PSReport`, junto ao script.
* **Pré-requisitos:**
  - Módulo `ExchangeOnlineManagement`, instalado pelo script se necessário; é preciso acesso à PowerShell Gallery para instalar ou atualizar o módulo.
  - Conta autorizada a conectar-se ao Exchange Online e consultar as estatísticas da caixa de correio informada.
  - `Out-GridView` para a visualização interativa. Se não estiver disponível ou falhar, o script avisa e continua tentando exportar o CSV.

---

