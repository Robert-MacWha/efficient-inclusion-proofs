/-
# `skew_mmr::{state, proof}`: the native verifier

The specification the circuit is checked against: `Proof::verify`, over the
proof as the circuit sees it once allocated. `Option` entries are what
`AllocVar` makes of them, `unwrap_or_default`, so `children` and `path` hold
plain values and `roots` holds every root (entries at or above `depth` are
never read, since `State::rank` rejects those trees first).
-/

namespace SkewMmr

/-- `RANK_BITS`. -/
def RANK_BITS : Nat := 6

/-- `State`, with `packed_ranks` read as the little-endian integer of its bytes. -/
structure State where
  packed_ranks : Nat
  depth : Nat
  count : Nat

namespace State

/-- `State::try_from_parts`: rejects a depth above `MAX_DEPTH` and a word with
bits set at or above `RANK_BITS * MAX_DEPTH`. -/
def try_from_parts (MAX_DEPTH packed_ranks depth count : Nat) : Option State :=
  if MAX_DEPTH < depth then none
  else if 2 ^ (RANK_BITS * MAX_DEPTH) ≤ packed_ranks then none
  else some ⟨packed_ranks, depth, count⟩

/-- Bits `6 * tree .. 6 * tree + 6` of the word `packed_ranks`. -/
def rank_bits (packed_ranks tree : Nat) : Nat :=
  packed_ranks / 2 ^ (RANK_BITS * tree) % 2 ^ RANK_BITS

/-- `State::rank`: the rank bits of `tree`, or `none` when `tree` sits at or above
`depth`. -/
def rank (s : State) (tree : Nat) : Option Nat :=
  if s.depth ≤ tree then none else some (rank_bits s.packed_ranks tree)

end State

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
  state : State
  element : E
  tree : Nat
  children : E × E
  path_len : Nat
  path : List (Step E)

/-- `Proof::verify`. -/
def Proof.verify {E : Type} [DecidableEq E] (H : E → E → E → E) (p : Proof E) : Bool :=
  match p.roots[p.tree]?, p.state.rank p.tree with
  | some root, some rank =>
    if p.path.length < p.path_len then false
    else if rank < p.path_len then false
    else
      let start := if p.path_len = rank then p.element else H p.element p.children.1 p.children.2
      decide ((p.path.take p.path_len).foldl (fun current step => step.fold H current) start = root)
  | _, _ => false

end SkewMmr
