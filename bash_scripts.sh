function repeat_until_failure() {
    local cmd="$@"

    while $cmd; do
        echo "success"
    done
}

function repeat_up_to_n_times() {
    local n=$1
    shift
    local cmd="$@"

    for ((i = 1; i <= n; i++)); do
        $cmd || return 1
    done
    return 0
}