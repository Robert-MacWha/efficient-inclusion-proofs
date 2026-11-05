# Skew-MMR vs leanIMT

Compares the binary skew-MMR (`contracts/`, `circuits/`) with [zk-kit's leanIMT](https://github.com/privacy-scaling-explorations/zk-kit.solidity/tree/main/packages/lean-imt) on:

- **Insert gas** vs the number of members.
- **Membership-proof constraints** vs capacity, and vs members at a fixed capacity.

## Results

### Insert gas

Each of the 10,000 inserts into an initially empty structure is measured on its own. The table and chart show the mean over each run of 100 inserts. Raw per-insert data is in `results/gas/*.csv`.

![Insert gas vs members](results/insert_gas.svg)

| Members | skew-MMR keccak | leanIMT keccak | skew-MMR Poseidon | leanIMT Poseidon |
| ------- | --------------- | -------------- | ----------------- | ---------------- |
| 100     | 43,592          | 58,175         | 60,484            | 117,311          |
| 1,000   | 30,428          | 69,791         | 47,295            | 187,258          |
| 2,500   | 30,550          | 80,552         | 48,120            | 195,027          |
| 5,000   | 30,489          | 83,858         | 47,708            | 211,051          |
| 7,500   | 30,550          | 82,220         | 48,120            | 220,636          |
| 10,000  | 30,550          | 86,617         | 48,120            | 230,271          |

Skew-MMR is flat. It hashes at most once per insert, and only every other insert on average. Its spikes come from the first write to a new frontier slot, and from the first 64 inserts filling the history ring. LeanIMT grows with `log2(members)`. An insert hashes once for each trailing 1 bit of its index, and the tree gets one level deeper at every power of two.

### Membership-proof constraints

Compiled with `circom --O2`, which folds away all linear constraints. Skew-MMR uses `SkewMmrInclusion(MAX_TREES)` from [`circuits/inclusion.circom`](../circuits/inclusion.circom). LeanIMT uses `BinaryMerkleRoot(MAX_DEPTH)` from `@zk-kit/binary-merkle-root.circom`, the circuit Semaphore v4 uses.

![Constraints vs capacity](results/constraints_vs_capacity.svg)

A skew-MMR capped at `t` trees holds `2^(t+1) - t - 2` members. So `t = d - 1` trees falls `d + 1` members short of a depth-`d` leanIMT, and `t = d` holds about twice as many.

| leanIMT depth | leanIMT constraints | skew-MMR, depth − 1 trees | skew-MMR, depth trees |
| ------------- | ------------------- | ------------------------- | --------------------- |
| 10 (2^10)     | 2,463               | 2,584 (+5%)               | 2,867 (+16%)          |
| 16 (2^16)     | 3,939               | 4,282 (+9%)               | 4,565 (+16%)          |
| 20 (2^20)     | 4,923               | 5,414 (+10%)              | 5,697 (+16%)          |
| 24 (2^24)     | 5,907               | 6,546 (+11%)              | 6,829 (+16%)          |
| 32 (2^32)     | 7,875               | 8,810 (+12%)              | 9,093 (+15%)          |

Each extra level costs leanIMT 246 constraints (one `Poseidon(2)` plus a mux). It costs skew-MMR 283 (one `Poseidon(3)`, a switcher and mux, frontier unpacking, and index bookkeeping). At equal capacity, skew-MMR pays one 3-input hash per level where leanIMT pays one 2-input hash. So the gap widens slowly with depth.

![Constraints vs members](results/constraints_vs_members.svg)

At a fixed capacity, both circuits are padded to their maximum size, so the count does not depend on the number of members. Both lines are flat by construction. They are plotted from the compiled counts at 100…10,000 members.

## Method and caveats

- **Gas measured** is the execution gas of the `insert` call (`vm.lastCallGas().gasTotalUsed`). Each insert runs after `vm.cool(target)`, so storage is cold as in a fresh transaction. It excludes the 21,000 base cost, calldata, and the cold access to the target account. Those are the same for every structure.
- **Poseidon variants** use `poseidon-solidity`: `PoseidonT4` (3 inputs) for skew-MMR and `PoseidonT3` (2 inputs) for leanIMT. These are external libraries, and after the first call their account stays warm. A real transaction that hashes pays another 2,600 gas for the cold library access.
- **Skew-MMR** is `SkewMmrWithHistory` (max 26 trees, history ring of 64), so each insert also commits the frontier to the history ring. The Poseidon variant swaps only the node hash. The frontier chain and commitment stay keccak, as in `LibSkewMmr`.
- **LeanIMT** is `InternalLeanIMT` from `@zk-kit/lean-imt.sol@2.0.1`, unmodified, for Poseidon. For keccak it is a copy with only the hash swapped (`src/LeanImtKeccakLib.sol`). Every insert writes the `leaves[leaf] = index` mapping, a zero-to-nonzero `SSTORE` of about 22,100 gas. This is part of the library's design (it gives `has`/`indexOf` and rejects duplicates), and Semaphore relies on it.

## Running

Inside the repo's dev shell (`nix develop`):

```bash
just bench
```

That runs, from `benchmarks/`:

```bash
pnpm install                          # leanIMT, poseidon-solidity, circom libraries
forge install foundry-rs/forge-std@v1.16.2 --no-git
forge test                            # writes results/gas/*.csv
python3 scripts/constraints.py        # writes results/constraints.csv
python3 scripts/plot.py               # writes results/*.svg, prints the tables above
```
