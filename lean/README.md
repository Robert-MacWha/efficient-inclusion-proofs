# skew-mmr Lean proofs

A Lean proof that the skew-MMR inclusion circuit decides what the native verifier decides.

The circuit in [`crates/skew-mmr/src/constraints`](../crates/skew-mmr/src/constraints) is modelled with [lean-ark-r1cs](https://github.com/Robert-MacWha/lean-ark-r1cs). See `SkewMmr.verify_sound` in [`SkewMmr/Proof.lean`](SkewMmr/Proof.lean) for the statement and its assumptions.

The circuit is stricter than `Proof::verify` in one place. It rejects a tree with rank above `MAX_DEPTH`, which a real `SkewMmr` never holds.

## Usage

Run this from the repo root. It checks the proofs, then checks that the Lean model and the Rust circuit build the same constraint matrices.

```bash
just lean
```
