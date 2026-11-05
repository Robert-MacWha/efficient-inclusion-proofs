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

# Benchmark skew-MMR against zk-kit's trees (insert gas, constraints, JS performance); see benchmarks/README.md
bench:
    #!/usr/bin/env bash
    set -euo pipefail
    (cd packages && pnpm install)
    cd benchmarks
    pnpm install
    [ -d lib/forge-std ] || forge install foundry-rs/forge-std@v1.16.2 --no-git
    forge test
    python3 scripts/constraints.py
    node perf/bench.ts
    python3 scripts/plot.py
