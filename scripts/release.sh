#!/usr/bin/env sh
# Creates and pushes a new release tag based on current date.
# Version format: YY.M.D or YY.M.D.B if the base tag already exists.
#
# Usage:
#   ./scripts/release.sh           # interactive
#   ./scripts/release.sh --dry-run # show tag without creating it

DRY_RUN=0
if [ "$1" = "--dry-run" ]; then
    DRY_RUN=1
fi

# Build base version from current date (no leading zeros)
year=$(date -u '+%y')
month=$(date -u '+%-m' 2>/dev/null || date -u '+%m' | sed 's/^0//')
day=$(date -u '+%-d' 2>/dev/null || date -u '+%d' | sed 's/^0//')
base_version="${year}.${month}.${day}"

echo "Determining release version..."
echo "Base version: ${base_version}"

# Fetch all tags from remote
echo "Fetching tags from remote..."
git fetch --tags 2>/dev/null

# Determine final version — increment build number if base already exists
version="${base_version}"
if git tag -l | grep -qx "v${version}"; then
    echo "Tag 'v${version}' already exists, checking build numbers..."
    build=1
    while git tag -l | grep -qx "v${version}.${build}"; do
        build=$((build + 1))
    done
    version="${base_version}.${build}"
    echo "Found available version: ${version} (build #${build})"
else
    echo "Version '${version}' is available"
fi

tag="v${version}"

echo ""
echo "=================================="
echo "Release version: ${tag}"
echo "=================================="
echo ""

if [ "$DRY_RUN" = "1" ]; then
    echo "DRY RUN: Would create and push tag '${tag}'"
    exit 0
fi

# Confirm with user (default is Yes)
printf "Create and push tag '%s'? [Y/n]: " "${tag}"
read -r confirmation
if [ "$confirmation" = "n" ] || [ "$confirmation" = "N" ]; then
    echo "Release cancelled"
    exit 0
fi

# Warn about uncommitted changes
status=$(git status --porcelain)
if [ -n "$status" ]; then
    echo ""
    echo "WARNING: You have uncommitted changes:"
    echo "$status"
    echo ""
    printf "Continue anyway? [y/N]: "
    read -r proceed
    if [ "$proceed" != "y" ] && [ "$proceed" != "Y" ]; then
        echo "Release cancelled"
        exit 0
    fi
fi

# Create tag
echo ""
echo "Creating tag '${tag}'..."
git tag -a "${tag}" -m "Release ${tag}"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create tag"
    exit 1
fi
echo "Tag created successfully"

# Push tag
echo "Pushing tag to remote..."
git push origin "${tag}"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to push tag"
    echo "You can manually push it later with: git push origin ${tag}"
    exit 1
fi

echo ""
echo "=================================="
echo "Release ${tag} created successfully!"
echo "=================================="
echo ""
echo "GitHub Actions will now build and publish the release."
echo "Check progress at: https://github.com/powertech-center/crossler/actions"
echo ""
