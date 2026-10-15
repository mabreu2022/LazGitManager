# Manual de Uso do Componente LazGitHubIntegration

**Plugin de Integração Git e GitHub para o Lazarus IDE (3.0+)**  
*Desenvolvido em Free Pascal / LCL sob `{$mode objfpc}{$H+}`*

---

## 1. Visão Geral

O **LazGitHubIntegration** é um pacote de tempo de design (`.lpk`) para o Lazarus IDE que integra nativamente o controle de versão local **Git** e a **API REST do GitHub** diretamente no ambiente de desenvolvimento.

### Principais Características
* **Zero Dependências em C:** Não requer DLLs externas instáveis como `libgit2.dll`. Executa o Git de forma segura via CLI (`TProcess`) e conecta à API do GitHub usando `fphttpclient` e `opensslsockets`.
* **Painel Acoplável (Dockable Window):** Totalmente compatível com **AnchorDocking** e o **DockedFormEditor**, podendo ser fixado em qualquer área do IDE (ao lado do Inspetor de Objetos, Editor de Código ou Mensagens).
* **Autenticação Real com GitHub:** Conecta diretamente à API REST oficial do GitHub (`https://api.github.com`), validando seu *Personal Access Token* (PAT), exibindo dados de perfil, listando repositórios e permitindo abrir **Issues** e **Pull Requests**.
* **Trabalho Seguro e Assíncrono:** Os comandos do Git não travam a interface do Lazarus, capturando tanto a saída padrão (`stdout`) quanto mensagens de erro (`stderr`) em tempo real.
* **Segurança contra Falhas (Null-Safe):** Se nenhum projeto estiver aberto, o plugin desabilita as ações com avisos amigáveis em vez de gerar erros de *Access Violation*.

---

## 2. Autenticação Real com o GitHub: Como Funciona?

### ❓ O plugin tem autenticação real com o GitHub?
**SIM, a autenticação é 100% REAL e direta com os servidores do GitHub.**

### Como a autenticação é processada:
1. O plugin utiliza o protocolo HTTPS com criptografia TLS 1.2/1.3 nativa (`opensslsockets`).
2. Todas as requisições para a API REST oficial (`https://api.github.com`) incluem os seguintes cabeçalhos padrão recomendados pelo GitHub:
   ```http
   Accept: application/vnd.github+json
   X-GitHub-Api-Version: 2022-11-28
   User-Agent: LazGitHub-Plugin
   Authorization: Bearer <SEU_TOKEN_PAT>
   ```
3. Ao clicar em **"Test Connection"** (nas Opções do IDE) ou **"Connect / Verify"** (no painel acoplado):
   * O plugin faz uma requisição `GET` ao endpoint `https://api.github.com/user`.
   * **Se o token for válido (HTTP 200):** O GitHub retorna os dados reais da sua conta (nome de usuário, ID, repositórios, limites de taxa). O plugin extrai seu `@username` e exibe como conectado.
   * **Se o token for inválido, vencido ou revogado:** A API retorna `HTTP 401 Unauthorized` ou `HTTP 403 Forbidden` com uma mensagem de erro JSON oficial do GitHub (ex: *"Bad credentials"*, *"API rate limit exceeded"*), que o plugin exibe detalhadamente.
4. **Armazenamento Seguro:** O token PAT é persistido no arquivo de configuração do usuário (`lazgithub.xml`) dentro da pasta de configurações do Lazarus (`%APPDATA%\lazarus` no Windows ou `~/.lazarus` no Linux), nunca sendo compartilhado externamente.

