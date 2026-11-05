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
# A fixed capacity above 10,000 members: leanIMT depth 14 (16,384), skew-MMR 13 trees (16,369).
FIXED = {"leanimt": 14, "skew-mmr": 13}

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


def buckets(name: str):
    """Mean, min and max insert gas over each run of `BUCKET` inserts, keyed by the last member."""
    gas = [int(row["gas"]) for row in read(RESULTS / "gas" / f"{name}.csv")]
    xs, mean, lo, hi = [], [], [], []
    for end in range(BUCKET, len(gas) + 1, BUCKET):
        window = gas[end - BUCKET:end]
        xs.append(end)
        mean.append(sum(window) / BUCKET)
        lo.append(min(window))
        hi.append(max(window))
    return xs, mean, lo, hi, gas


def plot_gas() -> None:
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.2))
    for ax, hash_fn in zip(axes, ["keccak", "poseidon"]):
        for structure, label, color in [("skew-mmr", "skew-MMR", SKEW), ("leanimt", "leanIMT", LEAN)]:
            xs, mean, lo, hi, _ = buckets(f"{structure}-{hash_fn}")
            ax.fill_between(xs, lo, hi, color=color, alpha=0.12, linewidth=0)
            ax.plot(xs, mean, color=color, linewidth=2, label=f"{label} (mean)")
            ax.annotate(label, (xs[-1], mean[-1]), xytext=(6, 0), textcoords="offset points",
                        va="center", color=INK)
        ax.set_title(f"{'Keccak' if hash_fn == 'keccak' else 'Poseidon'} node hash",
                     loc="left", color=INK)
        ax.set_xlabel("Members after insert")
        ax.set_ylim(bottom=0)
        ax.set_xlim(0, 11_300)
        ax.yaxis.set_major_formatter(lambda v, _: f"{v / 1000:.0f}k")
    axes[0].set_ylabel("Insert gas (whole transaction)")
    axes[0].legend(loc="upper left")
    fig.suptitle(f"Insert gas vs members (mean of each {BUCKET} inserts; band = min–max)",
                 x=0.01, ha="left", color=INK)
    fig.tight_layout()
    fig.savefig(RESULTS / "insert_gas.svg", metadata={"Date": None})


# Every Poseidon insert-gas series, as (file, label, color).
POSEIDON_GAS = [
    ("skew-mmr-poseidon", "skew-MMR", SKEW),
    ("leanimt-poseidon", "leanIMT", LEAN),
    ("binary-imt-16-poseidon", "binary IMT, depth 16", BIMT),
    ("binary-imt-32-poseidon", "binary IMT, depth 32", BIMT),
    ("quinary-imt-7-poseidon", "quinary IMT, depth 7", QIMT),
    ("quinary-imt-14-poseidon", "quinary IMT, depth 14", QIMT),
]
STEADY = (9_001, 10_000)


def steady_mean(name: str) -> float:
    gas = [int(row["gas"]) for row in read(RESULTS / "gas" / f"{name}.csv")]
    window = gas[STEADY[0] - 1:STEADY[1]]
    return sum(window) / len(window)


def plot_gas_all() -> None:
    fig, ax = plt.subplots(figsize=(8, 3.6))
    labels = [label for _, label, _ in POSEIDON_GAS]
    means = [steady_mean(name) for name, _, _ in POSEIDON_GAS]
    ys = list(range(len(labels)))[::-1]
    ax.barh(ys, means, color=[color for _, _, color in POSEIDON_GAS], height=0.6)
    for y, mean in zip(ys, means):
        ax.annotate(f"{mean / 1000:,.0f}k", (mean, y), xytext=(4, 0), textcoords="offset points",
                    va="center", color=INK)
    ax.set_yticks(ys, labels)
    ax.grid(axis="y", visible=False)
    ax.set_xlim(0, max(means) * 1.12)
    ax.xaxis.set_major_formatter(lambda v, _: f"{v / 1000:.0f}k")
    ax.set_xlabel(f"Mean insert gas, members {STEADY[0]:,}–{STEADY[1]:,} (whole transaction)")
    ax.set_title("Insert gas with Poseidon, zk-kit trees vs skew-MMR", loc="left", color=INK)
    fig.tight_layout()
    fig.savefig(RESULTS / "insert_gas_all.svg", metadata={"Date": None})


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


