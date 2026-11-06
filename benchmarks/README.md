# Skew-MMR vs zk-kit's Merkle trees

Skew-MMR compared with zk-kit's [leanIMT](https://github.com/zk-kit/zk-kit.solidity/tree/main/packages/lean-imt) and [IMT](https://github.com/zk-kit/zk-kit/tree/main/packages/imt), up to 1,024 members. All hashes are Poseidon.

| At 1,024 members           | skew-MMR | leanIMT |
| -------------------------- | -------- | ------- |
| Mean insert gas            | 71,948   | 185,610 |
| Proof constraints          | 2,867    | 2,463   |
| JS insert (ms)             | 0.111    | 0.849   |
| JS verify (ms, 100 members) | 0.753    | 1.22    |

## Insert gas

Gas for each insert into an empty tree, as a full transaction.

![Insert gas vs members](results/insert_gas.svg)

| Mean over first | skew-MMR | leanIMT |
| --------------- | -------- | ------- |
| 128 members     | 80,762   | 147,418 |
| 256 members     | 75,791   | 159,889 |
| 512 members     | 73,250   | 172,666 |
| 1,024 members   | 71,948   | 185,610 |

Skew-MMR hashes at most once per insert, so its cost stays flat. LeanIMT updates every level, so its cost grows with the number of members.

## Proof constraints

Circom constraints (`--O2`) for skew-MMR's [`inclusion.circom`](../circuits/inclusion.circom) and zk-kit's `binary-merkle-root` (used by leanIMT and IMT). Each size uses the smallest circuit that holds it.

![Constraints vs members](results/constraints_vs_members.svg)

| Members | leanIMT | skew-MMR | Difference |
| ------- | ------- | -------- | ---------- |
| 10      | 987     | 886      | −10%       |
| 100     | 1,725   | 1,735    | +1%        |
| 500     | 2,217   | 2,301    | +4%        |
| 1,000   | 2,463   | 2,584    | +5%        |
| 1,024   | 2,463   | 2,867    | +16%       |

Skew-MMR needs its next circuit size a few members before each power of two, so the gap briefly widens there.

![Constraints vs capacity](results/constraints_vs_capacity.svg)

## JS performance

[tinybench](https://github.com/tinylibs/tinybench) on `@zk-kit/imt`, `@zk-kit/lean-imt` and [`packages/`](../packages), with `poseidon-lite`. Each iteration adds one member to a growing tree.

![JS insert time vs members](results/perf_js_insert.svg)

![JS functions](results/perf_js_functions.svg)

| Mean ms, 100 iterations | skew-MMR | leanIMT | IMT   |
| ----------------------- | -------- | ------- | ----- |
| Insert                  | 0.100    | 0.508   | 0.937 |
| InsertMany              | 5.50     | 8.66    | 94.2  |
| GenerateProof           | 0.0052   | 0.0067  | 0.0069 |
| VerifyProof             | 0.753    | 1.22    | 1.18  |

## Running

From the repo root, in `nix develop`:

```bash
just bench
```