### Como gerar seu Token no GitHub (PAT):
1. Acesse o GitHub: [https://github.com/settings/tokens](https://github.com/settings/tokens).
2. Clique em **Generate new token** -> **Generate new token (classic)**.
3. Defina um nome (ex: `Lazarus-IDE-Plugin`) e o período de expiração.
4. Marque os escopos necessários:
   * `repo` (Acesso completo a repositórios privados e públicos: commits, branches, issues e pull requests).
   * `read:org` (Leitura de organizações, caso trabalhe em times).
   * `read:user` ou `user:email` (Para carregar dados do seu perfil).
5. Clique em **Generate token** e copie a chave gerada (iniciada por `ghp_...`).

---

## 3. Requisito de OpenSSL no Windows

Para efetuar requisições HTTPS nativas com o Free Pascal (`opensslsockets`) no Windows, o sistema necessita das bibliotecas de tempo de execução do OpenSSL (64 bits se seu Lazarus for 64 bits):
* `libssl-1_1-x64.dll`
* `libcrypto-1_1-x64.dll`
*(ou versões equivalentes `libssl-3-x64.dll` / `libcrypto-3-x64.dll` presentes em distribuições do Git for Windows ou MySQL).*

> **Dica:** Se já tiver o Git for Windows instalado, você já possui essas DLLs em `C:\Program Files\Git\mingw64\bin`. Para que o Lazarus as encontre, basta que esse diretório esteja no `PATH` do Windows, ou você pode copiar as DLLs para a pasta raiz do Lazarus (`C:\lazarus`).

---

## 4. Instalação no Lazarus IDE

### Método 1: Automático via Linha de Comando (`lazbuild`)
Se você estiver no terminal na pasta do projeto:
```powershell
C:\lazarus\lazbuild.exe --add-package "d:\Fontes Lazarus\OTA GIT Lazarus\lazgithubintegration.lpk"
C:\lazarus\lazbuild.exe --build-ide=
```
O Lazarus recompilará o executável do IDE já com o pacote embutido.

### Método 2: Pela Interface Gráfica do Lazarus (Passo a Passo)
1. Abra o **Lazarus IDE**.
2. No menu superior, vá em **Pacote > Abrir Arquivo de Pacote (.lpk)...** (Package > Open Package File).
3. Navegue até a pasta:  
   `D:\Fontes Lazarus\OTA GIT Lazarus\`  
   e selecione o arquivo **`lazgithubintegration.lpk`**.
4. Na janela do Gerenciador de Pacotes que abrir:
   * Clique em **Compilar** (Compile) para confirmar a compilação.
   * Clique no botão **Usar > Instalar** (Use > Install).
5. O Lazarus perguntará se deseja recompilar o IDE. Clique em **Sim** (Yes).
6. Aguarde alguns segundos enquanto o IDE é recompilado e reiniciado automaticamente.

---

## 5. Guia Passo a Passo de Uso

### 1. Configurando o Plugin
1. No menu principal do Lazarus, vá em **Ferramentas > Opções...** (Tools > Options).
2. Na árvore de categorias à esquerda, localize **Ambiente > GitHub Integration** (ou **Environment > GitHub Integration**).
   *(Dica: Você também pode abrir essa tela diretamente abrindo o painel do plugin com `Ctrl+Alt+G` e clicando no botão **Settings...**)*
3. Configure os parâmetros:
   * **Git Executable Path:** Caminho do executável do Git (padrão: `git`, ou aponte para `C:\Program Files\Git\cmd\git.exe` usando o botão *Browse...*).
   * **Auto-Fetch Interval:** Intervalo em minutos para verificação automática de alterações remotas (coloque `0` para desativar).
   * **Personal Access Token:** Cole seu token PAT gerado no GitHub.
4. Clique no botão **Test Connection**:
   * O plugin fará a autenticação em tempo real com o GitHub.
   * Se os dados estiverem corretos, uma mensagem verde exibirá:  
     `Success! Authenticated as @seu_usuario`.
5. Clique em **OK** para salvar as configurações.

---

### 2. Abrindo o Painel do Git & GitHub
Você pode abrir a janela do gerenciador de duas formas:
* Pelo atalho do teclado: **`Ctrl + Alt + G`**
* Pelo menu: **Exibir > Git & GitHub Manager** (View > Git & GitHub Manager).

> **Recurso de Docking:** Arraste a aba da janela para acoplá-la em qualquer divisão da sua área de trabalho do Lazarus (por exemplo, ao lado da lista de Mensagens ou do Editor de Código). O layout é lembrado automaticamente nas próximas sessões.

---

### 3. Gerenciando Alterações Locais (Aba "Git Changes")

1. **Barra Superior de Status:**
   * **Branch:** Mostra a branch ativa atual do projeto (ex: `main`, `develop`).
   * **Project:** Exibe o arquivo de projeto `.lpi` atualmente aberto no Lazarus.
   * **GitHub:** Mostra o status da conexão (`@usuario` ou `Disconnected`).
2. **Lista de Arquivos:**
   * Exibe todos os arquivos modificados (`Modified`), novos não rastreados (`Untracked`), adicionados (`Added`) ou excluídos (`Deleted`).
   * **Checkboxes Interativas:**
     * Ao **marcar** um checkbox de um arquivo: executa `git add` no arquivo (Stage).
     * Ao **desmarcar** o checkbox: executa `git reset HEAD` no arquivo (Unstage).
3. **Menu de Contexto (Botão Direito do Mouse):**
   * **Stage Selected:** Adiciona o arquivo selecionado ao índice.
   * **Unstage Selected:** Remove o arquivo selecionado do índice de commit.
   * **View Diff:** Exibe o diff unificado das alterações no painel de log inferior.
   * **Discard Changes:** Descarta modificações locais no arquivo (solicita confirmação).
   * **Stage All / Unstage All:** Prepara ou desfaz o preparo de todos os arquivos de uma só vez.
4. **Realizando Commits:**
   * Digite a mensagem de commit no campo **Commit Message**.
   * Clique em **Commit** para efetuar o commit local.
   * Ou clique em **Commit & Push** para commitar e já enviar imediatamente para o repositório remoto (`origin`).

---

### 4. Operações Remotas no GitHub (Aba "GitHub Remote")

1. **Detecção Automática de Repositório:**
   * Se o projeto aberto possuir uma URL remota configurada no Git (`remote.origin.url`), o plugin detecta automaticamente o `dono/repositorio` e preenche o seletor.
2. **Conectar / Listar Repositórios:**
   * Clique em **Connect / Verify** para carregar a lista de até 30 repositórios mais recentes da sua conta no seletor suspenso.
3. **Criando uma Nova Issue:**
   * Abra a sub-aba **New Issue**.
   * Digite o **Title** (Título) e o **Body** (Descrição detalhada do bug ou feature).
   * Clique em **Create Issue**. A issue será publicada instantaneamente no GitHub.
4. **Criando um Pull Request:**
   * Abra a sub-aba **New Pull Request**.
   * **Head Branch:** Branch de origem com suas alterações (preenchida automaticamente com a branch ativa).
   * **Base Branch:** Branch de destino que receberá o merge (padrão: `main`).
   * Digite o **Title** e a descrição.
   * Clique em **Create Pull Request**. O PR será aberto diretamente no repositório remoto.

---

### 5. Atalho no Menu de Projeto
No menu **Projeto > Git Commit Active Project...**:
* Abre instantaneamente o painel do Git e posiciona o foco no campo de mensagem de commit do projeto ativo.
* Se nenhum projeto estiver aberto, o Lazarus exibe um aviso amigável solicitando a abertura de um projeto antes.

---

## 6. Estrutura dos Arquivos do Código-Fonte

| Arquivo | Função / Responsabilidade |
| :--- | :--- |
| `LazGitHubConfig.pas` | Gerenciamento e persistência das configurações (`lazgithub.xml`) via `GetIDEConfigStorage`. |
| `LazGitHubAPI.pas` | Cliente HTTPS REST para comunicação com `api.github.com` via `fphttpclient` e `fpjson`. |
| `LazGitCLI.pas` | Motor de execução de comandos do Git local via `TProcess` com captura assíncrona de logs. |
| `LazGitDockForm.pas` / `.lfm` | Formulário visual acoplável contendo as abas de Git Changes, GitHub Remote e Log. |
| `LazGitHubOptionsFrame.pas` / `.lfm` | Frame integrado na tela de Opções do Lazarus (**Ferramentas > Opções > Ambiente > GitHub Integration**). |
| `LazGitHubRegistration.pas` | Registra as janelas dockáveis (`IDEWindowCreators`), menus e comandos de teclado (`Ctrl+Alt+G`). |
| `lazgithubintegration.lpk` | Descritor XML oficial do pacote para o instalador do Lazarus. |

---

## 7. Solução de Problemas (Troubleshooting)

### "No active project loaded in Lazarus IDE"
* **Causa:** Nenhuma aplicação ou projeto (`.lpi`) está atualmente aberto no Lazarus.
* **Solução:** Abra um projeto pelo menu **Projeto > Abrir Projeto...** que esteja versionado com Git.

### "Failed to launch Git process"
* **Causa:** O executável do Git não foi localizado no `PATH` do sistema.
* **Solução:** Acesse **Ferramentas > Opções > Ambiente > GitHub Integration**, clique em *Browse...* e aponte para o arquivo `git.exe` (exemplo: `C:\Program Files\Git\cmd\git.exe`).

### "HTTPS Connection error"
* **Causa:** O Windows não localizou as DLLs do OpenSSL (`libssl-1_1-x64.dll` e `libcrypto-1_1-x64.dll`).
* **Solução:** Certifique-se de que o diretório do Git (`C:\Program Files\Git\mingw64\bin`) está no `PATH` do Windows, ou copie essas duas DLLs para a pasta onde o Lazarus está instalado (`C:\lazarus`).

### "GitHub Error (401): Bad credentials"
* **Causa:** O token PAT digitado está incorreto, foi revogado ou expirou.
* **Solução:** Gere um novo token clássico no GitHub com os escopos `repo` e atualize nas opções do IDE.
