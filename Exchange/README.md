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

### 2. 📄 Nome-Do-Segundo-Script.ps1
* **Descrição:** Breve explicação do que o segundo script faz.
* **Versão:** `1.0.0`
* **Como Executar:**
  ```powershell
  .\Nome-Do-Segundo-Script.ps1 -Parametro X
  ```

---

