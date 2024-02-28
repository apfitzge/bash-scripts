# run clippy and fmt checks
rust_checks() {
    cargo +nightly clippy --all-targets -- -D warnings && \
    cargo +nightly fmt --all -- --check
}

# run checks then commit with message
rust_commit() {
    if [ -z "$1" ]; then echo "Usage: rust_commit <MESSAGE>"; return -1; fi

    rust_checks && git commit -am "$1";
}

# Save criterion benchmark directory into specified parent directory
# or defaults to ./criterion-backup.
# Saved data will have the name of the crate and the commit hash.
# Usage: criterion_save [<PARENT_DIR>]
criterion_save() {
    local parent_dir
    if [ -z "$1" ]; then parent_dir="./criterion-backup"; else parent_dir="$1"; fi

    local crate_name=$(basename $(pwd))
    local commit_hash=$(git rev-parse --short HEAD)
    local save_dir="$parent_dir/$crate_name-$commit_hash"

    mkdir -p "$save_dir" && cp -r target/criterion "$save_dir"
}

# Load saved criterion benchmark data from specified directory
# or defaults to ./criterion-backup.
# Usage: criterion_load [<PARENT_DIR>]
criterion_load() {
    local parent_dir
    if [ -z "$1" ]; then parent_dir="./criterion-backup"; else parent_dir="$1"; fi

    local crate_name=$(basename $(pwd))
    local commit_hash=$(git rev-parse --short HEAD)
    local load_dir="$parent_dir/$crate_name-$commit_hash"

    if [ -d "$load_dir" ]; then
        cp -r "$load_dir/criterion" target
    else
        echo "No saved data found for $crate_name at commit $commit_hash"
    fi
}