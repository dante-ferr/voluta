# Interactive tools must never run during graphical login.
[[ -o interactive ]] || return
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
_voluta_config="${XDG_CONFIG_HOME:-$HOME/.config}"
[[ -r "$_voluta_config/voluta-login-env.sh" ]] && source "$_voluta_config/voluta-login-env.sh"
if command -v voluta >/dev/null 2>&1 && voluta enabled developer_shell; then
    [[ -r "$_voluta_config/voluta/shell/interactive.zsh" ]] && source "$_voluta_config/voluta/shell/interactive.zsh"
else
    command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
fi
unset _voluta_config
