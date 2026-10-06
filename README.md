# Efficient inclusion proofs

This repo contains set commitment structures that allow a caller to cheaply prove that an element is included in a given set. The goal is to create a structure that can replace leanIMT for privacy protocols. This means optimizing for:
- Low gas cost when appending an element to the set.
- Low gas cost when verifying the root of the set commitment on-chain.
- Low constraint count when verifying an inclusion proof in-circuit.

## Overview

- [skew-mmr](crates/skew-mmr): A modified Merkle Mountain Range that uses skew-binary carrying rules. Bounds appends at one hash.
- [hash-chain](crates/hash-chain): A hash chain that keeps a running chain per level, each batch of `BATCH` elements closing and folding into the level above.  Average append cost is 1 hash, with rare cases of 2, 3, or 4 hashes.

> skew-mmr is *probably* the better choice for privacy protocols. It has a higher average gas cost (~62k vs ~40k using poseidon2), but:
>   1. has a lower maximum gas cost (~75k vs ~105k using poseidon2)
>   2. requires significantly fewer in-circuit hashes to verify an inclusion proof, and
>   3. has a more predictable gas cost for appending elements. 
> 
> Because of the hash-chain's batch structure, appending an element can rarely require 2-4x the expected gas cost, which makes it difficult to estimate ahead of time.

## Benchmarks

Measured by `contracts/test/*.gas.t.sol`.

### Hashes

Append columns measure the number of hashes required to append a single element. Proof column measures the number of hashes required to verify an inclusion proof for a single element.

| Structure  | Append mean | Append max | Proof mean    | Proof max   |
| ---------- | ----------- | ---------- | ------------- | ----------- |
| Skew-MMR   | 0.5         | 1          | log2(n) - 1.5 | log2(n) - 1 |
| Hash chain | 1.03        | 5          | 144           | 160         |

### Append gas

Benchmarks use keccak256 as the hash function. For privacy protocols, an algebraic hash like Poseidon2 will be required. The number of algebraic hashes required for each row is shown in the "Proof hashes" column, and can be used to estimate gas cost with a different hash fn.

| Skew-MMR branch           | Share       | Gas    | Proof hashes |
| ------------------------- | ----------- | ------ | ------------ |
| Push, `roots` slot reused | 2037 / 4096 | 26,895 | 0            |
| Merge                     | 2047 / 4096 | 27,942 | 1, 3-ary     |
| Push, new maximum depth   | 12 / 4096   | 26,405 | 0            |
| Mean                      |             | 27,417 | 0.5          |

| Hash chain branch | Share         | Mean   | Range           | Proof hashes |
| ----------------- | ------------- | ------ | --------------- | ------------ |
| 1 level           | 33907 / 35000 | 19,804 | 19,762 - 22,262 | 1            |
| 2 levels          | 1059 / 35000  | 29,807 | 27,611 - 31,943 | 2            |
| 3 levels          | 33 / 35000    | 30,543 | 30,372 - 32,560 | 3            |
| 4 levels          | 1 / 35000     | 33,133 |                 | 4            |
| Mean              |               | 20,117 |                 | 1.03         |


### Verify gas

Gas cost of verifying a calldata-provided state against a historical value stored in contract
storage.

| Structure            | Calldata words | Execution | Calldata | Total  |
| -------------------- | -------------- | --------- | -------- | ------ |
| Skew-MMR<sup>*</sup> | 26             | 10,266    | 13,312   | 23,578 |
| Hash chain           | 5              | 5,493     | 2,560    | 8,053  |

<sup>*</sup> Skew-MMR's verify cost varies with the length of the MMR. Each additional level adds 1 word to calldata (~512 gas) for an average gas cost of 6,144 and a maximum of 13,312.

### Projected with Poseidon2

Taking 14,000 gas for a 2-ary Poseidon2 and 25,000 for 3-ary [TaceoLabs/poseidon2-solidity](https://github.com/TaceoLabs/poseidon2-solidity#gas-and-bytecode-trade-offs):

| Structure  | Append mean | Verify mean | Append + verify |
| ---------- | ----------- | ----------- | --------------- |
| Skew-MMR   | 39,887      | 23,578      | 63,465          |
| Hash chain | 34,592      | 8,053       | 40,645          |
