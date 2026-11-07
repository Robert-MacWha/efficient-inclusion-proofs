/-
# `skew_mmr::constraints`: `ProofVar::verify`

The circuit, and its soundness theorem `verify_sound`: for any assignment
satisfying the constraints, the output bit is `1` exactly when the native
verifier `Proof::verify` accepts the proof read off the assignment, the
frontier is one `State::try_from_parts` accepts, and the selected tree has
rank at most `MAX_DEPTH`.

The last condition is the one place the circuit is stricter than the native
verifier. It never rejects a real frontier: building a tree of rank `r`
takes `r + 1` trees on the stack at once, so a `SkewMmr` with at most
`MAX_DEPTH` trees only holds trees of rank below `MAX_DEPTH`.
-/
import SkewMmr.State

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

/-- `ProofVar::verify`. -/
def ProofVar.verify (MAX_DEPTH : Nat) (H : HasherGadget F) (proof : ProofVar F)
    (element : FpVar F) (state : StateVar F) (roots : List (FpVar F)) : CS F (Boolean F) := do
  let tree ← one_hot MAX_DEPTH proof.tree
  let r ← state.rank tree
  let root ← (tree.zip roots).foldlM
    (fun root (x : Boolean F × FpVar F) => FpVar.conditionally_select x.1 x.2 root) FpVar.zero
  let pm ← prefix_mask MAX_DEPTH proof.path_len
  let rm ← prefix_mask MAX_DEPTH r.1
  let valid ← r.2.and pm.2
  let valid ← valid.and rm.2
  let valid ← (pm.1.zip rm.1).foldlM (fun valid (x : Boolean F × Boolean F) => do
      let w ← x.2.or x.1.not
      valid.and w) valid
  let is_leaf ← EqGadget.is_eq (F := F) proof.path_len r.1
  let node ← H.hash element proof.children.1 proof.children.2
  let current ← FpVar.conditionally_select is_leaf element node
  let current ← (proof.path.zip pm.1).foldlM (fun current (x : StepVar F × Boolean F) => do
      let folded ← x.1.fold H current
      FpVar.conditionally_select x.2 folded current) current
  let eq ← EqGadget.is_eq (F := F) current root
  valid.and eq

/-- `ProofVar::verify` on a `StateVar` built from its three words. -/
def verify_circuit [IntoBigInt F] (MAX_DEPTH : Nat) (H : HasherGadget F)
    (packed_ranks depth count : FpVar F) (proof : ProofVar F) (element : FpVar F)
    (roots : List (FpVar F)) : CS F (Boolean F) := do
  let state ← StateVar.from_parts MAX_DEPTH packed_ranks depth count
  proof.verify MAX_DEPTH H element state roots

end Gadgets

variable {p : Nat} [Fact p.Prime]

/-- The native proof an assignment describes: every field element read
through `ZMod.val` where Rust holds an integer, and `right` as `== 1`. -/
def decode (a : Assignment (ZMod p)) (packed_ranks depth count : FpVar (ZMod p))
    (proof : ProofVar (ZMod p)) (element : FpVar (ZMod p)) (roots : List (FpVar (ZMod p))) :
    Proof (ZMod p) where
  roots := roots.map (·.eval a)
  state := ⟨(packed_ranks.eval a).val, (depth.eval a).val, (count.eval a).val⟩
  element := element.eval a
  tree := (proof.tree.eval a).val
  children := (proof.children.1.eval a, proof.children.2.eval a)
  path_len := (proof.path_len.eval a).val
  path := proof.path.map fun s => ⟨s.element.eval a, s.sibling.eval a, decide (s.right.eval a = 1)⟩

/-! ### Loops on values -/

theorem select_foldl (T : Nat) (X : Nat → ZMod p) (n : Nat) :
    (List.range n).foldl (fun r i => r + (if T = i then 1 else 0) * (X i - r)) 0 =
      if T < n then X T else 0 := by
  induction n with
  | zero => simp
  | succ n ih =>
    rw [List.range_succ, List.foldl_append, ih]
    by_cases h1 : T = n
    · subst h1; simp
    · have : T < n + 1 ↔ T < n := by omega
      simp [h1, this]

