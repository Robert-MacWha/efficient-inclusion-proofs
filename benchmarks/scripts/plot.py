#!/usr/bin/env python3
"""Plots `results/gas/*.csv`, `results/constraints.csv` and `results/perf-js-*.csv` into
`results/*.svg`, and prints the markdown tables used in `README.md`. Run from `benchmarks/`."""

import csv
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

RESULTS = Path(__file__).resolve().parent.parent / "results"

SKEW, LEAN, IMT = "#2a78d6", "#eb6834", "#1baf7a"
INK, MUTED, GRID = "#0b0b0b", "#52514e", "#e4e3df"
MEMBERS = 1_024
# Inserts averaged per point in the gas and JS insert charts.
BUCKET = 32
STRUCTURES = [("skew-mmr", "skew-MMR", SKEW), ("leanimt", "leanIMT", LEAN), ("binary-imt", "IMT", IMT)]

plt.rcParams.update({
    "font.size": 10,
    "axes.edgecolor": MUTED,
    "axes.labelcolor": INK,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "grid.color": GRID,
    "grid.linewidth": 0.8,
    "legend.frameon": False,
    "svg.fonttype": "none",
    # Deterministic element ids, so re-plotting unchanged data leaves the SVGs unchanged.
    "svg.hashsalt": "skew-mmr-benchmarks",
})


def read(path: Path) -> list[dict]:
    with path.open() as f:
        return list(csv.DictReader(f))


def save(fig, name: str) -> None:
    fig.savefig(RESULTS / f"{name}.svg", metadata={"Date": None})


def mean(values: list[float]) -> float:
    return sum(values) / len(values)


def bucketed(values: list[float]):
    """Per-bucket (last member, mean, min, max) over runs of `BUCKET` consecutive values."""
    out = []
    for end in range(BUCKET, len(values) + 1, BUCKET):
        window = values[end - BUCKET:end]
        out.append((end, mean(window), min(window), max(window)))
    return out


def line_with_band(ax, values: list[float], label: str, color: str) -> None:
    points = bucketed(values)
    xs = [p[0] for p in points]
    ax.fill_between(xs, [p[2] for p in points], [p[3] for p in points], color=color, alpha=0.12,
                    linewidth=0)
    ax.plot(xs, [p[1] for p in points], color=color, linewidth=2, label=label)


# Insert gas


def gas(name: str) -> list[int]:
    return [int(row["gas"]) for row in read(RESULTS / "gas" / f"{name}.csv")]


def plot_gas() -> None:
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.2))
    for ax, hash_fn in zip(axes, ["keccak", "poseidon"]):
        for structure, label, color in STRUCTURES[:2]:
            line_with_band(ax, gas(f"{structure}-{hash_fn}"), label, color)
        ax.set_title(f"{'Keccak' if hash_fn == 'keccak' else 'Poseidon'} node hash", loc="left",
                     color=INK)
        ax.set_xlabel("Members")
        ax.set_xlim(0, MEMBERS)
        ax.set_ylim(bottom=0)
        ax.yaxis.set_major_formatter(lambda v, _: f"{v / 1000:.0f}k")
    axes[0].set_ylabel("Insert gas (whole transaction)")
    axes[0].legend(loc="upper left")
    fig.suptitle(f"Insert gas vs members (mean of each {BUCKET} inserts; shading = min–max)",
                 x=0.01, ha="left", color=INK)
    fig.tight_layout()
    save(fig, "insert_gas")


# Constraints


def constraints() -> dict[str, list[dict]]:
    rows = read(RESULTS / "constraints.csv")
    return {s: [r for r in rows if r["structure"] == s] for s in ("skew-mmr", "leanimt")}


def plot_constraints_vs_capacity() -> None:
    data = constraints()
    fig, ax = plt.subplots(figsize=(7.5, 4.2))
    for structure, label, color in STRUCTURES[:2]:
        xs = [math.log2(int(r["capacity"])) for r in data[structure]]
        ys = [int(r["constraints"]) for r in data[structure]]
        ax.plot(xs, ys, color=color, linewidth=2, marker="o", markersize=4, label=label)
        ax.annotate(label, (xs[-1], ys[-1]), xytext=(6, 0), textcoords="offset points",
                    va="center", color=INK)
    ax.set_xlabel("log2(capacity)")
    ax.set_ylabel("Constraints (circom --O2)")
    ax.set_xlim(0, 36)
    ax.set_ylim(bottom=0)
    ax.set_title("Membership-proof constraints vs capacity", loc="left", color=INK)
    ax.legend(loc="upper left")
    fig.tight_layout()
    save(fig, "constraints_vs_capacity")


def smallest_fit(rows: list[dict], members: int) -> dict:
    """The smallest compiled circuit whose capacity holds `members`."""
    return min((r for r in rows if int(r["capacity"]) >= members), key=lambda r: int(r["size"]))


def plot_constraints_vs_members() -> None:
    data = constraints()
    # From 2: the smallest compiled skew-MMR circuit has 2 trees.
    members = list(range(2, MEMBERS + 1))
    fig, ax = plt.subplots(figsize=(7.5, 4.2))
    for structure, label, color in STRUCTURES[:2]:
        ys = [int(smallest_fit(data[structure], n)["constraints"]) for n in members]
        ax.step(members, ys, where="post", color=color, linewidth=2, label=label)
        ax.annotate(label, (members[-1], ys[-1]), xytext=(6, 0), textcoords="offset points",
                    va="center", color=INK)
    ax.set_xscale("log", base=2)
    ax.set_xticks([2, 4, 16, 64, 256, 1_024], ["2", "4", "16", "64", "256", "1,024"])
    ax.set_xlim(2, MEMBERS * 1.6)
    ax.set_xlabel("Members (log scale)")
    ax.set_ylabel("Constraints (circom --O2)")
    ax.set_ylim(bottom=0)
    ax.set_title("Membership-proof constraints, smallest circuit that fits", loc="left", color=INK)
    ax.legend(loc="upper left")
    fig.tight_layout()
    save(fig, "constraints_vs_members")