def plot_perf() -> None:
    data = perf()
    fig, axes = plt.subplots(1, 3, figsize=(12, 4))
    for ax, op in zip(axes, ["insert", "prove", "verify"]):
        for structure, label, color in PERF:
            points = data[(structure, op)]
            xs = [math.log2(n) for n, _ in points]
            ys = [us for _, us in points]
            ax.plot(xs, ys, color=color, linewidth=2, marker="o", markersize=5, label=label)
        ax.set_yscale("log")
        ax.set_xticks([3, 7, 10, 14], ["8", "128", "1,024", "16,384"])
        ax.set_xlabel("Leaves")
        ax.set_title(op.capitalize(), loc="left", color=INK)
        ax.yaxis.set_major_formatter(lambda v, _: f"{v:g}")
    axes[0].set_ylabel("µs per operation (log scale)")
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
    members = list(range(100, 10_001, 100))
    fig, ax = plt.subplots(figsize=(7.5, 4.2))
    for structure, label, color, size in [("skew-mmr", "skew-MMR, 13 trees", SKEW, "trees"),
                                           ("leanimt", "leanIMT, depth 14", LEAN, "depth")]:
        row = next(r for r in data[structure] if int(r["size"]) == FIXED[structure])
        ys = [int(row["constraints"])] * len(members)
        ax.plot(members, ys, color=color, linewidth=2, label=f"{label} (capacity {int(row['capacity']):,})")
        ax.annotate(f"{ys[0]:,}", (members[-1], ys[-1]), xytext=(6, 0), textcoords="offset points",
                    va="center", color=INK)
    ax.set_xlabel("Members")
    ax.set_ylabel("Constraints (circom --O2)")
    ax.set_xlim(0, 11_000)
    ax.set_ylim(0, 4_500)
    ax.set_title("Membership-proof constraints vs members, fixed capacity", loc="left", color=INK)
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(RESULTS / "constraints_vs_members.svg", metadata={"Date": None})


def tables() -> None:
    print("| Members | skew-MMR keccak | leanIMT keccak | skew-MMR Poseidon | leanIMT Poseidon |")
    print("| ------- | --------------- | -------------- | ----------------- | ---------------- |")
    series = {name: buckets(name) for name in
              ["skew-mmr-keccak", "leanimt-keccak", "skew-mmr-poseidon", "leanimt-poseidon"]}
    for members in [100, 1_000, 2_500, 5_000, 7_500, 10_000]:
        i = members // BUCKET - 1
        cells = [f"{round(s[1][i]):,}" for s in series.values()]
        print(f"| {members:,} | " + " | ".join(cells) + " |")
    print()
    # A skew-MMR with `d` trees holds 2^(d+1) - d - 2, so `d - 1` trees fall `d + 1` members short
    # of a depth-`d` leanIMT and `d` trees hold about twice as many.
    print("| leanIMT depth | leanIMT constraints | skew-MMR, depth - 1 trees | skew-MMR, depth trees |")
    print("| ------------- | ------------------- | ------------------------- | --------------------- |")
    data = constraints()
    skew = {int(r["size"]): int(r["constraints"]) for r in data["skew-mmr"]}
    for depth in [10, 16, 20, 24, 32]:
        lean = next(int(r["constraints"]) for r in data["leanimt"] if int(r["size"]) == depth)
        cells = [f"{skew[t]:,} ({100 * (skew[t] - lean) / lean:+.0f}%)" for t in (depth - 1, depth)]
        print(f"| {depth} (2^{depth}) | {lean:,} | " + " | ".join(cells) + " |")

def more_tables() -> None:
    print()
    print(f"| Structure | Mean insert gas, members {STEADY[0]:,}–{STEADY[1]:,} |")
    print("| --------- | ------------------------------------- |")
    for name, label, _ in POSEIDON_GAS:
        print(f"| {label} | {steady_mean(name):,.0f} |")
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
    plot_gas_all()
    plot_perf()
    more_tables()
    plot_gas()
    plot_constraints_vs_capacity()
    plot_constraints_vs_members()
    tables()
