function refresh_forwarded_ssh() {
    export SSH_AUTH_SOCK=$(ls -t /tmp/ssh-**/* | head -1)
}