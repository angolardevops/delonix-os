# DelonixOS — .zshrc por omissão
# Objectivo: um shell que já está pronto para trabalhar em k8s/IaC sem o
# utilizador ter de instalar nada. Mantém-se legível — é para ser editado.

## --- histórico ---------------------------------------------------------------
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
mkdir -p "${HISTFILE:h}"
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
setopt EXTENDED_HISTORY INC_APPEND_HISTORY

## --- comportamento -----------------------------------------------------------
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS INTERACTIVE_COMMENTS NO_BEEP
setopt PROMPT_SUBST GLOB_DOTS

## --- completação -------------------------------------------------------------
autoload -Uz compinit
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zcompdump"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'

## --- plugins (pacotes da distro, não gestor de plugins) ----------------------
[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] &&
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] &&
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

## --- teclas ------------------------------------------------------------------
bindkey -e
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

## --- ambiente ----------------------------------------------------------------
# Aplicações Qt fora do KDE (e o Plasma em Wayland) seguem o tema do sistema.
export QT_QPA_PLATFORMTHEME=kde
# GTK escuro mesmo quando o portal não está a responder.
export GTK_THEME=Breeze-Dark

export EDITOR=nvim
export VISUAL=nvim
export PAGER=less
export LESS='-R --mouse'
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export PATH="$HOME/.local/bin:$HOME/go/bin:$HOME/.cargo/bin:$PATH"

## --- linguagens (já configuradas, não é preciso mexer) ------------------------
# Go: módulos e binários dentro do HOME, cache de build partilhada.
export GOPATH="$HOME/go"
export GOBIN="$HOME/go/bin"
export GOMODCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/go/mod"
export GOTOOLCHAIN=auto        # um projecto que pede outra versão de Go busca-a
# Rust: ver ~/.cargo/config.toml (mold + sccache já ligados).
export CARGO_HOME="$HOME/.cargo"
export RUSTUP_HOME="$HOME/.rustup"
export SCCACHE_CACHE_SIZE="10G"
# Python: uv gere ambientes e versões; nada de pip global a partir root.
export UV_PYTHON_PREFERENCE=managed
export PIP_REQUIRE_VIRTUALENV=true
# Node: o nvm manda. Carregado à primeira utilização — carregá-lo em cada shell
# custa ~200 ms, e a maioria das shells nunca toca em Node.
export NVM_DIR="$HOME/.nvm"
# Delonix Runtime: os defaults já servem — DELONIX_ROOT aponta sozinho para
# ~/.local/share/delonix. Só se define aqui o que muda comportamento:
#   DELONIX_SCAN_ON_PULL=1   analisa imagens com o trivy ao descarregar
#   DELONIX_NO_CGROUP_WARN=1 cala o aviso quando não há cgroup delegado
# Containers rootless: sem daemon, sem root. Ver `delonix-doctor`.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
# `kind` sabe falar com o podman, mas só se lho dissermos — sem isto procura
# um dockerd que não existe nesta distro.
export KIND_EXPERIMENTAL_PROVIDER=podman

## --- aliases -----------------------------------------------------------------
alias ls='eza --group-directories-first --icons'
alias ll='eza -lh --git --group-directories-first --icons'
alias la='eza -lah --git --group-directories-first --icons'
alias lt='eza --tree --level=2 --icons'
alias cat='bat -pp'
alias catt='bat'
alias grep='rg'
alias df='duf'
alias du='ncdu'
alias top='btop'
alias ip='ip -c'
alias ports='ss -tulpn'
alias myip='xh -b https://ifconfig.co/json'

# git
alias g='git'
alias gs='git status -sb'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'
alias lg='lazygit'

# kubernetes
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs -f'
alias kx='kubectx'
alias kn='kubens'
alias kaf='kubectl apply -f'
alias kgp='kubectl get pods -o wide'
alias kge='kubectl get events --sort-by=.lastTimestamp'
alias ktop='kubectl top pods --sort-by=memory'

# containers (rootless)
alias d='delonix'
alias p='podman'
alias pps='podman ps -a'
# `docker` é o CLI verdadeiro a falar com o podman rootless (DOCKER_HOST acima).
# Não há dockerd a correr; se precisares mesmo dele, é um enable consciente.
alias dps='docker ps -a'

# IaC
# linguagens
alias c='cargo'
alias cb='cargo build'
alias ct='cargo test'
alias py='python'
alias uvr='uv run'
alias uvs='uv sync'

# IaC
alias tf='tofu'
alias tfp='tofu plan'
alias tfa='tofu apply'
alias ap='ansible-playbook'

# virtualização
alias vms='virsh --connect qemu:///system list --all'
alias vmstart='virsh --connect qemu:///system start'
alias vmstop='virsh --connect qemu:///system shutdown'
alias ch='cloud-hypervisor'

