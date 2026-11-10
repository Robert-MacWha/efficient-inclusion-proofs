/-
# `skew_mmr::proof`: the native verifier

The specification the circuit is checked against: `Proof::verify`, over the
proof as the circuit sees it once allocated. `Option` entries are what
`AllocVar` makes of them, `unwrap_or_default`, so `roots`, `children` and
`path` hold plain values, with `0` for a missing one.
-/
import Mathlib.Algebra.Group.Defs

namespace SkewMmr

/-- `Step`. -/
structure Step (E : Type) where
  element : E
  sibling : E
  /-- Whether the path descends into the right child. -/
  right : Bool

/-- `Step::fold`. -/
def Step.fold {E : Type} (H : E → E → E → E) (s : Step E) (current : E) : E :=
  if s.right then H s.element s.sibling current else H s.element current s.sibling

/-- `Proof`, as allocated (see the module doc). -/
structure Proof (E : Type) where
  roots : List E
  element : E
  tree : Nat
  children : E × E
  path_len : Nat
  path : List (Step E)

/-- `Proof::verify`: hash the proven node, fold in the first `path_len` steps, and compare
with root `tree` (`0` when there is none). -/
def Proof.verify {E : Type} [DecidableEq E] [Zero E] (H : E → E → E → E) (p : Proof E) : Bool :=
  p.path_len ≤ p.path.length &&
    decide ((p.path.take p.path_len).foldl (fun current step => step.fold H current)
      (H p.element p.children.1 p.children.2) = p.roots.getD p.tree 0)

end SkewMmr
