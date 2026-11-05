#!/usr/bin/env python3
"""Plots `results/gas/*.csv`, `results/constraints.csv` and `results/perf-js.csv` into
`results/*.svg`, and prints the markdown tables used in `README.md`. Run from `benchmarks/`."""

import csv
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

RESULTS = Path(__file__).resolve().parent.parent / "results"

SKEW, LEAN, BIMT, QIMT = "#2a78d6", "#eb6834", "#1baf7a", "#6250d6"
INK, MUTED, GRID = "#0b0b0b", "#52514e", "#e4e3df"
BUCKET = 100
# Every insert is measured up to DENSE members; past that, WINDOW inserts ending at each checkpoint.
DENSE = 10_000
WINDOW = 1_000
CHECKPOINTS = [50_000, 100_000, 500_000, 1_000_000]
# A fixed capacity above 1,000,000 members: leanIMT depth 20 (1,048,576), skew-MMR 19 trees
# (1,048,555).
FIXED = {"leanimt": 20, "skew-mmr": 19}

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


def gas(name: str) -> dict[int, int]:
    """Measured insert gas, keyed by the member count after the insert."""
    return {int(row["members"]): int(row["gas"]) for row in read(RESULTS / "gas" / f"{name}.csv")}


def window(data: dict[int, int], end: int, size: int) -> list[int]:
    return [data[n] for n in range(end - size + 1, end + 1)]


def mean(values: list[int]) -> float:
    return sum(values) / len(values)


def plot_gas() -> None:
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.2))
    for ax, hash_fn in zip(axes, ["keccak", "poseidon"]):
        for structure, label, color in [("skew-mmr", "skew-MMR", SKEW), ("leanimt", "leanIMT", LEAN)]:
            data = gas(f"{structure}-{hash_fn}")
            ends = list(range(BUCKET, DENSE + 1, BUCKET))
            dense = [window(data, end, BUCKET) for end in ends]
            ax.fill_between(ends, [min(w) for w in dense], [max(w) for w in dense],
                            color=color, alpha=0.12, linewidth=0)
            sparse = [window(data, end, WINDOW) for end in CHECKPOINTS]
            for end, w in zip(CHECKPOINTS, sparse):
                ax.plot([end, end], [min(w), max(w)], color=color, alpha=0.35, linewidth=6,
                        solid_capstyle="butt")
            xs = ends + CHECKPOINTS
            ys = [mean(w) for w in dense + sparse]
            ax.plot(xs, ys, color=color, linewidth=2, label=label)
            ax.plot(CHECKPOINTS, ys[-len(CHECKPOINTS):], color=color, linestyle="none",
                    marker="o", markersize=5)
            ax.annotate(label, (xs[-1], ys[-1]), xytext=(8, 0), textcoords="offset points",
                        va="center", color=INK)
        ax.set_xscale("log")
        ax.set_xlim(BUCKET, 3_000_000)
        ax.set_xticks([100, 1_000, 10_000, 100_000, 1_000_000], ["100", "1k", "10k", "100k", "1M"])
        ax.set_title(f"{'Keccak' if hash_fn == 'keccak' else 'Poseidon'} node hash",
                     loc="left", color=INK)
        ax.set_xlabel("Members (log scale)")
        ax.set_ylim(bottom=0)
        ax.yaxis.set_major_formatter(lambda v, _: f"{v / 1000:.0f}k")
    axes[0].set_ylabel("Insert gas (whole transaction)")
    axes[0].legend(loc="upper left")
    fig.suptitle(f"Insert gas vs members (mean; shading = min–max)", x=0.01, ha="left", color=INK)
    fig.tight_layout()
    fig.savefig(RESULTS / "insert_gas.svg", metadata={"Date": None})


PERF = [
    ("skew-mmr", "skew-MMR", SKEW),
    ("leanimt", "leanIMT", LEAN),
    ("binary-imt", "binary IMT", BIMT),
    ("quinary-imt", "quinary IMT", QIMT),
]


def perf() -> dict[tuple[str, str], list[tuple[int, float]]]:
    series: dict[tuple[str, str], list[tuple[int, float]]] = {}
    for row in read(RESULTS / "perf-js.csv"):
        series.setdefault((row["structure"], row["op"]), []).append(
            (int(row["leaves"]), float(row["us_per_op"])))
    return series


def short(n: int) -> str:
    return f"{n // 1_000_000}M" if n >= 1_000_000 else f"{n // 1_000}k" if n >= 1_000 else str(n)


