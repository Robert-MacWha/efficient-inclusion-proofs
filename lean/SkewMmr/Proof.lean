/-
# `skew_mmr::constraints`: `ProofVar::verify`

The circuit, and its soundness theorem `verify_sound`: for any assignment
satisfying the constraints, the output bit is `1` exactly when the native
verifier `Proof::verify` accepts the proof read off the assignment.
-/
import SkewMmr.Mask
import SkewMmr.Native

namespace SkewMmr

open ArkR1CS

section Gadgets

variable {F : Type} [Field F] [DecidableEq F]

/-- `StepVar`. -/
structure StepVar (F : Type) where
  element : FpVar F
  sibling : FpVar F
  /-- Whether the path descends into the right child. -/
  right : Boolean F

/-- `ProofVar`. -/
structure ProofVar (F : Type) where
  tree : FpVar F
  children : FpVar F × FpVar F
  path_len : FpVar F
  path : List (StepVar F)

/-- `AllocVar::new_variable` for `StepVar`, in `AllocationMode::Witness`. -/
def StepVar.new_witness (s : Step F) : CS F (StepVar F) := do
  let element ← FpVar.new_witness s.element
  let sibling ← FpVar.new_witness s.sibling
  let right ← Boolean.new_witness s.right
  pure ⟨element, sibling, right⟩

/-- `AllocVar::new_variable` for `ProofVar`, in `AllocationMode::Witness`. -/
def ProofVar.new_witness (q : Proof F) : CS F (ProofVar F) := do
  let tree ← FpVar.new_witness (q.tree : F)
  let left ← FpVar.new_witness q.children.1
  let right ← FpVar.new_witness q.children.2
  let path_len ← FpVar.new_witness (q.path_len : F)
  let path ← q.path.mapM StepVar.new_witness
  pure ⟨tree, (left, right), path_len, path⟩

/-- `StepVar::fold`. -/
def StepVar.fold (H : HasherGadget F) (s : StepVar F) (current : FpVar F) : CS F (FpVar F) := do
  let left ← FpVar.conditionally_select s.right s.sibling current
  let right ← FpVar.conditionally_select s.right current s.sibling
  H.hash s.element left right

/-- The root loop of `ProofVar::verify`: the root `tree` selects, or `0`. -/
def select_root (tree : List (Boolean F)) (roots : List (FpVar F)) : CS F (FpVar F) :=
  (tree.zip roots).foldlM
    (fun root (x : Boolean F × FpVar F) => FpVar.conditionally_select x.1 x.2 root) FpVar.zero

/-- The walk up the path in `ProofVar::verify`: fold in each active step. -/
def walk (H : HasherGadget F) (path : List (StepVar F)) (active : List (Boolean F))
    (current : FpVar F) : CS F (FpVar F) :=
  (path.zip active).foldlM (fun current (x : StepVar F × Boolean F) => do
    let folded ← x.1.fold H current
    FpVar.conditionally_select x.2 folded current) current

/-- `ProofVar::verify`. The two loops are `select_root` and `walk`. -/
def ProofVar.verify (MAX_DEPTH : Nat) (H : HasherGadget F) (proof : ProofVar F)
    (element : FpVar F) (roots : List (FpVar F)) : CS F (Boolean F) := do
  let tree ← one_hot MAX_DEPTH proof.tree
  let root ← select_root tree roots
  let pm ← prefix_mask MAX_DEPTH proof.path_len
  let node ← H.hash element proof.children.1 proof.children.2
  let current ← walk H proof.path pm.1 node
  let eq ← EqGadget.is_eq (F := F) current root
  pm.2.and eq

end Gadgets

variable {p : Nat} [Fact p.Prime]

/-- The native step an assignment describes, reading `right` as `== 1`. -/
def StepVar.decode (a : Assignment (ZMod p)) (s : StepVar (ZMod p)) : Step (ZMod p) :=
  ⟨s.element.eval a, s.sibling.eval a, decide (s.right.eval a = 1)⟩

