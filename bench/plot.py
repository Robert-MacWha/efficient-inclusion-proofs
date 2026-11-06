#!/usr/bin/env python3
"""Plots `results/*.csv` into `results/*.svg` and prints the numbers used in `README.md`."""

import csv
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

RESULTS = Path(__file__).resolve().parent / "results"
COLORS = {"skew-MMR": "#2a78d6", "leanIMT": "#eb6834", "IMT": "#1baf7a"}
INK = "#0b0b0b"
BUCKET = 32

plt.rcParams.update({
    "font.size": 10,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "grid.color": "#e4e3df",
    "legend.frameon": False,
    "svg.fonttype": "none",
    "svg.hashsalt": "skew-mmr",  # stable ids, so unchanged data gives unchanged SVGs
})


def read(name: str) -> list[dict]:
    with (RESULTS / name).open() as f:
        return list(csv.DictReader(f))


def mean(values) -> float:
    values = list(values)
    return sum(values) / len(values)


def save(fig, ax, name: str, title: str) -> None:
    ax.set_title(title, loc="left", color=INK)
    ax.legend(loc="upper left")
    fig.tight_layout()
    fig.savefig(RESULTS / f"{name}.svg", metadata={"Date": None})


def plot_bucketed(ax, values: list[float], label: str) -> None:
    """Mean of each `BUCKET` consecutive values, with their min–max shaded."""
    ends = range(BUCKET, len(values) + 1, BUCKET)
    windows = [values[end - BUCKET:end] for end in ends]
    ax.fill_between(ends, [min(w) for w in windows], [max(w) for w in windows],
                    color=COLORS[label], alpha=0.12, linewidth=0)
    ax.plot(ends, [mean(w) for w in windows], color=COLORS[label], linewidth=2, label=label)


gas = {label: [int(r["gas"]) for r in read(f"gas-{name}.csv")]
       for label, name in [("skew-MMR", "skew-mmr"), ("leanIMT", "leanimt")]}
fig, ax = plt.subplots(figsize=(7.5, 4.2))
for label, values in gas.items():
    plot_bucketed(ax, values, label)
ax.set(xlabel="Members", ylabel="Gas per insert", xlim=(0, 1_024), ylim=(0, None))
ax.yaxis.set_major_formatter(lambda v, _: f"{v / 1000:.0f}k")
save(fig, ax, "insert_gas", f"Insert gas (mean of each {BUCKET}; shading = min–max)")

circuits = read("constraints.csv")
by_structure = {label: [r for r in circuits if r["structure"] == name]
                for label, name in [("skew-MMR", "skew-mmr"), ("leanIMT", "leanimt")]}


def smallest_fit(label: str, members: int) -> int:
    rows = [r for r in by_structure[label] if int(r["capacity"]) >= members]
    return int(min(rows, key=lambda r: int(r["size"]))["constraints"])


fig, ax = plt.subplots(figsize=(7.5, 4.2))
members = range(2, 1_025)
for label in by_structure:
    ax.step(members, [smallest_fit(label, n) for n in members], where="post",
            color=COLORS[label], linewidth=2, label=label)
ax.set_xscale("log", base=2)
ax.set_xticks([2, 16, 128, 1_024], ["2", "16", "128", "1,024"])
ax.set(xlabel="Members", ylabel="Constraints", ylim=(0, None))
save(fig, ax, "constraints_vs_members", "Proof constraints, smallest circuit that fits")

fig, ax = plt.subplots(figsize=(7.5, 4.2))
for label, rows in by_structure.items():
    ax.plot([math.log2(int(r["capacity"])) for r in rows], [int(r["constraints"]) for r in rows],
            color=COLORS[label], linewidth=2, marker="o", markersize=4, label=label)
ax.set(xlabel="log2(capacity)", ylabel="Constraints", ylim=(0, None))
save(fig, ax, "constraints_vs_capacity", "Proof constraints vs capacity")

perf = (RESULTS / "perf-js.csv").read_text().split("\n\n")
inserts = list(csv.DictReader(perf[0].splitlines()))
means = {(r["structure"], r["function"]): float(r["mean_ms"])
         for r in csv.DictReader(perf[1].splitlines())}
fig, ax = plt.subplots(figsize=(7.5, 4.2))
for label in COLORS:
    plot_bucketed(ax, [float(r[label]) for r in inserts], label)
ax.set(xlabel="Members", ylabel="ms per insert", xlim=(0, 1_024), ylim=(0, None))
save(fig, ax, "perf_js_insert", f"JS insert time (mean of each {BUCKET}; shading = min–max)")

print("Mean insert gas over the first N members")
for n in [128, 256, 512, 1_024]:
    print(f"  {n:>5}: " + "  ".join(f"{label} {mean(v[:n]):,.0f}" for label, v in gas.items()))
print("Constraints, smallest circuit that fits")
for n in [10, 100, 500, 1_000, 1_024]:
    print(f"  {n:>5}: " + "  ".join(f"{label} {smallest_fit(label, n):,}" for label in by_structure))
print("JS mean ms")
for fn in ["Insert", "GenerateProof", "VerifyProof"]:
    print(f"  {fn}: " + "  ".join(f"{label} {means[(label, fn)]:.4g}" for label in COLORS))
