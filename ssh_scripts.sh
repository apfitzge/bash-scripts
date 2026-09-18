# tmux updates the attached session's environment, not existing shells.
refresh_ssh_auth_sock() {
    [[ -n ${TMUX:-} && -n ${TMUX_PANE:-} ]] || return 0
    local session value
    session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_id}' 2>/dev/null) || return 0
    value=$(tmux show-environment -t "$session" SSH_AUTH_SOCK 2>/dev/null) || return 0
    case $value in
        SSH_AUTH_SOCK=*) export SSH_AUTH_SOCK="${value#SSH_AUTH_SOCK=}" ;;
        -SSH_AUTH_SOCK) unset SSH_AUTH_SOCK ;;
    esac
    return 0
}

refresh_forwarded_ssh() {
    refresh_ssh_auth_sock
}