/-- The native proof an assignment describes: every field element read through
`ZMod.val` where Rust holds an integer. -/
def decode (a : Assignment (ZMod p)) (proof : ProofVar (ZMod p)) (element : FpVar (ZMod p))
    (roots : List (FpVar (ZMod p))) : Proof (ZMod p) where
  roots := roots.map (·.eval a)
  element := element.eval a
  tree := (proof.tree.eval a).val
  children := (proof.children.1.eval a, proof.children.2.eval a)
  path_len := (proof.path_len.eval a).val
  path := proof.path.map (·.decode a)

/-! ### Lemmas -/

/-- Soundness of `StepVar::fold` on a bit `right`: the native `Step::fold`. -/
theorem StepVar.fold_sound (H : HasherGadget (ZMod p)) (s : StepVar (ZMod p))
    (c : FpVar (ZMod p)) (k : Counters) (a : Assignment (ZMod p))
    (hright : s.right.eval a = 0 ∨ s.right.eval a = 1)
    (h : ConstraintsHold a ((s.fold H c).run k).2) :
    ((s.fold H c).run k).1.eval a = (s.decode a).fold H.hash_native (c.eval a) := by
  simp only [StepVar.fold, CS.run_bind, constraintsHold_append] at h ⊢
  rw [H.sound _ _ _ _ a h.2.2, FpVar.conditionally_select_sound _ _ _ _ a h.1,
    FpVar.conditionally_select_sound _ _ _ _ a h.2.1]
  rcases hright with hr | hr <;> simp [hr, StepVar.decode, Step.fold]

