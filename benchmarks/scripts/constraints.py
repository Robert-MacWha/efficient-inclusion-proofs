#!/usr/bin/env python3
"""Compiles the skew-MMR and leanIMT membership circuits at every size and records their
constraint counts in `results/constraints.csv`.

- skew-mmr: `SkewMmrInclusion(MAX_TREES)` from `circuits/inclusion.circom` (Poseidon(3) node hash).
- leanimt:  `BinaryMerkleRoot(MAX_DEPTH)` from `@zk-kit/binary-merkle-root.circom` (Poseidon(2)),
            the circuit Semaphore v4 uses for leanIMT membership.

Both are compiled with `circom --O2`, so linear constraints are folded away and the count is what
a Groth16 / PLONK prover would see. Run from `benchmarks/` after `pnpm install`.
"""

import csv
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
OUT = ROOT / "results" / "constraints.csv"

SKEW_TREES = range(2, 33)
LEANIMT_DEPTHS = range(1, 33)


def skew_capacity(max_trees: int) -> int:
    """Elements a skew-MMR holds before its frontier outgrows `max_trees` trees.

    The frontier first reaches `d` trees at `2^d - d` elements (ranks `d-2, ..., 0, 0`).
    """
    return 2 ** (max_trees + 1) - max_trees - 2


SOURCES = {
    "skew-mmr": (
        'include "{root}/../circuits/inclusion.circom";\n'
        "component main = SkewMmrInclusion({size});\n",
        skew_capacity,
    ),
    "leanimt": (
        'include "{root}/node_modules/@zk-kit/binary-merkle-root.circom/src/binary-merkle-root.circom";\n'
        "component main = BinaryMerkleRoot({size});\n",
        lambda depth: 2**depth,
    ),
}


def compile_one(structure: str, size: int) -> dict:
    template, capacity = SOURCES[structure]
    src = BUILD / f"{structure}_{size}.circom"
    src.write_text("pragma circom 2.1.5;\n" + template.format(root=ROOT, size=size))

    out = subprocess.run(
        [
            "circom", str(src), "--r1cs", "--O2", "-o", str(BUILD),
            "-l", str(ROOT / "node_modules"),
            "-l", str(ROOT / "node_modules" / "circomlib" / "circuits"),
        ],
        capture_output=True, text=True, check=True,
    ).stdout

    def field(name: str) -> int:
        return int(re.search(rf"^{name}: (\d+)", out, re.MULTILINE).group(1))

    nonlinear, linear = field("non-linear constraints"), field("linear constraints")
    return {
        "structure": structure,
        "size": size,
        "capacity": capacity(size),
        "constraints": nonlinear + linear,
        "nonlinear": nonlinear,
        "linear": linear,
    }


def main() -> None:
    BUILD.mkdir(exist_ok=True)
    jobs = [("skew-mmr", t) for t in SKEW_TREES] + [("leanimt", d) for d in LEANIMT_DEPTHS]
    with ThreadPoolExecutor() as pool:
        rows = list(pool.map(lambda job: compile_one(*job), jobs))

    with OUT.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {len(rows)} rows to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
