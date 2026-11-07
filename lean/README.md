# skew-mmr Lean proofs

A Lean 4 model of the skew-MMR inclusion proof circuit (`crates/skew-mmr/src/constraints`), written against [lean-ark-r1cs](https://github.com/Robert-MacWha/lean-ark-r1cs), with a proof that the circuit decides what the native verifier decides.

## The theorem

`SkewMmr.verify_sound` (`SkewMmr/Proof.lean`): for every assignment that satisfies the constraints of `StateVar::from_parts` followed by `ProofVar::verify`, the output bit is 1 exactly when

- `State::try_from_parts` accepts the frontier,
- the selected tree has rank at most `MAX_DEPTH`, and
- `Proof::verify` accepts the proof read off the assignment.

The rank condition is the one place the circuit is stricter than `Proof::verify`. It never rejects a real frontier: building a tree of rank `r` needs `r + 1` trees on the stack at once, so ranks stay below `MAX_DEPTH`.

Assumptions:

- the field is `ZMod p` with `2^(6 * MAX_DEPTH) < p` (the circuit's own `MODULUS_BIT_SIZE` assertion),
- the hash gadget is sound: its output evaluates to the native hash of its inputs (`HasherGadget.sound`),
- `packed_ranks` is allocated rather than a constant, `roots` and `path` hold `MAX_DEPTH` entries, and every `right` is a bit (as `Boolean::new_witness` makes it).

## Layout

| Lean | Rust |
| --- | --- |
| `SkewMmr/Native.lean` | `state.rs`, `proof.rs` (the specification) |
| `SkewMmr/Hasher.lean` | `constraints/hasher.rs` |
| `SkewMmr/Mask.lean` | `constraints/mask.rs` |
| `SkewMmr/State.lean` | `constraints/state.rs` |
| `SkewMmr/Proof.lean` | `constraints/mod.rs` |

`Traces.lean` renders the full circuit for a few proofs, and `crates/skew-mmr/tests/lean_traces.rs` checks that arkworks builds the same constraint matrices and assignment.

## Running

```bash
just lean
```

This builds the proofs, renders the traces and runs the comparison.
