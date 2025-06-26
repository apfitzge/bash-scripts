function get_thread_pid() {
    local thread_name="$1"
    ps -eL | grep -w "$thread_name" | awk '{print $2}' | head -n 1
}
