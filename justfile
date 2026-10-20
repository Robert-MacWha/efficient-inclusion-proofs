packages := "packages contracts circuits"

# Publish each package whose package.json version is not yet on npm (e.g. `just publish --dry-run`)
publish *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    for dir in {{packages}}; do
        name=$(node -p "require('./$dir/package.json').name")
        version=$(node -p "require('./$dir/package.json').version")
        if [ -n "$(npm view "$name@$version" version 2>/dev/null)" ]; then
            echo "$name@$version already published, skipping"
            continue
        fi
        echo "publishing $name@$version"
        (cd "$dir" && pnpm publish {{flags}})
    done
