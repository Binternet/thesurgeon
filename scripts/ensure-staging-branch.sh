#!/usr/bin/env bash
# Create and push the staging branch so ArgoCD can watch it.
# The staging Application (hcomp-app) uses targetRevision: staging and values-stg.yaml.
# Run from repo root: ./scripts/ensure-staging-branch.sh

set -e

BRANCH="${1:-staging}"
PREV=$(git branch --show-current 2>/dev/null || echo "main")

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repo. Run from the hcomp repo root."
  exit 1
fi

if [[ ! -f charts/hcomp-app/values-stg.yaml ]]; then
  echo "Missing charts/hcomp-app/values-stg.yaml. Aborting."
  exit 1
fi

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "Branch $BRANCH already exists. Pushing."
  git push -u origin "$BRANCH" 2>/dev/null || true
else
  echo "Creating branch $BRANCH from $PREV."
  git checkout -b "$BRANCH"
  git push -u origin "$BRANCH"
  git checkout "$PREV"
fi

echo "Done. ArgoCD can watch $BRANCH (chart + values-stg.yaml)."
