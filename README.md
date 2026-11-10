# 🛠️ Meus Scripts & Utilitários Pessoais

Repositório centralizado para automação, scripts de instalação e manutenção de programas no Linux (com suporte a restauração pós-formatação).

---

## 📁 Estrutura do Repositório

```text
~/Dev/scripts/
├── antigravity/
│   ├── update-antigravity.sh    # Script de atualização do Google Antigravity
│   ├── icon2.png                # Ícone personalizado usado no lançador
│   └── Antigravity.desktop      # Atalho .desktop do Antigravity
├── crealityprint/
│   ├── extract-crealityprint.sh # Extrator e patches para o CrealityPrint (AppImage)
│   └── crealityprint.desktop    # Atalho .desktop do CrealityPrint
├── setup.sh                     # Script mestre para restauração de atalhos e links
└── README.md
```

---

## 🚀 Como Restaurar Pós-Formatação

Quando você formatar a máquina ou migrar para um novo computador, basta:

1. Clonar este repositório:
   ```bash
   git clone <URL_DO_REPOSITORIO> ~/Dev/scripts
   ```

2. Executar o script de configuração:
   ```bash
   cd ~/Dev/scripts
   ./setup.sh
   ```

O `setup.sh` criará automaticamente os links em `~/.local/bin/`, garantirá que os atalhos de menu `.desktop` e ícones estejam nos lugares certos e criará os links em `~/Programs/`.

---

## 💻 Comandos Disponíveis no Terminal

Graças aos links em `~/.local/bin/`, você pode executar os comandos de qualquer lugar:

### 1. Atualizar o Google Antigravity
```bash
# Detecta automaticamente o tar.gz mais recente em ~/Downloads
update-antigravity

# Ou passando o arquivo diretamente
update-antigravity ~/Downloads/Antigravity.tar.gz

# Reverter para a versão anterior em caso de erro
update-antigravity --rollback
```

### 2. Extrair / Gerenciar o CrealityPrint
```bash
# Extrair um AppImage baixado
extract-crealityprint ~/Downloads/CrealityPrint-V7.3.1.6378-x86_64-Release.AppImage

# Baixar e instalar a versão mais recente diretamente do GitHub
extract-crealityprint --download latest

# Definir versão padrão
extract-crealityprint --set-default V7.3.1.6378
```

---

## ☁️ Conectar a um Repositório Remoto (GitHub / Homelab)

Para subir suas alterações para a nuvem:

```bash
# No GitHub (via GitHub CLI se autenticado)
gh repo create scripts --private --source=. --remote=origin --push

# Ou manualmente via git remote
git remote add origin git@github.com:seu-usuario/scripts.git
git branch -M main
git push -u origin main
```
