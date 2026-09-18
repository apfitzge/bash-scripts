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
    local remote onto_remote onto_branch onto=upstream/master stack= stack_tip n ref new reviewed transaction
    local return_branch gitdir rebase_dir= candidate
    local -a options
    case "$action" in
        help|-h|--help)
            cat <<'HELP'
Usage: git_fork_rebase start <source-remote>/<branch> [--onto <base-remote>/<branch>] [--stack <local-top-branch>]
       git_fork_rebase review <session> [output-file]
       git_fork_rebase publish <session>
       git_fork_rebase finalize <session>
       git_fork_rebase cleanup <session>
       git_fork_rebase abort <session>
Example: git_fork_rebase start block-production/my-feature --onto upstream/master
The base defaults to upstream/master. Start fetches both remotes and rebases onto
the saved base tip (linearizes merge commits). Keep the printed session ID.
Publish and finalize use the saved source remote. Remote names cannot contain /.
With --stack staging, rebase through local staging and save the positions of all
local branches in that linear history. The local source branch must match the
remote source tip. Review lists all affected branches; finalize updates them
atomically, only locally. Stack mode requires review, not publication; you push
branches yourself. Publish is disabled in stack mode. Switch away from affected
branches in every worktree before finalizing. Merges in the stack are rejected.
Resolve conflicts manually, then use git rebase --continue in that worktree.
Review uses saved refs, regardless of HEAD. Re-review and re-publish after edits.
Range-diff compares per-commit patches; context noise is possible, and it does
not isolate conflict resolutions. An optional PR is only for discussion/approval
and must be closed without merging. No PR is created automatically.
Finalize requires publication and replaces the maintained branch with an exact
original-tip force-with-lease. Cleanup after success retains checked-out local
branches and remote review branches; cleanup can be retried after switching away.
Abort discards an unfinalized session and returns to the original local branch
(the stack top in stack mode). Run it in the session worktree with a clean index
and working tree, including untracked files; preserve conflict resolutions first.
Active rebases also require ignored files to be moved aside before aborting.
Original branches, remote branches, and stashes are retained.
HELP
            return 0 ;;
        start|review|publish|finalize|cleanup|abort) ;;
        *) echo "Unknown action: $action" >&2; return 1 ;;
    esac
    if [ "$action" = start ]; then
        options=("${@:3}")
        while [ "${#options[@]}" -gt 0 ]; do
            if [ "${#options[@]}" -lt 2 ] || [ -z "${options[1]}" ]; then
                echo "Options require a value. See: git_fork_rebase help" >&2; return 1
            fi
            case "${options[0]}" in
                --onto) onto=${options[1]} ;;
                --stack) stack=${options[1]} ;;
                *) echo "Unknown option: ${options[0]}" >&2; return 1 ;;
            esac
            options=("${options[@]:2}")
        done
    elif [ "$#" -gt 3 ] || { [ "$#" -eq 3 ] && [ "$action" != review ]; }; then
        echo "See: git_fork_rebase help" >&2; return 1
    fi
    if [ -z "$id" ]; then
        echo "See: git_fork_rebase help" >&2; return 1
    fi
    common=$(git rev-parse --path-format=absolute --git-common-dir) || return 1
    # Rebase state is per-worktree; check every registered worktree, not just HEAD.
    for path in "$common" "$common"/worktrees/*; do
        if [ "$action" != abort ] && { [ -d "$path/rebase-merge" ] || [ -d "$path/rebase-apply" ] || [ -f "$path/MERGE_HEAD" ]; }; then
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
        if [ -n "$stack" ]; then
            git check-ref-format "refs/heads/$stack" || return 1
            stack_tip=$(git rev-parse --verify "refs/heads/$stack") || return 1
            if [ "$(git rev-parse --verify "refs/heads/$branch")" != "$old" ]; then
                echo "Local $branch must match $remote/$branch before starting a stack rebase." >&2; return 1
            fi
            git merge-base --is-ancestor "$old" "$stack_tip" || {
                echo "$stack must descend from $branch." >&2; return 1
            }
            if [ -n "$(git rev-list --merges "$base..$stack_tip")" ] || [ "$base" = "$old" ]; then
                echo "Stack mode requires a linear feature history with commits beyond the merge-base." >&2; return 1
            fi
            old=$stack_tip
        fi
        return_branch=$stack
        if [ -z "$return_branch" ]; then
            return_branch=$(git symbolic-ref --quiet --short HEAD) || {
                echo "Start requires a local branch to return to on abort." >&2; return 1
            }
        fi
        state=$(mktemp -d "$common/fork-rebase.XXXXXXXXXX") || return 1
        id=${state##*/}
        refs="refs/fork-rebase/$id"
        temp=$id
        printf '%s\n' "$return_branch" > "$state/return-branch" || return 1
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
        if [ -n "$stack" ]; then
            # Keep real branch names out of the generated shell commands.
            # Numeric snapshot refs also support multiple branches at one commit.
            n=0
            : > "$state/stack" || return 1
            git for-each-ref --format='%(objectname) %(refname)' \
                --merged="$old" --no-merged="$base" refs/heads/ > "$state/candidates" || return 1
            while read -r tip ref; do
                case "$ref" in refs/heads/fork-rebase.*) continue ;; esac
                git symbolic-ref -q "$ref" > /dev/null && {
                    echo "Symbolic branch $ref is not supported in stack mode." >&2; return 1
                }
                printf '%s %s %s\n' "$tip" "$n" "$ref" >> "$state/stack" || return 1
                git update-ref "$refs/stack-old/$n" "$tip" || return 1
                n=$((n + 1))
            done < "$state/candidates"
            rm -- "$state/candidates" || return 1
            # Marker commands execute after each original branch boundary, even
            # when continuing in a fresh shell. Empty commits retain boundaries.
            printf '#!/bin/sh\nrefs=%s\n' "$refs" > "$state/sequence-editor" || return 1
            cat >> "$state/sequence-editor" <<'EDITOR' || return 1
