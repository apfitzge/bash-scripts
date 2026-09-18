# Review a rebased stack before moving local branches

For a linear stack `upstream/master → feature → PR branch → staging`:

```bash
git_fork_rebase start block-production/feature --stack staging
# Optional base override: --onto upstream/release
# Keep the printed session ID, such as fork-rebase.ABC123abcd.
```

The source is still an explicit remote/branch. `--stack` names the **local top
branch** containing all the work. The local `feature` must match the fetched
`block-production/feature` and be an ancestor of `staging`. Start requires a clean
working tree, including untracked files, and no active merge/rebase in any worktree.
Stack mode rejects merge commits in the replayed history.

Start prints every affected local branch and its original tip. It selects local
branches whose tips lie in the history being replayed, including aliases at the
same commit. It excludes upstream history, divergent branches, and temporary
`fork-rebase.*` branches. The set is saved at start: branches created later are
not added. Each branch retains its own boundary; staging work does not become
part of the feature branch.

The function rebases a temporary copy of the entire stack. It leaves the real
local branches and all remote branches unchanged. Git's immediate `--update-refs`
is disabled; durable marker commands save the new position of each original
branch instead. The saved refs and metadata survive new shell sessions. Empty
commits and commits already present upstream are replayed/kept to retain branch
boundaries. Nothing chooses conflict resolutions automatically.

Resolve any conflicts in the original worktree:

```bash
# Edit conflicting files, then:
git add <resolved-files>
git rebase --continue
```

Review the branch mapping and full stack's range-diff, optionally saving both:

```bash
git_fork_rebase review fork-rebase.ABC123abcd
git_fork_rebase review fork-rebase.ABC123abcd review.txt
```

Review shows `branch: old-tip -> new-tip` for each affected branch and records
those exact new tips. Range-diff compares per-commit patches, may include context
noise, and does **not** isolate conflict resolutions. Inspect and test the code
as well. An optional PR is for discussion/approval only and must be closed without
merging; no PR is created or merged automatically.

After approval, explicitly finalize:

```bash
git_fork_rebase finalize fork-rebase.ABC123abcd
```

**In stack mode, finalization only updates local branches. Nothing is pushed.**
Push the branches yourself afterward. The `publish` command is disabled for stack
sessions. Finalization updates all saved local branch refs in one Git transaction;
if any original tip changed, none is moved. It refuses checked-out target branches
in every worktree and rejects changed reviewed mappings or an edited temporary
tip. Switch other worktrees away from affected branches first. If you edit the
rebased history, start a new session so the boundaries can be rebuilt.

The explicit finalize command is your approval; the function cannot verify human
approval. Review/finalize operate on saved refs, regardless of current HEAD, and
are blocked during unfinished rebases. Aborted sessions cannot be finalized.
Do not run simultaneous operations against the same session or change its branches
while finalizing.

Cleanup runs after success. It retains a temporary branch that is still checked
out or has changed. Switch away and retry:

```bash
git switch staging
git_fork_rebase cleanup fork-rebase.ABC123abcd
```

Session refs live under `refs/fork-rebase/<session>/`; metadata and the completion
script live in `$(git rev-parse --git-common-dir)/<session>/`. Find sessions with
`git for-each-ref --format='%(refname)' refs/fork-rebase/`. Discard an unfinalized session with:

```bash
git_fork_rebase abort <session>
```

Abort works during the session's rebase or after completion, before finalize.
Run it in the session worktree. It verifies the active rebase's branch, original
tip, and base before aborting it, returns to the original local branch (the top
branch in stack mode), then deletes only the session's temporary local branch,
refs, and state directory. Original branches, remote review branches, stashes,
and other sessions are retained. Finalized sessions must use `cleanup` instead.

Abort requires a clean index and working tree, including untracked files. It
refuses unresolved conflicts or uncommitted resolutions: preserve that work
before retrying. During an active rebase, ignored files must also be preserved
outside the worktree because Git’s abort reset can overwrite them. It also
refuses rebases in other worktrees and branches checked
out elsewhere. Older stack sessions infer the top from their saved branch map;
if multiple branches share that original tip, abort refuses the ambiguity.
Older single-branch sessions return to the saved local source branch because
those sessions did not record the original checkout.

## Existing single-branch workflow

Without `--stack`, the original remote workflow remains available:

```bash
git_fork_rebase start block-production/feature  # --onto defaults to upstream/master
git_fork_rebase review <session> [output-file]
git_fork_rebase publish <session>
git_fork_rebase finalize <session>
```

In that mode, publish pushes the temporary review branch, and finalize replaces
the remote source branch using the saved original-tip force-with-lease. It never
weakens that lease or retries a rejection. It does not move other local branches.
Use `--stack` for the local-only workflow described above.

## Validation

Run `bash tests/git_fork_rebase_stack.sh`. It creates disposable local repositories
and tests branch listing and boundaries, aliases, fresh-shell review/continuation,
conflicts and aborts, checked-out branches, atomic stale-tip rejection, altered
reviewed mappings, edited rebased tips, cleanup, and unchanged remote branches.
Run `bash -n git_scripts.sh` for syntax validation.

For manual testing, create disposable upstream and fork bare repositories and a
working clone. Build a feature → PR → staging stack, advance upstream, and run the
sequence above. Check the printed affected list before resolving conflicts and
verify each resulting branch contains only its intended part of the stack. Repeat
with a conflicting edit, an affected branch checked out in another worktree, and
an original branch moved after review. Finalization must refuse unsafe updates
without moving any of the saved local branches or pushing anything.
