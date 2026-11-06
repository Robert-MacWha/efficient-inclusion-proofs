#!/usr/bin/env python3
"""Compiles the skew-MMR and leanIMT membership circuits at every size with `circom --O2` and
writes their constraint counts to `results/constraints.csv`. Needs `pnpm install` in `packages/`."""

import csv
import re
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

BENCH = Path(__file__).resolve().parent
REPO = BENCH.parent
MODULES = REPO / "packages" / "node_modules"

CIRCUITS = {
    # A skew-MMR with `t` trees holds 2^(t+1) - t - 2 members.
    "skew-mmr": (f'include "{REPO}/circuits/inclusion.circom";\ncomponent main = SkewMmrInclusion({{}});',
                 range(2, 33), lambda t: 2 ** (t + 1) - t - 2),
    "leanimt": (f'include "{MODULES}/@zk-kit/binary-merkle-root.circom/src/binary-merkle-root.circom";\n'
                "component main = BinaryMerkleRoot({});", range(1, 33), lambda d: 2**d),
}


def compile_one(structure: str, size: int, out: Path) -> dict:
    template, _, capacity = CIRCUITS[structure]
    src = out / f"{structure}_{size}.circom"
    src.write_text("pragma circom 2.1.5;\n" + template.format(size))
    log = subprocess.run(
        ["circom", str(src), "--r1cs", "--O2", "-o", str(out),
         "-l", str(MODULES), "-l", str(MODULES / "circomlib" / "circuits")],
        capture_output=True, text=True, check=True,
    ).stdout
    constraints = int(re.search(r"^non-linear constraints: (\d+)", log, re.MULTILINE).group(1))
    return {"structure": structure, "size": size, "capacity": capacity(size), "constraints": constraints}


with tempfile.TemporaryDirectory() as tmp, ThreadPoolExecutor() as pool:
    jobs = [(s, n, Path(tmp)) for s, (_, sizes, _) in CIRCUITS.items() for n in sizes]
    rows = list(pool.map(lambda job: compile_one(*job), jobs))

with (BENCH / "results" / "constraints.csv").open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
