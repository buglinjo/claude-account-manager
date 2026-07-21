#!/usr/bin/env bash
set -euo pipefail

#
# release.sh — tag a new cam version, update the Homebrew formula, and create
#              a GitHub Release.
#
# Usage:
#   ./scripts/release.sh v1.0.1
#
# If no tag is provided, the script prompts interactively.
#

# ---- config ----------------------------------------------------------------
HOMEBREW_TAP_REL="../homebrew-claude-account-manager"
FORMULA_REL="Formula/claude-account-manager.rb"
GITHUB_REPO="buglinjo/claude-account-manager"

# ---- helpers ---------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

die()   { echo -e "${RED}error:${NC} $*" >&2; exit 1; }
info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}warn:${NC} $*"; }

# ---- checks ----------------------------------------------------------------
command -v git    >/dev/null || die "git is required"
command -v shasum >/dev/null || die "shasum is required"
command -v gh     >/dev/null || warn "gh (GitHub CLI) not found — skipping GitHub Release creation"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# clean working tree?
if ! git diff-index --quiet HEAD --; then
  die "working tree has uncommitted changes; commit or stash first"
fi

# ---- determine tag ---------------------------------------------------------
git fetch --tags origin 2>/dev/null || true
LATEST_TAG=$(git tag --sort=-v:refname | head -1)

info "latest tag on origin: ${LATEST_TAG:-<none>}"

if [[ $# -ge 1 ]]; then
  NEW_TAG="$1"
else
  echo -n "Enter new tag (e.g., v1.0.1): "
  read -r NEW_TAG
fi

[[ -n "$NEW_TAG" ]] || die "no tag provided"
[[ "$NEW_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid tag format: $NEW_TAG (expected vX.Y.Z)"

if git rev-parse "$NEW_TAG" >/dev/null 2>&1; then
  die "tag $NEW_TAG already exists locally"
fi

ARCHIVE_URL="https://github.com/${GITHUB_REPO}/archive/refs/tags/${NEW_TAG}.tar.gz"

# ---- create tag ------------------------------------------------------------
info "creating tag $NEW_TAG..."
git tag -a "$NEW_TAG" -m "cam ${NEW_TAG}"

# ---- push tag so GitHub generates the archive ------------------------------
info "pushing tag $NEW_TAG to origin..."
git push origin "$NEW_TAG"

# ---- download archive and compute SHA (matches exactly what brew fetches) ---
info "downloading archive to compute sha256..."
SHA=$(curl -sL "$ARCHIVE_URL" | shasum -a 256 | cut -d' ' -f1)
info "sha256: $SHA"

# ---- update Homebrew formula -----------------------------------------------
TAP_DIR="$(cd "$ROOT_DIR/$HOMEBREW_TAP_REL" && pwd 2>/dev/null)" || die "homebrew tap not found at $ROOT_DIR/$HOMEBREW_TAP_REL"
FORMULA_FILE="$TAP_DIR/$FORMULA_REL"

if [[ ! -f "$FORMULA_FILE" ]]; then
  die "formula file not found: $FORMULA_FILE"
fi

info "updating $FORMULA_FILE..."

sed -i '' "s|url \".*\"|url \"$ARCHIVE_URL\"|" "$FORMULA_FILE"
sed -i '' "s|sha256 \".*\"|sha256 \"$SHA\"|" "$FORMULA_FILE"
sed -i '' '/^  revision/d' "$FORMULA_FILE"

info "formula updated"

# ---- create GitHub Release -------------------------------------------------
if command -v gh >/dev/null 2>&1; then
  info "creating GitHub Release..."
  RELEASE_CREATED=false
  PREV_TAG=$(git tag --sort=-v:refname | grep -v "^$NEW_TAG$" | head -1)
  if [[ -n "$PREV_TAG" ]]; then
    gh release create "$NEW_TAG" --title "$NEW_TAG" --generate-notes --notes-start-tag "$PREV_TAG" && RELEASE_CREATED=true
  fi
  if ! $RELEASE_CREATED; then
    gh release create "$NEW_TAG" --title "$NEW_TAG" --generate-notes && RELEASE_CREATED=true
  fi
  if ! $RELEASE_CREATED; then
    gh release create "$NEW_TAG" --title "$NEW_TAG" --notes "" || warn "GitHub Release creation failed"
  fi
fi

# ---- commit and push formula update ----------------------------------------
cd "$TAP_DIR"

if git diff-index --quiet HEAD --; then
  warn "no changes in tap repo (formula already up-to-date?)"
else
  git add -A
  git commit -m "cam ${NEW_TAG}"
  if git remote get-url origin >/dev/null 2>&1; then
    info "pushing tap repo..."
    git push origin master || warn "push failed — push tap repo manually"
  else
    warn "tap repo has no remote — committed locally at $TAP_DIR"
  fi
fi

# ---- done ------------------------------------------------------------------
echo ""
info "release ${NEW_TAG} published!"
echo "   brew update && brew upgrade cam"
