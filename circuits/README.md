# @skew-mmr/circuits

Circom inclusion-proof gadget for the skew-MMR accumulator.

```circom
include "@skew-mmr/circuits/inclusion.circom";
component main {public [roots, element]} = SkewMmrInclusion(20);
```

The gadget outputs `valid`, 1 when `element` is in the accumulator and 0 otherwise, so the caller decides when membership is required, e.g. `valid === 1`.

`roots` must be authenticated by the caller, with entries above the frontier's depth set to 0.

Resolve with `circom -l node_modules`. Requires circom `^2.0.8` and circomlib.
