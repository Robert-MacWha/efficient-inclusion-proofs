# Skew-MMR

Skew-MMR is an efficient append-only set commitment structure. It's a variant of a Merkle Mountain Range (MMR) that uses skewed binary carrying rules to reduce number of hashes per append operation to worst-case O(1).

## Benchmarks

### Operations

| Operation | Mean Hashes   | Max Hashes  |
| --------- | ------------- | ----------- |
| Append    | 0.5           | 1           |
| Verify    | log2(n) - 1.5 | log2(n) - 1 |

### Gas

Append gas varies significantly by branch. These tests were run using the `keccak256` hash function, which only uses ~880 gas per hash. To estimate the gas cost of using a more expensive hash function, add the cost difference to the `Merge` column's gas.

| Branch                           | Share       | Gas             |
| -------------------------------- | ----------- | --------------- |
| Push, `roots` slot reused        | 2037 / 4096 | 11,831          |
| Merge, one hash                  | 2047 / 4096 | 14,755          |
| Push, `roots` slot written first | 12 / 4096   | 28,476 - 45,576 |

The first two rows are each ~50% of appends. The third row happens when only a new maximum depth is reached, ~log2(n) times over the lifetime of the structure. This can be avoided by pre-warming the `roots` slots to arbitrary non-zero values in the constructor / an initializer.