def plot_perf() -> None:
    data = perf()
    fig, axes = plt.subplots(1, 3, figsize=(12, 4))
    for ax, op in zip(axes, ["insert", "prove", "verify"]):
        for structure, label, color in PERF:
            points = data[(structure, op)]
            xs = [math.log2(n) for n, _ in points]
            ys = [us for _, us in points]
            ax.plot(xs, ys, color=color, linewidth=2, marker="o", markersize=5, label=label)
        if op == "verify":
            ax.set_ylim(bottom=0)
            ax.yaxis.set_major_formatter(lambda v, _: f"{v:,.0f}")
        else:
            ax.set_yscale("log")
            ax.yaxis.set_major_formatter(lambda v, _: f"{v:g}")
        ticks = [1_000, 10_000, 100_000, 1_000_000]
        ax.set_xticks([math.log2(n) for n in ticks], [short(n) for n in ticks])
        ax.set_xlabel("Leaves")
        ax.set_title(f"{op.capitalize()}{'' if op == 'verify' else ' (log scale)'}", loc="left", color=INK)
    axes[0].set_ylabel("µs per operation")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", ncol=len(PERF))
    fig.suptitle("Off-chain performance (TypeScript, poseidon-lite)", x=0.01, ha="left", color=INK)
    fig.tight_layout(rect=(0, 0.07, 1, 1))
    fig.savefig(RESULTS / "perf_js.svg", metadata={"Date": None})


def constraints() -> dict[str, list[dict]]:
    rows = read(RESULTS / "constraints.csv")
    return {s: [r for r in rows if r["structure"] == s] for s in ("skew-mmr", "leanimt")}


def plot_constraints_vs_capacity() -> None:
    data = constraints()
    fig, ax = plt.subplots(figsize=(7.5, 4.2))
    for structure, label, color, size in [("skew-mmr", "skew-MMR", SKEW, "trees"),
                                           ("leanimt", "leanIMT", LEAN, "depth")]:
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
    fig.savefig(RESULTS / "constraints_vs_capacity.svg", metadata={"Date": None})


def plot_constraints_vs_members() -> None:
    data = constraints()
    members = list(range(10_000, 1_000_001, 10_000))
    fig, ax = plt.subplots(figsize=(7.5, 4.2))
    for structure, label, color in [("skew-mmr", f"skew-MMR, {FIXED['skew-mmr']} trees", SKEW),
                                    ("leanimt", f"leanIMT, depth {FIXED['leanimt']}", LEAN)]:
        row = next(r for r in data[structure] if int(r["size"]) == FIXED[structure])
        ys = [int(row["constraints"])] * len(members)
        ax.plot(members, ys, color=color, linewidth=2, label=f"{label} (capacity {int(row['capacity']):,})")
        ax.annotate(f"{ys[0]:,}", (members[-1], ys[-1]), xytext=(6, 0), textcoords="offset points",
                    va="center", color=INK)
    ax.set_xlabel("Members")
    ax.set_ylabel("Constraints (circom --O2)")
    ax.set_xlim(0, 1_100_000)
    ax.set_ylim(0, 6_500)
    ax.xaxis.set_major_formatter(lambda v, _: short(int(v)))
    ax.set_title("Membership-proof constraints vs members, fixed capacity", loc="left", color=INK)
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(RESULTS / "constraints_vs_members.svg", metadata={"Date": None})


def tables() -> None:
    print("| Members | skew-MMR keccak | leanIMT keccak | skew-MMR Poseidon | leanIMT Poseidon |")
    print("| ------- | --------------- | -------------- | ----------------- | ---------------- |")
    series = [gas(name) for name in
              ["skew-mmr-keccak", "leanimt-keccak", "skew-mmr-poseidon", "leanimt-poseidon"]]
    for members in [1_000, DENSE] + CHECKPOINTS:
        cells = [f"{mean(window(data, members, WINDOW)):,.0f}" for data in series]
        print(f"| {short(members)} | " + " | ".join(cells) + " |")
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

def more_tables() -> None:
    print()
    data = perf()
    for op in ["insert", "prove", "verify"]:
        print(f"| {op} (µs/op) | " + " | ".join(label for _, label, _ in PERF) + " |")
        print("| --- |" + " --- |" * len(PERF))
        for i, (n, _) in enumerate(data[("skew-mmr", op)]):
            cells = [f"{data[(s, op)][i][1]:,.1f}" for s, _, _ in PERF]
            print(f"| {n:,} leaves | " + " | ".join(cells) + " |")
        print()


if __name__ == "__main__":
    plot_perf()
    more_tables()
    plot_gas()
    plot_constraints_vs_capacity()
    plot_constraints_vs_members()
    tables()