theorem select_root_sound (D T : Nat) (tree : List (Boolean (ZMod p)))
    (roots : List (FpVar (ZMod p))) (k : Counters) (a : Assignment (ZMod p))
    (htree : tree.map (·.eval a) = (List.range D).map (fun i => if T = i then 1 else 0))
    (hroots : roots.length = D) (h : ConstraintsHold a ((select_root tree roots).run k).2) :
    ((select_root tree roots).run k).1.eval a = (roots.map (·.eval a)).getD T 0 := by
  have hlen : (tree.zip roots).length = D := by simp [length_of_map_eq_range htree, hroots]
  -- After `i` entries, `root` is root `T` if `T < i`.
  have loop := CS.foldlM_inv _ a (tree.zip roots)
    (fun i (r : FpVar (ZMod p)) => r.eval a =
      if T < i then (roots.map (·.eval a)).getD T 0 else 0)
    _ k (by simp)
    (fun i hi r k' hr h' => by
      have hiD : i < D := hlen ▸ hi
      have ht : i < tree.length := by rw [length_of_map_eq_range htree]; exact hiD
      have hhit : IsBit a tree[i] (T = i) := getElem_of_map_eq_range htree i ht
      simp only [List.getElem_zip] at h' ⊢
      rw [FpVar.select_bit hhit h', hr]
      by_cases hTi : T = i
      · subst hTi
        simp [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (hroots ▸ hiD)]
      · simp only [hTi, ↓reduceIte]
        exact if_congr (by omega) rfl rfl)
    h
  rw [hlen] at loop
  unfold select_root
  rw [loop]
  split_ifs with hT
  · rfl
  · rw [List.getD_eq_getElem?_getD, List.getElem?_eq_none (by simp [hroots]; omega)]; rfl

theorem walk_sound (D L : Nat) (H : HasherGadget (ZMod p)) (path : List (StepVar (ZMod p)))
    (active : List (Boolean (ZMod p))) (current : FpVar (ZMod p)) (k : Counters)
    (a : Assignment (ZMod p)) (hpath : path.length = D)
    (hright : ∀ s ∈ path, s.right.eval a = 0 ∨ s.right.eval a = 1)
    (hactive : active.map (·.eval a) = (List.range D).map (fun i => if i < L then 1 else 0))
    (h : ConstraintsHold a ((walk H path active current).run k).2) :
    ((walk H path active current).run k).1.eval a =
      ((path.map (·.decode a)).take L).foldl (fun c step => step.fold H.hash_native c)
        (current.eval a) := by
  have hlen : (path.zip active).length = D := by simp [hpath, length_of_map_eq_range hactive]
  -- After `i` steps, `current` has folded in the first `min i path_len` steps.
  have loop := CS.foldlM_inv _ a (path.zip active)
    (fun i (c : FpVar (ZMod p)) => c.eval a =
      ((path.map (·.decode a)).take (min i L)).foldl (fun c step => step.fold H.hash_native c)
        (current.eval a))
    _ k (by simp)
    (fun i hi c k' hc h' => by
      have hiD : i < D := hlen ▸ hi
      have ha : i < active.length := by rw [length_of_map_eq_range hactive]; exact hiD
      have hp : i < path.length := hpath ▸ hiD
      have hact : IsBit a active[i] (i < L) := getElem_of_map_eq_range hactive i ha
      simp only [List.getElem_zip, CS.run_bind, constraintsHold_append] at h' ⊢
      rw [FpVar.select_bit hact h'.2, StepVar.fold_sound H _ _ _ a
        (hright _ (List.getElem_mem (hpath ▸ hiD))) h'.1, hc]
      by_cases hiL : i < L
      · simp only [hiL, ↓reduceIte]
        rw [show min (i + 1) L = i + 1 by omega, show min i L = i by omega, List.take_add_one,
          List.foldl_append, List.getElem?_map, List.getElem?_eq_getElem hp]
        rfl
      · simp only [hiL, ↓reduceIte]
        rw [show min (i + 1) L = min i L by omega])
    h
  rw [hlen] at loop
  unfold walk
  rw [loop]
  by_cases hLD : L ≤ D
  · rw [show min D L = L by omega]
  · rw [show min D L = D by omega, List.take_of_length_le (by simp [hpath]),
      List.take_of_length_le (by simp [hpath]; omega)]

/-! ### Soundness -/

/-- Soundness of the skew-MMR inclusion proof circuit: for any assignment satisfying
the constraints, the output bit is `1` exactly when `Proof::verify` accepts the proof
the assignment describes (`decode`).

Assumptions: the field is `ZMod p` with `MAX_DEPTH < p`, `roots` and `path` have
`MAX_DEPTH` entries, and each `right` is a bit (as `Boolean::new_witness` makes it). -/
theorem verify_sound (D : Nat) (hD : D < p) (H : HasherGadget (ZMod p))
    (proof : ProofVar (ZMod p)) (hpath : proof.path.length = D) (element : FpVar (ZMod p))
    (roots : List (FpVar (ZMod p))) (hroots : roots.length = D) (k : Counters)
    (a : Assignment (ZMod p))
    (hright : ∀ s ∈ proof.path, s.right.eval a = 0 ∨ s.right.eval a = 1)
    (h : ConstraintsHold a ((proof.verify D H element roots).run k).2) :
    ((proof.verify D H element roots).run k).1.eval a =
      if (decode a proof element roots).verify H.hash_native then 1 else 0 := by
  simp only [ProofVar.verify, CS.run_bind, constraintsHold_append] at h ⊢
  obtain ⟨htree, hroot, hpm, hnode, hwalk, heq, hout⟩ := h
  -- `let tree = one_hot(&self.tree)`, and the root it selects.
  have htreeE := one_hot_sound D hD.le proof.tree _ a htree
  have hrootE := select_root_sound D _ _ roots _ a htreeE hroots hroot
  -- `let (active, bounded) = prefix_mask(&self.path_len)`.
  obtain ⟨hactE, hbndE⟩ := prefix_mask_sound D hD proof.path_len _ a hpm
  -- The node, then the walk up the path.
  have hcurE := walk_sound D _ H proof.path _ _ _ a hpath hright hactE hwalk
  rw [H.sound _ _ _ _ a hnode] at hcurE
  -- `bounded & current.is_eq(&root)`, against `Proof::verify`.
  rw [Boolean.and_bit hbndE (FpVar.is_eq_bit _ _ heq) hout, hcurE, hrootE]
  simp [decode, Proof.verify, hpath]

end SkewMmr