theorem valid_foldl (L R n : Nat) (v : ZMod p) :
    (List.range n).foldl
        (fun v i => v * (1 - (1 - if i < R then 1 else 0) * (1 - (1 - if i < L then 1 else 0)))) v =
      v * if ∀ i < n, i < L → i < R then 1 else 0 := by
  induction n with
  | zero => simp
  | succ n ih =>
    rw [List.range_succ, List.foldl_append, ih]
    have : (∀ i < n + 1, i < L → i < R) ↔ (∀ i < n, i < L → i < R) ∧ (n < L → n < R) :=
      ⟨fun h => ⟨fun i hi => h i (by omega), h n (by omega)⟩,
        fun h i hi => if hin : i < n then h.1 i hin else by
          obtain rfl : i = n := by omega
          exact h.2⟩
    simp only [List.foldl_cons, List.foldl_nil, this]
    by_cases h1 : ∀ i < n, i < L → i < R <;> by_cases h2 : n < L <;> by_cases h3 : n < R <;>
      simp [h1, h2, h3]

theorem current_foldl {α : Type} (f : α → ZMod p → ZMod p) (L : Nat) :
    ∀ (ps : List α) (s : Nat) (c : ZMod p),
      (ps.zip ((List.range' s ps.length).map fun i => if i < L then 1 else 0)).foldl
          (fun c x => c + x.2 * (f x.1 c - c)) c =
        (ps.take (L - s)).foldl (fun c q => f q c) c
  | [], _, _ => by simp
  | q :: ps, s, c => by
    simp only [List.length_cons, List.range'_succ, List.map_cons, List.zip_cons_cons,
      List.foldl_cons]
    rw [current_foldl f L ps (s + 1)]
    by_cases hs : s < L
    · simp only [hs, ↓reduceIte]
      rw [show L - s = (L - (s + 1)) + 1 by omega, List.take_succ_cons, List.foldl_cons]
      simp
    · simp only [hs, ↓reduceIte]
      rw [show L - s = 0 by omega, show L - (s + 1) = 0 by omega]
      simp

theorem eq_map_range_getD {α : Type} (l : List α) (d : α) :
    l = (List.range l.length).map fun i => l.getD i d := by
  apply List.ext_getElem
  · simp
  · intro i h₁ h₂
    simp [List.getElem?_eq_getElem h₁]

omit [Fact p.Prime] in
theorem D_lt_p {D : Nat} (hD : 2 ^ (RANK_BITS * D) < p) : D < p :=
  lt_of_le_of_lt (le_trans (Nat.lt_two_pow_self).le
    (Nat.pow_le_pow_right (by norm_num) (by simp [RANK_BITS]; omega))) hD

theorem StepVar.fold_sound (H : HasherGadget (ZMod p)) (s : StepVar (ZMod p))
    (c : FpVar (ZMod p)) (k : Counters) (a : Assignment (ZMod p))
    (h : ConstraintsHold a ((s.fold H c).run k).2) :
    ((s.fold H c).run k).1.eval a =
      H.hash_native (s.element.eval a)
        (c.eval a + s.right.eval a * (s.sibling.eval a - c.eval a))
        (s.sibling.eval a + s.right.eval a * (c.eval a - s.sibling.eval a)) := by
  simp only [StepVar.fold, CS.run_bind, constraintsHold_append] at h ⊢
  rw [H.sound _ _ _ _ a h.2.2, FpVar.conditionally_select_sound _ _ _ _ a h.1,
    FpVar.conditionally_select_sound _ _ _ _ a h.2.1]

/-- A fold over bits is the native fold. -/
theorem fold_decode (H : HasherGadget (ZMod p)) (a : Assignment (ZMod p)) :
    ∀ (ps : List (StepVar (ZMod p))), (∀ s ∈ ps, s.right.eval a = 0 ∨ s.right.eval a = 1) →
      ∀ c, ps.foldl (fun c (s : StepVar (ZMod p)) =>
          H.hash_native (s.element.eval a) (c + s.right.eval a * (s.sibling.eval a - c))
            (s.sibling.eval a + s.right.eval a * (c - s.sibling.eval a))) c =
        (ps.map fun s => (⟨s.element.eval a, s.sibling.eval a, decide (s.right.eval a = 1)⟩ :
          Step (ZMod p))).foldl (fun c step => step.fold H.hash_native c) c
  | [], _, _ => rfl
  | s :: ps, hps, c => by
    simp only [List.foldl_cons, List.map_cons]
    rw [fold_decode H a ps (fun s hs => hps s (List.mem_cons_of_mem _ hs))]
    congr 1
    rcases hps s List.mem_cons_self with h | h <;> simp [h, Step.fold]

/-- The output bit, once every gadget is evaluated, against the specification. -/
theorem accept_iff (D : Nat) (hD : 2 ^ (RANK_BITS * D) < p) (Hn : ZMod p → ZMod p → ZMod p → ZMod p)
    (Tf depf Lf Nf cnt elem c0 c1 : ZMod p) (rootsE : List (ZMod p)) (hroots : rootsE.length = D)
    (ps : List (Step (ZMod p))) (hps : ps.length = D) (hN : Nf.val < 2 ^ (RANK_BITS * D)) :
    (((((if Tf.val < D ∧ Tf.val < depf.val then (1 : ZMod p) else 0) *
              (if depf.val ≤ D then 1 else 0)) *
            (if Lf.val ≤ D then 1 else 0)) *
          (if (if Tf.val < D then ((Nf.val / 2 ^ (RANK_BITS * Tf.val) % 2 ^ RANK_BITS : Nat) : ZMod p) else 0).val ≤ D then 1 else 0)) *
        (if ∀ i < D, i < Lf.val → i < (if Tf.val < D then ((Nf.val / 2 ^ (RANK_BITS * Tf.val) % 2 ^ RANK_BITS : Nat) : ZMod p) else 0).val then 1 else 0)) *
      (if (ps.take Lf.val).foldl (fun c step => step.fold Hn c)
            (Hn elem c0 c1 + (if Lf = (if Tf.val < D then ((Nf.val / 2 ^ (RANK_BITS * Tf.val) % 2 ^ RANK_BITS : Nat) : ZMod p) else 0) then 1 else 0) * (elem - Hn elem c0 c1)) =
          (if Tf.val < D then rootsE.getD Tf.val 0 else 0) then 1 else 0) =
    if (State.try_from_parts D Nf.val depf.val cnt.val).isSome ∧
        (∀ r ∈ State.rank ⟨Nf.val, depf.val, cnt.val⟩ Tf.val, r ≤ D) ∧
        Proof.verify Hn ⟨rootsE, ⟨Nf.val, depf.val, cnt.val⟩, elem, Tf.val, (c0, c1), Lf.val, ps⟩
    then 1 else 0 := by
  have hfrom : (State.try_from_parts D Nf.val depf.val cnt.val).isSome = true ↔ depf.val ≤ D := by
    unfold State.try_from_parts
    split_ifs <;> simp <;> omega
  simp only [hfrom]
  generalize hRf' : (if Tf.val < D then ((Nf.val / 2 ^ (RANK_BITS * Tf.val) % 2 ^ RANK_BITS : Nat) : ZMod p) else 0) = Rf
  simp only [Proof.verify, State.rank, hps]
  by_cases hlive : Tf.val < D ∧ Tf.val < depf.val
  · obtain ⟨hTD, hTdep⟩ := hlive
    set R := Nf.val / 2 ^ (RANK_BITS * Tf.val) % 2 ^ RANK_BITS with hR
    have hRlt : R < p := by
      refine lt_of_lt_of_le (Nat.mod_lt _ (by positivity)) (le_trans ?_ hD.le)
      exact Nat.pow_le_pow_right (by norm_num) (by simp only [RANK_BITS]; omega)
    have hRf : Rf = (R : ZMod p) := by rw [← hRf']; simp only [hTD, ↓reduceIte, hR]
    have hroot : rootsE[Tf.val]? = some (rootsE.getD Tf.val 0) := by
      rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (by omega)]; rfl
    have hstart : Hn elem c0 c1 + (if Lf = Rf then 1 else 0) * (elem - Hn elem c0 c1) =
        if Lf.val = R then elem else Hn elem c0 c1 := by
      rw [hRf]; simp only [eq_natCast_iff _ hRlt]; split_ifs <;> ring
    rw [hstart, hRf, ZMod.val_cast_of_lt hRlt, hroot]
    simp only [hTD, hTdep, and_self, ↓reduceIte, not_le.mpr hTdep, one_mul, Option.mem_def,
      Option.some.injEq, forall_eq']
    have hall : Lf.val ≤ D → ((∀ i < D, i < Lf.val → i < R) ↔ Lf.val ≤ R) := fun hLD =>
      ⟨fun h => by
        by_contra hc
        exact lt_irrefl R (h R (by omega) (by omega)), fun h i _ hi => by omega⟩
    by_cases h1 : depf.val ≤ D <;> by_cases h2 : Lf.val ≤ D <;> by_cases h3 : R ≤ D <;>
      by_cases h4 : Lf.val ≤ R <;> simp [h1, h2, h3, h4, hall]
  · have hnone : rootsE[Tf.val]? = none ∨ depf.val ≤ Tf.val := by
      by_cases hTD : Tf.val < D
      · exact .inr (by omega)
      · exact .inl (List.getElem?_eq_none (by omega))
    rcases hnone with h | h <;> simp [hlive, h]

/-! ### Soundness -/

/-- Soundness of the skew-MMR inclusion proof circuit.

For any assignment satisfying the constraints, the output bit is `1` exactly
when, for the proof the assignment describes (`decode`):

* `State::try_from_parts` accepts the frontier (of its two checks, the
  circuit enforces `packed_ranks < 2^(RANK_BITS * MAX_DEPTH)` and reports
  `depth ≤ MAX_DEPTH`),
* the selected tree, if live, has rank at most `MAX_DEPTH`, and
* the native verifier `Proof::verify` accepts.

Assumptions: the field is `ZMod p` with `2^(RANK_BITS * MAX_DEPTH) < p` (the
`MODULUS_BIT_SIZE > RANK_BITS * MAX_DEPTH` assertion), `packed_ranks` is
allocated (not a constant), `roots` and `path` have `MAX_DEPTH` entries, and
each `right` is a bit (as `Boolean::new_witness` makes it). -/
theorem verify_sound (D : Nat) (hD : 2 ^ (RANK_BITS * D) < p) (H : HasherGadget (ZMod p))
    (packed_ranks depth count : FpVar (ZMod p)) (hpacked : ¬ packed_ranks.isConstant)
    (proof : ProofVar (ZMod p)) (hpath : proof.path.length = D) (element : FpVar (ZMod p))
    (roots : List (FpVar (ZMod p))) (hroots : roots.length = D) (k : Counters)
    (a : Assignment (ZMod p))
    (hright : ∀ s ∈ proof.path, s.right.eval a = 0 ∨ s.right.eval a = 1)
    (h : ConstraintsHold a
      ((verify_circuit D H packed_ranks depth count proof element roots).run k).2) :
    ((verify_circuit D H packed_ranks depth count proof element roots).run k).1.eval a =
      let q := decode a packed_ranks depth count proof element roots
      if (State.try_from_parts D q.state.packed_ranks q.state.depth q.state.count).isSome ∧
        (∀ r ∈ q.state.rank q.tree, r ≤ D) ∧ q.verify H.hash_native
      then 1 else 0 := by
  have hDp := D_lt_p hD
  simp only [verify_circuit, ProofVar.verify, CS.run_bind,
    constraintsHold_append] at h ⊢
  obtain ⟨hfp, htree, hrank, hroot, hpm, hrm, hv1, hv2, hvalid, hleaf, hnode, hcur0, hcur, heq,
    hout⟩ := h
  -- `StateVar::from_parts`, `one_hot`, `StateVar::rank`.
  obtain ⟨hNlt, hranksE, hpopE, hbndE⟩ :=
    from_parts_sound D hD packed_ranks depth count hpacked k a hfp
  have htreeE := one_hot_sound D hDp.le proof.tree _ a htree
  obtain ⟨hrankE, hliveE⟩ := rank_sound D _ _ _ _ _ _ a htreeE hranksE hpopE hrank
  -- The root: a one-hot selection over `roots`.
  let gR : ZMod p → ZMod p × ZMod p → ZMod p := fun r x => r + x.1 * (x.2 - r)
  let φR : Boolean (ZMod p) × FpVar (ZMod p) → ZMod p × ZMod p :=
    Prod.map (fun b : Boolean (ZMod p) => b.eval a) (fun x : FpVar (ZMod p) => x.eval a)
  have hrootE := CS.foldlM_sound _ (fun _ => True) (fun r : FpVar (ZMod p) => r.eval a)
    (fun r x => gR r (φR x))
    a (fun r x k' _ h' => ⟨trivial, FpVar.conditionally_select_sound _ _ _ _ a h'⟩) _ _ _ trivial
    hroot
  have hrootV := hrootE.2
  rw [← List.foldl_map (f := φR) (g := gR)] at hrootV
  simp only [φR] at hrootV
  rw [← List.zip_map, htreeE, eq_map_range_getD (roots.map (·.eval a)) 0,
    List.length_map, hroots, List.zip_map', List.foldl_map, FpVar.eval_zero] at hrootV
  simp only [gR] at hrootV
  rw [select_foldl] at hrootV
  -- The masks and the validity bit.
  obtain ⟨hactE, hpbE⟩ := prefix_mask_sound D hDp proof.path_len _ a hpm
  obtain ⟨hwithinE, hrbE⟩ := prefix_mask_sound D hDp _ _ a hrm
  have hv1E := Boolean.and_sound _ _ _ a hv1
  have hv2E := Boolean.and_sound _ _ _ a hv2
  let gV : ZMod p → ZMod p × ZMod p → ZMod p := fun v x => v * (1 - (1 - x.2) * (1 - (1 - x.1)))
  let φV : Boolean (ZMod p) × Boolean (ZMod p) → ZMod p × ZMod p :=
    Prod.map (fun b : Boolean (ZMod p) => b.eval a) (fun b : Boolean (ZMod p) => b.eval a)
  have hvalidE := CS.foldlM_sound _ (fun _ => True) (fun v : Boolean (ZMod p) => v.eval a)
    (fun v x => gV v (φV x))
    a (fun v x k' _ h' => by
      simp only [CS.run_bind, constraintsHold_append] at h' ⊢
      refine ⟨trivial, ?_⟩
      rw [Boolean.and_sound _ _ _ a h'.2, Boolean.or_sound _ _ _ a h'.1, Boolean.eval_not]
      rfl) _ _ _ trivial hvalid
  have hvalidV := hvalidE.2
  rw [← List.foldl_map (f := φV) (g := gV)] at hvalidV
  simp only [φV] at hvalidV
  rw [← List.zip_map, hactE, hwithinE, List.zip_map', List.foldl_map] at hvalidV
  simp only [gV] at hvalidV
  rw [valid_foldl] at hvalidV
  -- The node, and the walk up the path.
  have hleafE := FpVar.is_eq_sound _ _ _ a hleaf
  have hnodeE := H.sound _ _ _ _ a hnode
  have hcur0E := FpVar.conditionally_select_sound _ _ _ _ a hcur0
  let foldE : StepVar (ZMod p) → ZMod p → ZMod p := fun s c =>
    H.hash_native (s.element.eval a) (c + s.right.eval a * (s.sibling.eval a - c))
      (s.sibling.eval a + s.right.eval a * (c - s.sibling.eval a))
  let gC : ZMod p → StepVar (ZMod p) × ZMod p → ZMod p := fun c x => c + x.2 * (foldE x.1 c - c)
  let φC : StepVar (ZMod p) × Boolean (ZMod p) → StepVar (ZMod p) × ZMod p :=
    Prod.map id (fun b : Boolean (ZMod p) => b.eval a)
  have hcurE := CS.foldlM_sound _ (fun _ => True) (fun c : FpVar (ZMod p) => c.eval a)
    (fun c x => gC c (φC x))
    a (fun c x k' _ h' => by
      simp only [CS.run_bind, constraintsHold_append] at h' ⊢
      refine ⟨trivial, ?_⟩
      rw [FpVar.conditionally_select_sound _ _ _ _ a h'.2, StepVar.fold_sound H _ _ _ a h'.1]
      rfl) _ _ _ trivial hcur
  have hcurV := hcurE.2
  have hwalk := current_foldl foldE (proof.path_len.eval a).val proof.path 0
  rw [hpath, ← List.range_eq_range', Nat.sub_zero] at hwalk
  rw [← List.foldl_map (f := φC) (g := gC)] at hcurV
  simp only [φC] at hcurV
  rw [← List.zip_map_right, hactE] at hcurV
  simp only [gC] at hcurV
  rw [hwalk, fold_decode H a _ (fun s hs => hright s (List.mem_of_mem_take hs))] at hcurV
  have heqE := FpVar.is_eq_sound _ _ _ a heq
  -- The output.
  rw [Boolean.and_sound _ _ _ a hout, heqE, hcurV, hrootV, hcur0E, hnodeE, hleafE, hvalidV,
    hv2E, hv1E, hliveE, hbndE, hpbE, hrbE, hrankE]
  rw [List.map_take]
  refine accept_iff D hD H.hash_native _ _ _ _ _ _ _ _ _ ?_ _ ?_ hNlt
  · simpa using hroots
  · simpa using hpath

end SkewMmr
