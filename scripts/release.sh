#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.3.0
#
# Bumps MARKETING_VERSION in project.yml, commits, tags, and pushes.
# The tag push triggers GitHub Actions to build the DMG and create a release.

VERSION="${1:?Usage: $0 <version> (e.g., 0.3.0)}"
TAG="v${VERSION}"

# Validate semver format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Version must be semver (e.g., 0.3.0)"
  exit 1
fi

# Must be on main branch
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
  echo "Error: Must be on 'main' branch (currently on '$BRANCH')"
  exit 1
fi

# No uncommitted changes
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: Uncommitted changes detected. Commit or stash first."
  exit 1
fi

# Tag must not exist
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Error: Tag $TAG already exists"
  exit 1
fi

# Update MARKETING_VERSION in both targets
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"${VERSION}\"/" project.yml

# Commit version bump
git add project.yml
git commit -m "Bump version to ${VERSION}"

# Create annotated tag
git tag -a "$TAG" -m "Release ${VERSION}"

# Push commit and tag
git push origin main
git push origin "$TAG"

echo ""
echo "Release $TAG pushed successfully."
echo "GitHub Actions will build the DMG and create the release."
echo "Track progress: https://github.com/julian0xff/OpenDictator/actions"
