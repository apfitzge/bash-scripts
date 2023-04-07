alias git-move-diff='git rev-parse --abbrev-ref HEAD | git show --color-moved-ws=ignore-all-space -w --patch-with-stat  --color-moved'

git_current_branch() {
    git rev-parse --abbrev-ref HEAD
}

git_commit_child() {
    if [ -z "$1" ]; then echo "Usage: git_commit_child <COMMIT>"; return -1; fi

    git rev-list HEAD~$(expr $(git rev-list --ancestry-path $1.. --count) - 1) --max-count=1
}

git_branch_point() {
    if [ -z "$1" ]; then echo "Usage: git_branch_point <MAIN_BRANCH>"; return -1; fi

    GIT_BRANCH_POINT_OG_BRANCH=$1
    GIT_BRANCH_POINT_CURRENT_BRANCH=$(git_current_branch)

    diff -u <(git rev-list --first-parent ${GIT_BRANCH_POINT_CURRENT_BRANCH}) \
             <(git rev-list --first-parent ${GIT_BRANCH_POINT_OG_BRANCH}) \
             | sed -ne 's/^ //p' | head -1
}

git_branch_squash() {
    if [ -z "$1" || -z "$2" || -z "$3" ]; then
        echo "Usage: git_branch_squash <MAIN_BRANCH> <SQUASH_DESTINATION> <SQUASH_MESSAGE>";
        return -1;
    fi

    GIT_BRANCH_SQUASH_BP=$(git_branch_point $1)
    GIT_BRANCH_SQUASH_DEST=$2

    git checkout -b $GIT_BRANCH_SQUASH_DEST
    git reset --soft $GIT_BRANCH_SQUASH_BP
    git commit -m "$3"
}

sol_commit() {
    if [ -z "$1" ]; then echo "Usage: sol_commit <MESSAGE>"; return -1; fi

    ./cargo nightly clippy --all-targets && \
    git commit -am "$1";
}

sol_merge() {
    if [ -z "$1" ]; then echo "Usage: sol_merge <GitHub PR #>"; return -1; fi

    SOL_MERGE_OG_BRANCH=$(git_current_branch)
    SOL_MERGE_MG_BRANCH=$(git_current_branch)

    if [ "$SOL_MERGE_OG_BRANCH" = "$SOL_MERGE_MG_BRANCH" ]; then
        echo "You are already on the branch for this PR. Please check out another so that the `-d` flag works correctly.";
        return 1;
    fi

    SOL_MERGE_MG_BRANCH_REBASE="${SOL_MERGE_MG_BRANCH}_rebase"
    gh pr checkout "$1" && \
    git checkout -b "$SOL_MERGE_MG_BRANCH_REBASE" \
    git fetch --all && \
    git rebase upstream/master && \
    ./cargo nightly clippy --all-targets && \
    git checkout "$SOL_MERGE_OG_BRANCH" && \
    gh pr checks "$1" && \
    gh pr merge -s -d "$1" && \
    git branch -D "$SOL_MERGE_MG_BRANCH_REBASE"
}
