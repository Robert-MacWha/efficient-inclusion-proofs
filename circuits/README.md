# @skew-mmr/circuits

Circom inclusion-proof gadget for the skew-MMR accumulator.

```circom
include "@skew-mmr/circuits/inclusion.circom";
component main {public [roots, packedRanks, depth, element]} = SkewMmrInclusion(20);
```

The gadget outputs `valid`, 1 when `element` is in the accumulator and 0 otherwise, so the caller decides when membership is required, e.g. `valid === 1`.

It also outputs `index`, the proven element's position in insertion order, counted from 0. The index is fixed when the element is appended and is meaningful only when `valid` is 1, e.g.

Resolve with `circom -l node_modules`. Requires circom `^2.0.8` and circomlib.
