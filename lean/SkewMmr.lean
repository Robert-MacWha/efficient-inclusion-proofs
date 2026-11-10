/-
# SkewMmr

A Lean model of the skew-MMR inclusion proof circuit
(`crates/skew-mmr/src/constraints`), written against the `ArkR1CS` model of
arkworks, with a proof that it decides exactly what the native verifier
(`crates/skew-mmr/src/proof.rs`) decides.

* `SkewMmr.Native` ↔ `skew_mmr::{state, proof}` (the native verifier)
* `SkewMmr.Hasher` ↔ `skew_mmr::constraints::hasher` (black-box interface)
* `SkewMmr.Mask`   ↔ `skew_mmr::constraints::mask`
* `SkewMmr.State`  ↔ `skew_mmr::constraints::state`
* `SkewMmr.Proof`  ↔ `skew_mmr::constraints` (`ProofVar::verify`), and the
  main theorem `ProofVar.verify_sound`
-/
import SkewMmr.Native
import SkewMmr.Hasher
import SkewMmr.Mask
import SkewMmr.State
import SkewMmr.Proof
