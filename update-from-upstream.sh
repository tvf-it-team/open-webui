#!/bin/bash
# update-from-upstream.sh
# Merge the latest official Open WebUI release into the TVF fork, keeping
# TVF customisations. No force-push: history is preserved.
#
# Usage:
#   ./update-from-upstream.sh             merge the newest stable release
#   ./update-from-upstream.sh v0.11.4     merge a specific release
#   ./update-from-upstream.sh --continue  carry on after fixing conflicts by hand

set -euo pipefail
cd "$(dirname "$0")"

say()  { echo ">>> $*"; }
fail() { echo "Error: $*" >&2; exit 1; }

# Remember how conflicts were resolved, so the same ones fix themselves next time
git config rerere.enabled true

# Auto-resolve conflicts that have an obvious answer:
#   package-lock.json  -> upstream's version (it's generated)
#   branding assets    -> TVF's version (anything that exists in custom-changes/)
resolve_known_conflicts() {
  local f conflicts
  # Capture the list first: reading it live while running git checkout/add
  # makes two git processes fight over .git/index.lock
  conflicts=$(git diff --name-only --diff-filter=U)
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$f" == "package-lock.json" ]]; then
      say "Auto-resolving $f: taking upstream's version"
      git checkout --theirs -- "$f" && git add -- "$f"
    elif [[ -f "custom-changes/$f" ]]; then
      say "Auto-resolving $f: keeping TVF branding"
      git checkout --ours -- "$f" && git add -- "$f"
    fi
  done <<< "$conflicts"
}

# Make sure every branding asset in custom-changes/ is in place
reapply_assets() {
  local f
  while IFS= read -r f; do
    cp "custom-changes/$f" "$f"
  done < <(cd custom-changes && find static backend -type f)
  if [[ -n "$(git status --porcelain -- static backend/open_webui/static)" ]]; then
    say "Re-applying TVF branding assets"
    git add -A static backend/open_webui/static
    git commit -m "Re-apply TVF branding assets"
  fi
}

# Check it builds, then offer to move main forward and push
finish() {
  if git grep -q -E '^(<{7}|>{7}) ' -- ':!*.md'; then
    git grep -n -E '^(<{7}|>{7}) ' -- ':!*.md' | head -20
    fail "Conflict markers are still in the files above. Fix them, then run: $0 --continue"
  fi

  say "Checking the build (npm ci && npm run build). This takes a while..."
  npm ci
  npm run build
  say "Build OK."

  local branch
  branch=$(git branch --show-current)
  echo
  git log --oneline -3
  echo
  read -r -p "Move main forward to $branch and push to GitHub? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    git checkout main
    git merge --ff-only "$branch"
    git push origin main "$branch"
    say "Done. GitHub main now includes $branch."
    say "Next: back up the databases, then run the reinstall scripts (one instance first)."
  else
    say "Not pushed. When ready:"
    echo "    git checkout main && git merge --ff-only $branch && git push origin main"
  fi
}

# ---- --continue: after resolving conflicts by hand ----
if [[ "${1:-}" == "--continue" ]]; then
  [[ "$(git branch --show-current)" == upgrade-* ]] || fail "--continue must be run on an upgrade-* branch"
  if [[ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]]; then
    remaining=$(git diff --name-only --diff-filter=U)
    [[ -z "$remaining" ]] || fail "Still unresolved (git add them when fixed): $(echo $remaining)"
    git commit --no-edit
  fi
  reapply_assets
  finish
  exit 0
fi

# ---- Normal run ----
[[ -z "$(git status --porcelain)" ]] || fail "You have uncommitted changes. Commit or stash them first."

say "Updating main from GitHub..."
git checkout main
git pull --ff-only origin main

say "Fetching official Open WebUI releases..."
git fetch upstream --tags

TAG="${1:-$(git tag -l 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)}"
[[ -n "$TAG" ]] || fail "Could not find a release tag."
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "Tag $TAG not found."

if git merge-base --is-ancestor "$TAG" main; then
  say "main already includes $TAG. Nothing to do."
  exit 0
fi

BRANCH="upgrade-${TAG#v}"
if git rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then
  fail "Branch $BRANCH already exists. Delete it (git branch -D $BRANCH) or use --continue."
fi

say "Latest release is $TAG. Merging it on branch $BRANCH..."
git checkout -b "$BRANCH"

if ! git merge --no-edit -m "Merge upstream $TAG" "$TAG"; then
  resolve_known_conflicts
  remaining=$(git diff --name-only --diff-filter=U)
  if [[ -n "$remaining" ]]; then
    echo
    say "These files need resolving by hand:"
    echo "$remaining" | sed 's/^/    /'
    echo
    echo "Open each one, look for the <<<<<<< markers, keep upstream's new code"
    echo "plus the TVF changes, then run: git add <file>"
    echo "When all are done, run: $0 --continue"
    echo "(To give up and go back: git merge --abort && git checkout main && git branch -D $BRANCH)"
    exit 1
  fi
  git commit --no-edit
fi

reapply_assets
finish
