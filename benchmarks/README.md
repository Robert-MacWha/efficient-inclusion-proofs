# Skew-MMR vs zk-kit's Merkle trees

Skew-MMR compared with zk-kit's [leanIMT](https://github.com/zk-kit/zk-kit.solidity/tree/main/packages/lean-imt) and [IMT](https://github.com/zk-kit/zk-kit/tree/main/packages/imt). All hashing uses the original Poseidon, through the same libraries zk-kit uses.

**Summary:**

- **Insert gas:** skew-MMR's cost is flat: ~52k gas with keccak and ~71k with Poseidon. LeanIMT's cost grows by ~4k (keccak) or ~12.5k (Poseidon) each time the number of members doubles, so the gap keeps widening. At 10,000 members leanIMT costs 2.1× (keccak) or 3.6× (Poseidon) as much.
- **Proof constraints:** skew-MMR needs 5–12% more than leanIMT at the same capacity.
- **JS insert:** skew-MMR is 10× faster than leanIMT at 16k leaves. JS verify is ~20% slower.

## Insert gas

Gas for each of the first 10,000 inserts into an empty tree. Each insert is measured as a full transaction, as zk-kit's gas reports do.

![Insert gas vs members](results/insert_gas.svg)

| Members | skew-MMR keccak | leanIMT keccak | skew-MMR Poseidon | leanIMT Poseidon |
| ------- | --------------- | -------------- | ----------------- | ---------------- |
| 1,000   | 51,644          | 91,007         | 69,711            | 210,974          |
| 5,000   | 51,705          | 105,074        | 70,149            | 234,767          |
| 10,000  | 51,766          | 107,833        | 70,586            | 253,986          |

Skew-MMR does at most one hash per insert, so its cost doesn't depend on size. LeanIMT updates one node per level, so its cost grows with log2(members).

**Why leanIMT's keccak and Poseidon curves go in opposite directions.** At each level, a leanIMT insert either hashes or writes to storage, depending on that bit of the leaf's index. Right after a power of two, the index is `1000…0`, which means few hashes and many writes. As the index climbs toward the next power of two, the mix shifts back toward hashes.

- **Keccak:** writes are the expensive part, so gas jumps up at each power of two.
- **Poseidon:** hashes are the expensive part, so gas drops at each power of two.

LeanIMT also stores a leaf → index mapping on every insert (~22k gas), which skew-MMR doesn't have.

## Membership-proof constraints

Circom constraint counts (`--O2`):

- **skew-MMR:** [`circuits/inclusion.circom`](../circuits/inclusion.circom).
- **leanIMT:** zk-kit's `binary-merkle-root`, which Semaphore uses. zk-kit uses the same circuit for the binary IMT.

![Constraints vs capacity](results/constraints_vs_capacity.svg)

| Capacity | leanIMT | skew-MMR | Difference |
| -------- | ------- | -------- | ---------- |
| 2^10     | 2,463   | 2,584    | +5%        |
| 2^16     | 3,939   | 4,282    | +9%        |
| 2^20     | 4,923   | 5,414    | +10%       |
| 2^24     | 5,907   | 6,546    | +11%       |
| 2^32     | 7,875   | 8,810    | +12%       |

Each level costs leanIMT 246 constraints and skew-MMR 283, mainly because skew-MMR hashes 3 inputs per level instead of 2.

Both circuits have a fixed size, so the count doesn't change as the tree fills:

![Constraints vs members](results/constraints_vs_members.svg)

## JS performance

This follows zk-kit's [JS benchmark](https://github.com/zk-kit/zk-kit/tree/main/benchmarks), with the same libraries, hash and tree sizes: insert all leaves, prove half of them, verify those proofs. Times are µs per operation.

![JS performance](results/perf_js.svg)

| 16,384 leaves | skew-MMR | leanIMT | binary IMT | quinary IMT |
| ------------- | -------- | ------- | ---------- | ----------- |
| Insert        | 114      | 1,167   | 2,364      | 2,591       |
| Prove         | 0.9      | 83      | 0.8        | 0.7         |
| Verify        | 2,814    | 2,301   | 2,311      | 2,630       |

- **Insert and verify** are dominated by hashing, so they follow the hash counts above.
- **LeanIMT's slow prove** is a zk-kit quirk: each proof copies the whole leaf array.
- **Harness difference:** zk-kit's own harness keeps timing after the work runs out, which inflates its numbers. This one times only real operations.

## Running

From the repo root, in `nix develop`:

```bash
just bench
```

The JS benchmark takes about 15 minutes. Results are written to `results/`.
