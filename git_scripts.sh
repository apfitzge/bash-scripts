alias git-move-diff='git rev-parse --abbrev-ref HEAD | git show --color-moved-ws=ignore-all-space -w --patch-with-stat  --color-moved'

# Get the current commit hash
git_current_commit() {
    git rev-parse HEAD
}

# Get the current branch name
git_current_branch() {
    git rev-parse --abbrev-ref HEAD
}

# Get the child of a commit on the current branch
git_commit_child() {
    if [ -z "$1" ]; then echo "Usage: git_commit_child <COMMIT>"; return -1; fi

    git rev-list HEAD~$(expr $(git rev-list --ancestry-path $1.. --count) - 1) --max-count=1
}

# Determine the first common commit between the current branch and the input branch
git_branch_point() {
    if [ -z "$1" ]; then echo "Usage: git_branch_point <MAIN_BRANCH>"; return -1; fi

    GIT_BRANCH_POINT_OG_BRANCH=$1
    GIT_BRANCH_POINT_CURRENT_BRANCH=$(git_current_branch)
    diff -u <(git rev-list --first-parent ${GIT_BRANCH_POINT_CURRENT_BRANCH}) \
             <(git rev-list --first-parent ${GIT_BRANCH_POINT_OG_BRANCH}) \
             | sed -ne 's/^ //p' | head -1
}

# Squash all commits on the current branch (from branching point off of the input branch) into a single commit
# with the provided message.
git_branch_squash() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: git_branch_squash <MAIN_BRANCH> <SQUASH_MESSAGE>";
        return -1;
    fi

    GIT_BRANCH_SQUASH_OG_BRANCH=$(git_current_branch)
    GIT_BRANCH_SQUASH_BP=$(git_branch_point $1)
    GIT_BRANCH_SQUASH_DEST="$GIT_BRANCH_SQUASH_OG_BRANCH-squishy-squashy"

    git checkout -b $GIT_BRANCH_SQUASH_DEST && \
    git reset --soft $GIT_BRANCH_SQUASH_BP && \
    git commit -m "$2" && \
    COMMIT=$(git_current_commit) && \
    git checkout $GIT_BRANCH_SQUASH_OG_BRANCH && \
    git branch -D $GIT_BRANCH_SQUASH_DEST && \
    echo "Squashed commit: $COMMIT"
}

# Check if a branch exists
git_branch_exists() {
    if [ -z "$1" ]; then echo "Usage: git_branch_exists <BRANCH>"; return -1; fi
    git rev-parse --verify --quiet $1 > /dev/null
}

# Check if there are diffs
git_has_diffs() {
    git diff-index --exit-code --ignore-submodules HEAD || return 1;
}

git_stash_if_diff() {
    if ! git_has_diffs; then
        git stash
        return 1
    else
        return 0
    fi
}

git_worktree_setup() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        echo "Usage: git_worktree_setup <NAME> <REPO> <INITIAL-BRANCH>";
        return -1;
    fi

    GIT_WORKTREE_SETUP_NAME=$1
    GIT_WORKTREE_SETUP_REPO=$2
    GIT_WORKTREE_SETUP_BRANCH=$3

    mkdir ${GIT_WORKTREE_SETUP_NAME} && \
    cd ${GIT_WORKTREE_SETUP_NAME} && \
    git clone --bare ${GIT_WORKTREE_SETUP_REPO} .git && \
    cd .git && \
    git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' && \
    git worktree add ../worktrees/${GIT_WORKTREE_SETUP_BRANCH} ${GIT_WORKTREE_SETUP_BRANCH} && \
    cd ../../
}

git_worktree_base() {
    dirname $(git rev-parse --git-common-dir)
}

# Create a new worktree w/ the provided branch name.
# Creates the branch if it does not already exist.
git_worktree_new() {
    if [ -z "$1" ]; then echo "Usage: git_worktree_new <BRANCH>"; return -1; fi

    GIT_WORKTREE_NEW_BRANCH=$1
    GIT_WORKTREE_NEW_BASE=$(git_worktree_base)/worktrees

    if git_branch_exists ${GIT_WORKTREE_NEW_BRANCH}; then
        git worktree add ${GIT_WORKTREE_NEW_BASE}/${GIT_WORKTREE_NEW_BRANCH} ${GIT_WORKTREE_NEW_BRANCH}
    else
        git worktree add ${GIT_WORKTREE_NEW_BASE}/${GIT_WORKTREE_NEW_BRANCH} -b ${GIT_WORKTREE_NEW_BRANCH}
    fi
}

# Open a new worktree for a PR number.
gh_pr_worktree() {
    if [ -z "$1" ]; then echo "Usage: gh_worktree_new <PR_NUMBER>"; return -1; fi

    GH_WORKTREE_NEW_PR=$1
    GH_WORKTREE_NEW_BASE=$(git_worktree_base)/worktrees
    temp_branch="temp-branch-$(date +%Y%m%d%H%M%S)"

    git worktree add ${GH_WORKTREE_NEW_BASE}/${GH_WORKTREE_NEW_PR} -b ${temp_branch}

    if [ $? -eq 0 ]; then
        cd ${GH_WORKTREE_NEW_BASE}/${GH_WORKTREE_NEW_PR}
        gh pr checkout ${GH_WORKTREE_NEW_PR}
        cd -
        git branch -D ${temp_branch}
    else
        git worktree remove ${GH_WORKTREE_NEW_BASE}/${GH_WORKTREE_NEW_PR}
    fi
}