state=$(dirname -- "$0")
awk -v refs="$refs" '
    NR == FNR {
        markers[$1] = markers[$1] "exec git update-ref " refs "/stack-new/" $2 " HEAD\n"
        next
    }
    { print }
    $1 == "pick" {
        for (commit in markers)
            if (index(commit, $2) == 1) printf "%s", markers[commit]
    }
    END { print "exec git update-ref " refs "/completed HEAD" }
' "$state/stack" "$1" > "$1.new" && mv -- "$1.new" "$1"
EDITOR
            options=(--reapply-cherry-picks --empty=keep)
            echo "Local branches to update after approval:"
            while read -r tip n ref; do
                printf '  %s (%s)\n' "${ref#refs/heads/}" "$tip"
            done < "$state/stack"
        else
            # Append one final exec, so aborting cannot masquerade as completion.
            printf '#!/bin/sh\nprintf "\\nexec git update-ref %s/completed HEAD\\n" >> "$1"\n' "$refs" > "$state/sequence-editor" || return 1
        fi
        git checkout -b "$temp" "$old" || return 1
        echo "Session: $id"
        echo "Source: $remote/$branch; base: $onto_remote/$onto_branch ($upstream)"
        echo "Review: git_fork_rebase review $id [output-file]"
        echo "Optional PR: discussion/approval only; close it without merging."
        GIT_SEQUENCE_EDITOR="sh '${state//\'/\'\\\'\'}/sequence-editor'" git \
            -c rebase.instructionFormat=%s -c rebase.abbreviateCommands=false -c rerere.enabled=false rebase \
            --interactive --no-autosquash --no-autostash --no-update-refs --no-rebase-merges \
            "${options[@]}" --onto "$upstream" "$base" "$temp"
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
    if [ "$action" = abort ]; then
        if git show-ref --verify --quiet "$refs/finalized"; then
            echo "Already finalized; use cleanup $id." >&2; return 1
        fi
        if [ -f "$state/return-branch" ]; then
            IFS= read -r return_branch < "$state/return-branch" || return 1
        elif [ -f "$state/stack" ]; then
            # Older sessions did not explicitly record the stack top. Only
            # infer it when exactly one saved branch has the original top tip.
            return_branch=
            while read -r tip n ref; do
                if [ "$tip" = "$old" ]; then
                    if [ -n "$return_branch" ]; then
                        echo "Ambiguous original stack top; retaining session." >&2; return 1
                    fi
                    return_branch=${ref#refs/heads/}
                fi
            done < "$state/stack"
        else
            return_branch=$branch
        fi
        git check-ref-format "refs/heads/$return_branch" || return 1
        git show-ref --verify --quiet "refs/heads/$return_branch" || {
            echo "Original local branch is missing; retaining session." >&2; return 1
        }
        gitdir=$(git rev-parse --absolute-git-dir) || return 1
        for path in "$common" "$common"/worktrees/*; do
            if [ -f "$path/MERGE_HEAD" ]; then
                echo "Finish the active merge before aborting the session." >&2; return 1
            fi
            if [ "$path" != "$gitdir" ] && [ -f "$path/HEAD" ]; then
                candidate=$(cat "$path/HEAD") || return 1
                if [ "$candidate" = "ref: refs/heads/$temp" ] ||
                    [ "$candidate" = "ref: refs/heads/$return_branch" ]; then
                    echo "Session or original branch is checked out in another worktree." >&2; return 1
                fi
            fi
            for candidate in "$path/rebase-merge" "$path/rebase-apply"; do
                [ -d "$candidate" ] || continue
                if [ "$path" != "$gitdir" ] ||
                    [ ! -f "$candidate/head-name" ] ||
                    [ "$(cat "$candidate/head-name")" != "refs/heads/$temp" ] ||
                    [ ! -f "$candidate/orig-head" ] ||
                    [ "$(cat "$candidate/orig-head")" != "$old" ] ||
                    [ ! -f "$candidate/onto" ] ||
                    [ "$(cat "$candidate/onto")" != "$(git rev-parse --verify "$refs/upstream")" ] ||
                    [ -f "$candidate/autostash" ]; then
                    echo "Active rebase does not belong to this session in this worktree; retaining session." >&2; return 1
                fi
                rebase_dir=$candidate
            done
        done
        status=$(git status --porcelain --untracked-files=all --ignore-submodules=none) || return 1
        if [ -n "$status" ]; then
            echo "A clean working tree and index (including untracked files) are required; preserve changes before aborting." >&2; return 1
        fi
        if [ -n "$rebase_dir" ]; then
            # rebase --abort resets the worktree; unlike checkout, that reset
            # may overwrite ignored files. Refuse those too before resetting.
            status=$(git ls-files --others --ignored --exclude-standard) || return 1
            if [ -n "$status" ]; then
                echo "Preserve ignored files before aborting an active rebase." >&2; return 1
            fi
            git -c core.hooksPath=/dev/null rebase --abort || return 1
        fi
        # Non-forcing checkout also protects ignored files from being overwritten.
        git -c core.hooksPath=/dev/null checkout --no-overwrite-ignore "$return_branch" -- || return 1
        if git show-ref --verify --quiet "refs/heads/$temp"; then
            git branch -D "$temp" || return 1
        fi
        git for-each-ref --format='delete %(refname) %(objectname)' "$refs/" |
            git update-ref --stdin || return 1
        rm -r -- "$state" || return 1
        echo "Aborted $id; returned to $return_branch."
        return 0
    fi
    if [ "$action" = cleanup ]; then
        tip=$(git rev-parse --verify "$refs/finalized") || return 1
        # The exact finalized tip is saved on the destination branches. -D refuses
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
        if [ -f "$state/stack" ]; then
            git for-each-ref --format='delete %(refname) %(objectname)' \
                "$refs/stack-old/" "$refs/stack-new/" "$refs/stack-reviewed/" |
                git update-ref --stdin || return 1
            git update-ref -d "$refs/reviewed" || return 1
            rm -- "$state/stack" || return 1
        fi
        if [ -f "$state/return-branch" ]; then rm -- "$state/return-branch" || return 1; fi
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
    if [ -f "$state/stack" ]; then
        if [ "$tip" != "$(git rev-parse "$refs/completed")" ]; then
            echo "Stack tip changed after rebase; start a new session to rebuild branch mappings." >&2; return 1
        fi
        if [ "$action" = publish ]; then
            echo "Stack mode updates local branches only; review, finalize, then push them yourself." >&2; return 1
        fi
        while read -r old n ref; do
            new=$(git rev-parse --verify "$refs/stack-new/$n") || return 1
            git merge-base --is-ancestor "$upstream" "$new" &&
                git merge-base --is-ancestor "$new" "$tip" || {
                    echo "Invalid rebased boundary for $ref; start a new session." >&2; return 1
                }
        done < "$state/stack"
        if [ "$action" = finalize ]; then
            reviewed=$(git rev-parse --verify "$refs/reviewed") || return 1
            if [ "$tip" != "$reviewed" ]; then
                echo "Review the current stack before finalizing." >&2; return 1
            fi
            transaction="start\nverify refs/heads/$temp $tip\n"
            while read -r old n ref; do
                # update-ref does not protect checked-out branches itself.
                for path in "$common" "$common"/worktrees/*; do
                    if [ -f "$path/HEAD" ] && [ "$(cat "$path/HEAD")" = "ref: $ref" ]; then
                        echo "$ref is checked out; switch that worktree away before finalizing." >&2; return 1
                    fi
                done
                if git symbolic-ref -q "$ref" > /dev/null; then
                    echo "$ref became symbolic; refusing to finalize." >&2; return 1
                fi
                new=$(git rev-parse --verify "$refs/stack-reviewed/$n") || return 1
                transaction+="verify $refs/stack-new/$n $new\nupdate $ref $new $old\n"
            done < "$state/stack"
            transaction+="create $refs/finalized $tip\nprepare\ncommit\n"
            printf '%b' "$transaction" | git update-ref --no-deref --stdin || return 1
            echo "Updated the saved local branches. No branches were pushed."
            git_fork_rebase cleanup "$id" || echo "Finalization succeeded; temporary state retained for later cleanup."
            return 0
        fi
    fi
    case "$action" in
        review)
            echo "Range-diff compares per-commit patches, may include context noise, and does not isolate conflict resolutions." >&2
            if [ -f "$state/stack" ]; then
                # Use the same output path for the branch map and the patch review.
                if [ "$#" -eq 3 ]; then
                    git_fork_rebase_stack_review "$state" "$refs" "$tip" > "$3" || return 1
                else
                    git_fork_rebase_stack_review "$state" "$refs" "$tip" || return 1
                fi
                git update-ref "$refs/reviewed" "$tip" || return 1
            elif [ "$#" -eq 3 ]; then
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

# Record precisely the branch boundaries shown by a successful stack review.
git_fork_rebase_stack_review() {
    local state=$1 refs=$2 tip=$3 old n ref new transaction="start\n"
    while read -r old n ref; do
        new=$(git rev-parse --verify "$refs/stack-new/$n") || return 1
        printf '%s: %s -> %s\n' "${ref#refs/heads/}" "$old" "$new"
        transaction+="update $refs/stack-reviewed/$n $new\n"
    done < "$state/stack"
    git --no-pager range-diff --no-color "$refs/base..$refs/old" "$refs/upstream..$tip" || return 1
    printf '%b' "${transaction}prepare\ncommit\n" | git update-ref --stdin > /dev/null
}
