# @skew-mmr/circuits

Circom inclusion-proof gadget for the skew-MMR accumulator.

```circom
include "@skew-mmr/circuits/inclusion.circom";
component main {public [roots, state, element]} = SkewMmrInclusion(20);
```

Resolve with `circom -l node_modules`. Requires circom `^2.0.8` and circomlib.
