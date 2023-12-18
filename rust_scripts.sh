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