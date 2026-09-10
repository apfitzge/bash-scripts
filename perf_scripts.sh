function get_thread_pid() {
    local thread_name="$1"
    ps -eL | grep -w "$thread_name" | awk '{print $2}' | head -n 1
}

function profile_env() {
    export RUSTFLAGS="-C debuginfo=2 -C force-frame-pointers=yes"
    export CFLAGS="-fno-omit-frame-pointer -g"
    export CXXFLAGS="-fno-omit-frame-pointer -g"
}