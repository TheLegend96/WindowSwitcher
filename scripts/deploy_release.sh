#!/bin/bash
set -e

# ==============================================================================
# Window Switcher - Automated GitHub Release & Deployment Pipeline
# Usage: ./scripts/deploy_release.sh <version> "<release_notes>"
# Example: ./scripts/deploy_release.sh 1.0.1 "Liquid glass design & real-time preview"
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$1"
NOTES="$2"
REPO_OWNER="pruthvirajmane"
REPO_NAME="mac-window-switcher"

if [ -z "$VERSION" ]; then
    echo "❌ Error: Version argument is required."
    echo "Usage: $0 <version> [release_notes]"
    echo "Example: $0 1.0.1 \"Added live screen mirroring and Cobalt Azure branding\""
    exit 1
fi

if [ -z "$NOTES" ]; then
    NOTES="Window Switcher v$VERSION release with performance optimizations and design polish."
fi

echo "🚀 Preparing release v$VERSION for $REPO_OWNER/$REPO_NAME..."

# 1. Update Info.plist version strings
PLIST_FILE="$PROJECT_DIR/Resources/Info.plist"
if [ -f "$PLIST_FILE" ]; then
    echo "📝 Updating Info.plist to version $VERSION..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST_FILE" || true
    CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST_FILE" 2>/dev/null || echo "1")
    NEW_BUILD=$((CURRENT_BUILD + 1))
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST_FILE" || true
fi

# 2. Build application and create production DMG
echo "📦 Building application bundle and compressed DMG..."
"$PROJECT_DIR/create_dmg.sh"

DMG_FILE="$PROJECT_DIR/WindowSwitcher.dmg"
if [ ! -f "$DMG_FILE" ]; then
    echo "❌ Error: DMG was not generated at $DMG_FILE"
    exit 1
fi

# 3. Git commit & tag
cd "$PROJECT_DIR"
if [ -d ".git" ]; then
    echo "🌿 Staging release changes..."
    git add -A
    git commit -m "Release v$VERSION: $NOTES" || echo "No git changes to commit"
    git tag -fa "v$VERSION" -m "Window Switcher v$VERSION"
    echo "🏷️ Git tag v$VERSION created."
fi

# 4. Check GitHub Remote & Release
echo "🌐 Checking GitHub release status..."
if git remote get-url origin >/dev/null 2>&1; then
    echo "Pushing commits and tags to GitHub..."
    git push origin HEAD --tags || true
fi

# 5. Check if gh CLI or GITHUB_TOKEN is available
if command -v gh >/dev/null 2>&1; then
    echo "🤖 Publishing GitHub release via gh CLI..."
    gh release create "v$VERSION" "$DMG_FILE#Window Switcher macOS DMG (Apple Silicon)" \
        --title "Window Switcher v$VERSION" \
        --notes "$NOTES"
    echo "🎉 Release v$VERSION published successfully to GitHub!"
elif [ -n "$GITHUB_TOKEN" ]; then
    echo "🤖 Publishing GitHub release via REST API..."
    RELEASE_DATA=$(cat <<EOF
{
  "tag_name": "v$VERSION",
  "target_commitish": "main",
  "name": "Window Switcher v$VERSION",
  "body": "$NOTES",
  "draft": false,
  "prerelease": false
}
EOF
)
    RESPONSE=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases" \
        -d "$RELEASE_DATA")

    UPLOAD_URL=$(echo "$RESPONSE" | grep -o 'https://uploads.github.com/repos/[^"]*assets' | head -n 1)

    if [ -n "$UPLOAD_URL" ]; then
        UPLOAD_ENDPOINT="${UPLOAD_URL}?name=WindowSwitcher.dmg"
        echo "Uploading DMG asset to $UPLOAD_ENDPOINT..."
        curl -s -X POST \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/x-apple-diskimage" \
            --data-binary @"$DMG_FILE" \
            "$UPLOAD_ENDPOINT"
        echo "🎉 Release v$VERSION published with DMG attached!"
    else
        echo "⚠️ Note: GitHub release created, but upload URL was not parsed: $RESPONSE"
    fi
else
    echo "ℹ️ Release packaged locally! When you connect your remote repo, push with:"
    echo "   git remote add origin https://github.com/$REPO_OWNER/$REPO_NAME.git"
    echo "   git push -u origin main --tags"
    echo "   And upload '$DMG_FILE' to the GitHub Release page."
fi

echo "✅ All release steps complete for v$VERSION!"
