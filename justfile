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

# Compare skew-MMR with zk-kit's trees; see bench/README.md
bench:
    cd contracts && pnpm install && forge test --mc LeanImtComparison
    cd packages && pnpm install && pnpm bench
    python3 bench/constraints.py
    python3 bench/plot.py

# Check the Lean proofs of the skew-MMR circuit, and its model against arkworks; see lean/README.md
lean:
    cd lean && lake build
    mkdir -p crates/target/lean-traces
    cd lean && lake env lean --run Traces.lean ../crates/target/lean-traces
    cd crates && cargo test -p skew-mmr --test lean_traces -- --ignored
