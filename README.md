# Skew-MMR

Skew-MMR is an efficient append-only set commitment structure. It's a variant of a Merkle Mountain Range (MMR) that uses skewed binary carrying rules to reduce number of hashes per append operation to worst-case O(1).

## Benchmarks

### Operations

| Operation | Mean Hashes   | Max Hashes  |
| --------- | ------------- | ----------- |
| Append    | 0.5           | 1           |
| Verify    | log2(n) - 1.5 | log2(n) - 1 |

### Append gas

Append gas varies by branch. These tests were run using the `keccak256` hash function. To estimate the gas cost of using a more expensive hash function, add the cost difference to the `Merge` row's gas.

| Branch                    | Share       | Gas    |
| ------------------------- | ----------- | ------ |
| Push, `roots` slot reused | 2037 / 4096 | 24,632 |
| Merge, one hash           | 2047 / 4096 | 27,729 |
| Push, new maximum depth   | 12 / 4096   | 24,143 |


### Verify gas

`verifyFrontier` against cold storage, versus the `2100 * depth` of cold SLOADs it replaces.

| Depth      | Gas     | Cold SLOADs |
| ---------- | ------- | ----------- |
| 5          | 4,733   | 10,500      |
| 11         | 6,545   | 23,100      |
| 26 (proj.) | ~11,075 | 54,600      |

302 gas per additional root.