# `delonix update` — actualiza o sistema E o motor da casa. O runtime não tem
# esse subcomando (o `Update` que existe lá dentro é uma acção do reconciliador,
# não um comando), por isso interceptamo-lo aqui e delegamos tudo o resto no
# binário real. A verificação faz a função desaparecer sozinha no dia em que o
# runtime ganhar o seu próprio `update` — sem esconder nada de ninguém.
delonix() {
    if [[ ${1:-} == update ]] &&
       ! command delonix help 2>/dev/null | grep -qE '^[[:space:]]+update([[:space:]]|$)'; then
        shift
        command delonix-toolbox update "$@"
        return $?
    fi
    command delonix "$@"
}

# N'GolaCloud
alias dctl='delonixctl'
alias dapply='delonixctl apply -f'

## --- funções úteis -----------------------------------------------------------
# Contexto k8s + namespace de uma vez: `kctx prod kube-system`
kctx() { kubectl config use-context "$1" && [[ -n "$2" ]] && kubens "$2"; }

# Porta local para um serviço: `kpf svc/grafana 3000:80`
kpf() { kubectl port-forward "$@"; }

# Entra num pod com shell decente
kexec() { kubectl exec -it "$1" -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'; }

# Descodifica um Secret inteiro
ksecret() {
    kubectl get secret "$1" -o json |
        jq -r '.data | to_entries[] | "\(.key)=\(.value | @base64d)"'
}

# Extrai um manifesto limpo (sem campos geridos pelo servidor)
kclean() {
    kubectl get "$@" -o json |
        jq 'del(.metadata.managedFields, .metadata.resourceVersion, .metadata.uid,
                .metadata.creationTimestamp, .metadata.generation, .status)'
}

## --- ferramentas interactivas -------------------------------------------------
command -v starship >/dev/null && eval "$(starship init zsh)"
command -v zoxide   >/dev/null && eval "$(zoxide init zsh --cmd cd)"
command -v direnv   >/dev/null && eval "$(direnv hook zsh)"
command -v atuin    >/dev/null && eval "$(atuin init zsh --disable-up-arrow)"
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -r /usr/share/fzf/completion.zsh   ]] && source /usr/share/fzf/completion.zsh
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --color=fg+:#e6e8ec,hl:#e0202f,hl+:#e0202f,pointer:#e0202f,marker:#e0202f'

## --- completações de CLIs pesadas (geradas em cache) -------------------------
_delonix_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-completions"
mkdir -p "$_delonix_cache"
for _tool in kubectl helm k9s tofu argocd cosign trivy delonixctl delonix; do
    command -v "$_tool" >/dev/null || continue
    _file="$_delonix_cache/_$_tool"
    [[ -s "$_file" ]] || "$_tool" completion zsh >"$_file" 2>/dev/null
done
fpath=("$_delonix_cache" $fpath)
unset _tool _file

## --- nvm preguiçoso -----------------------------------------------------------
# Substitui `nvm`, `node`, `npm` e `npx` por stubs que carregam o nvm de
# verdade na primeira chamada e depois se apagam. Sem isto, ou o arranque da
# shell fica lento, ou o `.nvmrc` do projecto não é respeitado.
if [[ -s /usr/share/nvm/init-nvm.sh ]]; then
    _delonix_load_nvm() {
        unfunction nvm node npm npx 2>/dev/null
        source /usr/share/nvm/init-nvm.sh
    }
    for _cmd in nvm node npm npx; do
        # Depois do unfunction, o nome volta a resolver para o que o nvm
        # definiu: função (nvm) ou binário (node/npm/npx). `command` não serve
        # aqui — o próprio `nvm` é uma função de shell.
        eval "${_cmd}() { _delonix_load_nvm; ${_cmd} \"\$@\"; }"
    done
    unset _cmd
    # Respeita o .nvmrc ao entrar numa directoria de projecto.
    _delonix_nvmrc() {
        [[ -f .nvmrc ]] || return
        _delonix_load_nvm 2>/dev/null
        nvm use --silent 2>/dev/null
    }
    autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook chpwd _delonix_nvmrc
fi

## --- tmux como consola por omissão --------------------------------------------
# Toda a sessão interactiva vive dentro do tmux: um cabo que cai, um SSH que
# morre ou um terminal fechado por engano deixam de matar o que estava a correr.
# `new-session -A` liga-se à sessão existente ou cria-a — nunca duplica.
#
# Escapes: DELONIX_NO_TMUX=1 (uma vez) ou tocar em ~/.config/delonix/no-tmux.
if [[ -z ${TMUX:-} && -z ${DELONIX_NO_TMUX:-} && $- == *i* ]] &&
   [[ ! -e "$HOME/.config/delonix/no-tmux" ]] &&
   [[ $TERM != dumb && $TERM != linux ]] &&
   command -v tmux >/dev/null; then
    exec tmux new-session -A -s delonix
fi

## --- local (não versionado) ---------------------------------------------------
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
