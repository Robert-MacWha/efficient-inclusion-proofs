# Efficient inclusion proofs

[AI:W](https://0rwx.com/?ref=explainx)

This repo contains set commitment structures that allow a caller to cheaply prove that an element is included in a given set. The goal is to create a structure that can replace leanIMT for privacy protocols. This means optimizing for:
- Low gas cost when appending an element to the set.
- Low gas cost when verifying the root of the set commitment on-chain.
- Low constraint count when verifying an inclusion proof in-circuit.

## Overview

- [skew-mmr](crates/skew-mmr): A modified Merkle Mountain Range that uses skew-binary carrying rules. Bounds appends at one hash.
  - [lean](lean): Lean proof that the skew-mmr circuit decides what the native verifier decides.
- [hash-chain](crates/hash-chain): A hash chain that keeps a running chain per level, each batch of `BATCH` elements closing and folding into the level above.  Average append cost is 1 hash, with rare cases of 2, 3, or 4 hashes.

> skew-mmr is *probably* the better choice for privacy protocols. It has a higher average append gas cost, but:
>   1. takes exactly one hash per append, where the hash chain can take up to 4,
>   2. requires significantly fewer in-circuit hashes to verify an inclusion proof, and
>   3. has a more predictable gas cost for appending elements.
>
> Because of the hash-chain's batch structure, appending an element can rarely require several times the expected number of hashes, which makes its gas cost difficult to estimate ahead of time.

## Benchmarks

Comparison with zk-kit's leanIMT and IMT: [bench/](bench/README.md).

### Hashes

Append columns measure the number of hashes required to append a single element. Proof columns measure the number of hashes required to verify an inclusion proof for a single element.

| Structure   | Append mean | Append max | Proof mean  | Proof max |
| ----------- | ----------- | ---------- | ----------- | --------- |
| Skew-MMR    | 1           | 1          | log2(n) - 1 | log2(n)   |
| LeanIMT     | log2(n) / 2 | log2(n)    | log2(n)     | log2(n)   |
| Merkle tree | depth       | depth      | depth       | depth     |
| Hash chain  | 1.03        | 4          | 95          | 97        |

### Gas

Execution gas of each call with keccak256, measured by `contracts/test/*.gas.t.sol`:

```bash
cd contracts && forge test --mc "SkewMmrWithHistoryGasTest|HashChainVerifierGasTest" --gas-report
```

| Call                            | Min    | Mean   | Max    |
| ------------------------------- | ------ | ------ | ------ |
| Skew-MMR `append`               | 13,120 | 14,405 | 55,720 |
| Skew-MMR `verifyFrontier`       | 3,081  | 4,080  | 5,265  |
| Hash chain `append`             | 10,805 | 11,090 | 24,254 |
| Hash chain `verifyAccumulators` | 4,332  | 4,332  | 4,332  |

For privacy protocols, an algebraic hash like Poseidon will be required. Add its cost for each hash in the table above. See [bench/](bench/README.md) for full-transaction gas with Poseidon.
