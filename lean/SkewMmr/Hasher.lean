/-
# `skew_mmr::constraints::hasher` (black-box interface)

`Hasher<F>` and `HasherGadget<F>` for one hash, with the only assumption made
about it: any assignment satisfying the gadget's constraints evaluates its
output to the native hash of the evaluated inputs.
-/
import ArkR1CS

namespace SkewMmr

open ArkR1CS

/-- A native three-input hash with a sound gadget. -/
structure HasherGadget (F : Type) [Field F] [DecidableEq F] where
  /-- `Hasher::hash`. -/
  hash_native : F → F → F → F
  /-- `HasherGadget::hash`. -/
  hash : FpVar F → FpVar F → FpVar F → CS F (FpVar F)
  sound : ∀ (element left right : FpVar F) (k : Counters) (a : Assignment F),
    ConstraintsHold a ((hash element left right).run k).2 →
      ((hash element left right).run k).1.eval a =
        hash_native (element.eval a) (left.eval a) (right.eval a)

end SkewMmr
