# Skew-MMR

Skew-MMR is an efficient append-only set commitment structure. It's a variant of a Merkle Mountain Range (MMR) that uses skewed binary carrying rules to reduce number of hashes per append operation to worst-case O(1).

## Benchmarks

### Operations

| Operation | Mean Hashes   | Max Hashes  |
| --------- | ------------- | ----------- |
| Append    | 0.5           | 1           |
| Verify    | log2(n) - 1.5 | log2(n) - 1 |

### Append gas

Gas cost of appending a new leaf to the MMR. The `Share` column indicates the percentage of the calls that follow each branch.

Append gas varies by branch. These tests were run using the `keccak256` hash function. To estimate the gas cost of using a more expensive hash function, add the cost difference to the `Merge` row's gas cost. Neither `Push` rows are affected by the hash function.

| Branch                    | Share       | Gas     |
| ------------------------- | ----------- | ------- |
| Push, `roots` slot reused | 2037 / 4096 | 24,632  |
| Merge, one hash           | 2047 / 4096 | 27,729  |
| Push, new maximum depth   | 12 / 4096   | 24,143  |
| Average                   | 100%        | ~26,000 |

### Verify gas

Gas cost of verifying a calldata-provided state & frontier against a historical value stored in contract storage.

| Depth | Execution Gas | Calldata Gas |
| ----- | ------------- | ------------ |
| 26    | ~11,075       | ~13,700      |
