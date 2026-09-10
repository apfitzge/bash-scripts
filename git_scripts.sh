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

# For all worktrees runt he provided command.
git_worktree_for_all() {
    GIT_WORKTREE_FOR_ALL_COMMAND=$@
    GIT_WORKTREE_FOR_ALL_BASE=$(git_worktree_base)/worktrees

    for d in ${GIT_WORKTREE_FOR_ALL_BASE}/*; do
        if [ -d "$d" ]; then
            cd $d
            $GIT_WORKTREE_FOR_ALL_COMMAND
            cd - > /dev/null
        fi
    done

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

git_list_unpushed_branches() {
    # Fetch all remote branches
    git fetch --all

    # List local branches that are not pushed to the remote
    for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
        if ! git show-ref --quiet refs/remotes/origin/$branch; then
            echo $branch
        fi
    done
}

# Rebase a long-lived fork branch, retaining snapshots for review across shells.
git_fork_rebase() {
    local action=${1:-help} id=${2:-} common state refs branch temp old base upstream tip published path status
    local remote onto_remote onto_branch onto=upstream/master
    case "$action" in
        help|-h|--help)
            cat <<'HELP'
Usage: git_fork_rebase start <source-remote>/<branch> [--onto <base-remote>/<branch>]
       git_fork_rebase review <session> [output-file]
       git_fork_rebase publish <session>
       git_fork_rebase finalize <session>
       git_fork_rebase cleanup <session>
Example: git_fork_rebase start block-production/my-feature --onto upstream/master
The base defaults to upstream/master. Start fetches both remotes and rebases onto
the saved base tip (linearizes merge commits). Keep the printed session ID.
Publish and finalize use the saved source remote. Remote names cannot contain /.
Resolve conflicts manually, then use git rebase --continue in that worktree.
Review uses saved refs, regardless of HEAD. Re-review and re-publish after edits.
Range-diff compares per-commit patches; context noise is possible, and it does
not isolate conflict resolutions. An optional PR is only for discussion/approval
and must be closed without merging. No PR is created automatically.
Finalize requires publication and replaces the maintained branch with an exact
original-tip force-with-lease. Cleanup after success retains checked-out local
branches and remote review branches; cleanup can be retried after switching away.
HELP
            return 0 ;;
        start|review|publish|finalize|cleanup) ;;
        *) echo "Unknown action: $action" >&2; return 1 ;;
    esac
    if [ "$action" = start ]; then
        if [ "$#" -eq 4 ] && [ "$3" = --onto ] && [ -n "$4" ]; then
            onto=$4
        elif [ "$#" -ne 2 ]; then
            echo "Usage: git_fork_rebase start <source-remote>/<branch> [--onto <base-remote>/<branch>]" >&2
            return 1
        fi
    elif [ "$#" -gt 3 ] || { [ "$#" -eq 3 ] && [ "$action" != review ]; }; then
        echo "See: git_fork_rebase help" >&2; return 1
    fi
    if [ -z "$id" ]; then
        echo "See: git_fork_rebase help" >&2; return 1
    fi
    common=$(git rev-parse --path-format=absolute --git-common-dir) || return 1
    # Rebase state is per-worktree; check every registered worktree, not just HEAD.
    for path in "$common" "$common"/worktrees/*; do
        if [ -d "$path/rebase-merge" ] || [ -d "$path/rebase-apply" ] || [ -f "$path/MERGE_HEAD" ]; then
            echo "Finish or abort the merge/rebase before using this command." >&2; return 1
        fi
    done
    if [ "$action" = start ]; then
        remote=${id%%/*}
        branch=${id#*/}
        onto_remote=${onto%%/*}
        onto_branch=${onto#*/}
        if [ "$remote" = "$id" ] || [ "$onto_remote" = "$onto" ] ||
            [ -z "$remote" ] || [ -z "$onto_remote" ] ||
            [[ "$remote" = -* || "$onto_remote" = -* ]]; then
            echo "Specify source and base as remote/branch (remote names cannot contain /)." >&2; return 1
        fi
        git check-ref-format "refs/heads/$branch" || return 1
        git check-ref-format "refs/heads/$onto_branch" || return 1
        git remote get-url "$remote" > /dev/null || return 1
        git remote get-url "$onto_remote" > /dev/null || return 1
        status=$(git status --porcelain --untracked-files=all) || return 1
        if [ -n "$status" ]; then
            echo "A clean working tree (including untracked files) is required." >&2; return 1
        fi
        git fetch "$remote" || return 1
        git fetch "$onto_remote" || return 1
        # Explicit fetches also handle remotes with restricted fetch refspecs.
        git fetch "$remote" "refs/heads/$branch" || return 1
        old=$(git rev-parse --verify FETCH_HEAD) || return 1
        git fetch "$onto_remote" "refs/heads/$onto_branch" || return 1
        upstream=$(git rev-parse --verify FETCH_HEAD) || return 1
        base=$(git merge-base "$old" "$upstream") || return 1
        state=$(mktemp -d "$common/fork-rebase.XXXXXXXXXX") || return 1
        id=${state##*/}
        refs="refs/fork-rebase/$id"
        temp=$id
        printf '%s\n' "$branch" > "$state/branch" || return 1
        printf '%s\n' "$remote" > "$state/remote" || return 1
        printf '%s\n' "$onto" > "$state/onto" || return 1
        git update-ref --stdin <<REFS || return 1
start
create $refs/old $old
create $refs/base $base
create $refs/upstream $upstream
prepare
commit
REFS
        # Append one final exec, so aborting cannot masquerade as completion.
        printf '#!/bin/sh\nprintf "\\nexec git update-ref %s/completed HEAD\\n" >> "$1"\n' "$refs" > "$state/sequence-editor" || return 1
        git checkout -b "$temp" "$old" || return 1
        echo "Session: $id"
        echo "Source: $remote/$branch; base: $onto_remote/$onto_branch ($upstream)"
        echo "Review: git_fork_rebase review $id [output-file]"
        echo "Optional PR: discussion/approval only; close it without merging."
        GIT_SEQUENCE_EDITOR="sh '${state//\'/\'\\\'\'}/sequence-editor'" git \
            -c rebase.instructionFormat=%s -c rerere.enabled=false rebase \
            --interactive --no-autosquash --no-autostash --no-update-refs --no-rebase-merges \
            --onto "$upstream" "$base" "$temp"
        return $?
    fi
    case "$id" in fork-rebase.*) ;; *) echo "Invalid session ID." >&2; return 1 ;; esac
    case "$id" in *[!a-zA-Z0-9.-]*) echo "Invalid session ID." >&2; return 1 ;; esac
    state="$common/$id"
    refs="refs/fork-rebase/$id"
    temp=$id
    if [ ! -f "$state/branch" ]; then echo "Unknown session: $id" >&2; return 1; fi
    IFS= read -r branch < "$state/branch" || return 1
    if [ ! -f "$state/remote" ]; then
        echo "Session has no saved source remote; start a new session with explicit remote/branch arguments." >&2; return 1
    fi
    IFS= read -r remote < "$state/remote" || return 1
    old=$(git rev-parse --verify "$refs/old") || return 1
    if [ "$action" = cleanup ]; then
        tip=$(git rev-parse --verify "$refs/finalized") || return 1
        # The exact finalized tip is saved remotely. -D still refuses branches
        # checked out in any worktree, without changing that worktree's HEAD.
        if git show-ref --verify --quiet "refs/heads/$temp"; then
            if [ "$(git rev-parse "refs/heads/$temp")" != "$tip" ]; then
                echo "Temporary branch changed; retaining session and branch." >&2; return 1
            fi
            git branch -D "$temp" || {
                echo "Retaining session. Switch away, then retry cleanup." >&2
                return 1
            }
        fi
        for path in old base upstream completed published finalized; do
            git update-ref -d "$refs/$path" || return 1
        done
        rm -- "$state/branch" "$state/remote" "$state/onto" "$state/sequence-editor" && rmdir -- "$state"
        return $?
    fi
    if git show-ref --verify --quiet "$refs/finalized"; then
        echo "Already finalized; use cleanup $id." >&2; return 1
    fi
    git rev-parse --verify "$refs/completed" > /dev/null || {
        echo "Rebase has not completed. Resolve and continue it; an aborted session cannot be published." >&2
        return 1
    }
    tip=$(git rev-parse --verify "refs/heads/$temp") || return 1
    upstream=$(git rev-parse --verify "$refs/upstream") || return 1
    git merge-base --is-ancestor "$upstream" "$tip" || {
        echo "Temporary branch no longer descends from saved upstream tip." >&2; return 1
    }
    case "$action" in
        review)
            echo "Range-diff compares per-commit patches, may include context noise, and does not isolate conflict resolutions." >&2
            if [ "$#" -eq 3 ]; then
                git --no-pager range-diff --no-color "$refs/base..$refs/old" "$upstream..$tip" > "$3"
            else
                git range-diff "$refs/base..$refs/old" "$upstream..$tip"
            fi ;;
        publish)
            published=$(git rev-parse --verify --quiet "$refs/published") || published=
            git push "--force-with-lease=refs/heads/$temp:$published" "$remote" "$tip:refs/heads/$temp" || return 1
            git update-ref "$refs/published" "$tip" || return 1
            echo "Published $remote/$temp at $tip for review."
            echo "Optional PR: discussion/approval only; close it without merging." ;;
        finalize)
            published=$(git rev-parse --verify "$refs/published") || return 1
            if [ "$tip" != "$published" ]; then
                echo "Tip changed since publication. Review and publish again before finalizing." >&2; return 1
            fi
            git push "--force-with-lease=refs/heads/$branch:$old" "$remote" "$published:refs/heads/$branch" || return 1
            git update-ref "$refs/finalized" "$published" || return 1
            echo "Finalized $remote/$branch at $published. Remote review branch $temp is retained."
            git_fork_rebase cleanup "$id" || echo "Finalization succeeded; temporary state retained for later cleanup."
            ;;
    esac
}