# JS performance

FUNCTIONS = ["Insert", "InsertMany", "GenerateProof", "VerifyProof"]
JS_NAMES = {"SkewMMR": "skew-mmr", "LeanIMT": "leanimt", "IMT": "binary-imt"}


def js_insert() -> dict[str, list[float]]:
    rows = read(RESULTS / "perf-js-insert.csv")
    return {s: [float(r[s]) for r in rows] for s, _, _ in STRUCTURES}


def js_functions() -> dict[tuple[str, str], float]:
    return {(JS_NAMES[r["structure"]], r["function"]): float(r["mean_ms"])
            for r in read(RESULTS / "perf-js-functions.csv")}


def plot_js_insert() -> None:
    data = js_insert()
    fig, ax = plt.subplots(figsize=(7.5, 4.2))
    for structure, label, color in STRUCTURES:
        line_with_band(ax, data[structure], label, color)
    ax.set_xlabel("Members")
    ax.set_ylabel("ms per insert")
    ax.set_xlim(0, len(data["skew-mmr"]))
    ax.set_ylim(bottom=0)
    ax.set_title(f"JS insert time vs members (mean of each {BUCKET} inserts; shading = min–max)",
                 loc="left", color=INK)
    ax.legend(loc="upper left")
    fig.tight_layout()
    save(fig, "perf_js_insert")


def plot_js_functions() -> None:
    data = js_functions()
    fig, ax = plt.subplots(figsize=(8, 4.2))
    width = 0.26
    for i, (structure, label, color) in enumerate(STRUCTURES):
        xs = [f + (i - 1) * (width + 0.02) for f in range(len(FUNCTIONS))]
        ax.bar(xs, [data[(structure, fn)] for fn in FUNCTIONS], width=width, color=color,
               label=label)
    ax.set_yscale("log")
    ax.yaxis.set_major_formatter(lambda v, _: f"{v:g}")
    ax.set_xticks(range(len(FUNCTIONS)), FUNCTIONS)
    ax.grid(axis="x", visible=False)
    ax.set_ylabel("Mean ms per call (log scale)")
    ax.set_title("JS functions, 100 iterations each (as in the leanIMT paper)", loc="left", color=INK)
    ax.legend(loc="upper right")
    fig.tight_layout()
    save(fig, "perf_js_functions")


# Tables


def tables() -> None:
    names = ["skew-mmr-keccak", "leanimt-keccak", "skew-mmr-poseidon", "leanimt-poseidon"]
    series = [gas(name) for name in names]
    print("| Average over first | skew-MMR keccak | leanIMT keccak | skew-MMR Poseidon | leanIMT Poseidon |")
    print("| ------------------ | --------------- | -------------- | ----------------- | ---------------- |")
    for n in [128, 256, 512, 1_024]:
        print(f"| {n:,} | " + " | ".join(f"{mean(s[:n]):,.0f}" for s in series) + " |")
    print()
    print("| Members | " + " | ".join(names) + " |  (mean of the 32 inserts ending here)")
    for n in [128, 256, 512, 1_024]:
        print(f"| {n:,} | " + " | ".join(f"{mean(s[n - BUCKET:n]):,.0f}" for s in series) + " |")
    print()

    # A skew-MMR with `d - 1` trees holds 2^d - d - 1 members, the same capacity as a depth-`d`
    # leanIMT to within `d + 1`.
    print("| Capacity | leanIMT | skew-MMR | Difference |")
    print("| -------- | ------- | -------- | ---------- |")
    data = constraints()
    skew = {int(r["size"]): int(r["constraints"]) for r in data["skew-mmr"]}
    for depth in [10, 16, 20, 24, 32]:
        lean = next(int(r["constraints"]) for r in data["leanimt"] if int(r["size"]) == depth)
        ours = skew[depth - 1]
        print(f"| 2^{depth} | {lean:,} | {ours:,} | {100 * (ours - lean) / lean:+.0f}% |")
    print()
    print("| Members | leanIMT | skew-MMR | Difference |  (smallest circuit that fits)")
    for n in [10, 100, 500, 1_000, 1_024]:
        lean = smallest_fit(data["leanimt"], n)
        ours = smallest_fit(data["skew-mmr"], n)
        a, b = int(lean["constraints"]), int(ours["constraints"])
        print(f"| {n:,} | {a:,} (depth {lean['size']}) | {b:,} ({ours['size']} trees) | {100 * (b - a) / a:+.0f}% |")
    print()

    inserts = js_insert()
    print("| JS insert, 1,000 iterations (ms) | " + " | ".join(l for _, l, _ in STRUCTURES) + " |")
    print(f"| Mean | " + " | ".join(f"{mean(inserts[s]):.3f}" for s, _, _ in STRUCTURES) + " |")
    print()
    funcs = js_functions()
    print("| JS, 100 iterations (mean ms) | " + " | ".join(l for _, l, _ in STRUCTURES) + " |")
    for fn in FUNCTIONS:
        print(f"| {fn} | " + " | ".join(f"{funcs[(s, fn)]:.4g}" for s, _, _ in STRUCTURES) + " |")


if __name__ == "__main__":
    plot_gas()
    plot_constraints_vs_capacity()
    plot_constraints_vs_members()
    plot_js_insert()
    plot_js_functions()
    tables()
