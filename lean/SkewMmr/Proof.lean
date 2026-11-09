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

/-- The root loop of `ProofVar::verify`: the root `tree` selects, or `0`. -/
def select_root (tree : List (Boolean F)) (roots : List (FpVar F)) : CS F (FpVar F) :=
  (tree.zip roots).foldlM
    (fun root (x : Boolean F × FpVar F) => FpVar.conditionally_select x.1 x.2 root) FpVar.zero

/-- The `valid &= within | !active` loop of `ProofVar::verify`. -/
def check_steps (active within : List (Boolean F)) (valid : Boolean F) : CS F (Boolean F) :=
  (active.zip within).foldlM (fun valid (x : Boolean F × Boolean F) => do
    let w ← x.2.or x.1.not
    valid.and w) valid

/-- The walk up the path in `ProofVar::verify`: fold in each active step. -/
def walk (H : HasherGadget F) (path : List (StepVar F)) (active : List (Boolean F))
    (current : FpVar F) : CS F (FpVar F) :=
  (path.zip active).foldlM (fun current (x : StepVar F × Boolean F) => do
    let folded ← x.1.fold H current
    FpVar.conditionally_select x.2 folded current) current

/-- `ProofVar::verify`. The three loops are `select_root`, `check_steps` and `walk`. -/
def ProofVar.verify (MAX_DEPTH : Nat) (H : HasherGadget F) (proof : ProofVar F)
    (element : FpVar F) (state : StateVar F) (roots : List (FpVar F)) : CS F (Boolean F) := do
  let tree ← one_hot MAX_DEPTH proof.tree
  let r ← state.rank tree
  let root ← select_root tree roots
  let pm ← prefix_mask MAX_DEPTH proof.path_len
  let rm ← prefix_mask MAX_DEPTH r.1
  let valid ← r.2.and pm.2
  let valid ← valid.and rm.2
  let valid ← check_steps pm.1 rm.1 valid
  let is_leaf ← EqGadget.is_eq (F := F) proof.path_len r.1
  let node ← H.hash element proof.children.1 proof.children.2
  let current ← FpVar.conditionally_select is_leaf element node
  let current ← walk H proof.path pm.1 current
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

/-- The native step an assignment describes, reading `right` as `== 1`. -/
def StepVar.decode (a : Assignment (ZMod p)) (s : StepVar (ZMod p)) : Step (ZMod p) :=
  ⟨s.element.eval a, s.sibling.eval a, decide (s.right.eval a = 1)⟩

/-- The native proof an assignment describes: every field element read
through `ZMod.val` where Rust holds an integer. -/
def decode (a : Assignment (ZMod p)) (packed_ranks depth count : FpVar (ZMod p))
    (proof : ProofVar (ZMod p)) (element : FpVar (ZMod p)) (roots : List (FpVar (ZMod p))) :
    Proof (ZMod p) where
  roots := roots.map (·.eval a)
  state := ⟨(packed_ranks.eval a).val, (depth.eval a).val, (count.eval a).val⟩
  element := element.eval a
  tree := (proof.tree.eval a).val
  children := (proof.children.1.eval a, proof.children.2.eval a)
  path_len := (proof.path_len.eval a).val
  path := proof.path.map (·.decode a)

/-! ### Steps -/

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

theorem forall_lt_succ {P : Nat → Prop} {i : Nat} :
    (∀ j < i + 1, P j) ↔ (∀ j < i, P j) ∧ P i :=
  ⟨fun h => ⟨fun j hj => h j (by omega), h i (by omega)⟩,
    fun h j hj => if hji : j < i then h.1 j hji else (show j = i by omega) ▸ h.2⟩

/-! ### Loops -/

/-- Soundness of `select_root` on a one-hot `tree` selecting `T`: root `T`, or `0`
when `T` is out of range. -/
theorem select_root_sound (D T : Nat) (tree : List (Boolean (ZMod p)))
    (roots : List (FpVar (ZMod p))) (k : Counters) (a : Assignment (ZMod p))
    (htree : tree.map (·.eval a) = (List.range D).map (fun i => if T = i then 1 else 0))
    (hroots : roots.length = D) (h : ConstraintsHold a ((select_root tree roots).run k).2) :
    ((select_root tree roots).run k).1.eval a =
      if T < D then (roots.map (·.eval a)).getD T 0 else 0 := by
  have hlen : (tree.zip roots).length = D := by simp [length_of_map_eq htree, hroots]
  -- After `i` entries, `root` is root `T` if `T < i`.
  have loop := CS.foldlM_inv _ a (tree.zip roots)
    (fun i (r : FpVar (ZMod p)) => r.eval a =
      if T < i then (roots.map (·.eval a)).getD T 0 else 0)
    _ k (by simp)
    (fun i hi r k' hr h' => by
      have hiD : i < D := hlen ▸ hi
      have ht : i < tree.length := by rw [length_of_map_eq htree]; exact hiD
      have hhit : IsBit a tree[i] (T = i) := getElem_of_map_eq htree i ht
      simp only [List.getElem_zip] at h' ⊢
      rw [select_bit hhit h', hr]
      by_cases hTi : T = i
      · subst hTi
        simp [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (hroots ▸ hiD)]
      · simp only [hTi, ↓reduceIte]
        exact if_congr (by omega) rfl rfl)
    h
  rwa [hlen] at loop

/-- Soundness of `check_steps`: `valid` gains `∀ i < MAX_DEPTH, i < path_len → i < rank`,
which is `path_len ≤ rank` when `path_len ≤ MAX_DEPTH`. -/
theorem check_steps_sound (D L R : Nat) (active within : List (Boolean (ZMod p)))
    (valid : Boolean (ZMod p)) (P : Prop) [Decidable P] (k : Counters) (a : Assignment (ZMod p))
    (hactive : active.map (·.eval a) = (List.range D).map (fun i => if i < L then 1 else 0))
    (hwithin : within.map (·.eval a) = (List.range D).map (fun i => if i < R then 1 else 0))
    (hvalid : IsBit a valid P) (h : ConstraintsHold a ((check_steps active within valid).run k).2) :
    IsBit a ((check_steps active within valid).run k).1 (P ∧ ∀ i < D, i < L → i < R) := by
  have hlen : (active.zip within).length = D := by
    simp [length_of_map_eq hactive, length_of_map_eq hwithin]
  -- After `i` entries, `valid` adds `j < path_len → j < rank` for each `j < i`.
  have loop := CS.foldlM_inv _ a (active.zip within)
    (fun i (v : Boolean (ZMod p)) => IsBit a v (P ∧ ∀ j < i, j < L → j < R))
    _ k (hvalid.congr (by simp))
    (fun i hi v k' hv h' => by
      have hiD : i < D := hlen ▸ hi
      have ha : i < active.length := by rw [length_of_map_eq hactive]; exact hiD
      have hw : i < within.length := by rw [length_of_map_eq hwithin]; exact hiD
      have hact : IsBit a active[i] (i < L) := getElem_of_map_eq hactive i ha
      have hwin : IsBit a within[i] (i < R) := getElem_of_map_eq hwithin i hw
      simp only [List.getElem_zip, CS.run_bind, constraintsHold_append] at h' ⊢
      refine (and_bit hv (or_bit hwin (not_bit hact) h'.1) h'.2).congr ?_
      rw [forall_lt_succ]
      constructor
      · rintro ⟨⟨hP, hj⟩, hi⟩; exact ⟨hP, hj, fun hiL => hi.resolve_right (not_not.mpr hiL)⟩
      · rintro ⟨hP, hj, hi⟩; exact ⟨⟨hP, hj⟩, by by_cases hiL : i < L <;> simp_all⟩)
    h
  rwa [hlen] at loop

/-- Soundness of `walk` on bit `right`s: the native fold over the first `path_len`
steps. -/
theorem walk_sound (D L : Nat) (H : HasherGadget (ZMod p)) (path : List (StepVar (ZMod p)))
    (active : List (Boolean (ZMod p))) (current : FpVar (ZMod p)) (k : Counters)
    (a : Assignment (ZMod p)) (hpath : path.length = D)
    (hright : ∀ s ∈ path, s.right.eval a = 0 ∨ s.right.eval a = 1)
    (hactive : active.map (·.eval a) = (List.range D).map (fun i => if i < L then 1 else 0))
    (h : ConstraintsHold a ((walk H path active current).run k).2) :
    ((walk H path active current).run k).1.eval a =
      ((path.map (·.decode a)).take L).foldl (fun c step => step.fold H.hash_native c)
        (current.eval a) := by
  have hlen : (path.zip active).length = D := by simp [hpath, length_of_map_eq hactive]
  -- After `i` steps, `current` has folded in the first `min i path_len` steps.
  have loop := CS.foldlM_inv _ a (path.zip active)
    (fun i (c : FpVar (ZMod p)) => c.eval a =
      ((path.map (·.decode a)).take (min i L)).foldl (fun c step => step.fold H.hash_native c)
        (current.eval a))
    _ k (by simp)
    (fun i hi c k' hc h' => by
      have hiD : i < D := hlen ▸ hi
      have ha : i < active.length := by rw [length_of_map_eq hactive]; exact hiD
      have hp : i < path.length := hpath ▸ hiD
      have hact : IsBit a active[i] (i < L) := getElem_of_map_eq hactive i ha
      simp only [List.getElem_zip, CS.run_bind, constraintsHold_append] at h' ⊢
      rw [select_bit hact h'.2, StepVar.fold_sound H _ _ _ a
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

/-! ### The output against the native verifier -/

/-- What the circuit's output bit says, against the specification. Here `Tf`,
`depf`, `Lf` and `Nf` are the values of `tree`, `depth`, `path_len` and
`packed_ranks`, and `Rf` is the rank the circuit selected. -/
theorem accept_iff (D : Nat) (hD : 2 ^ (RANK_BITS * D) < p)
    (Hn : ZMod p → ZMod p → ZMod p → ZMod p) (Tf depf Lf Nf cnt elem c0 c1 Rf : ZMod p)
    (hRf : Rf = if Tf.val < D then (State.rank_bits Nf.val Tf.val : ZMod p) else 0)
    (rootsE : List (ZMod p)) (hroots : rootsE.length = D)
    (ps : List (Step (ZMod p))) (hps : ps.length = D) (hN : Nf.val < 2 ^ (RANK_BITS * D)) :
    ((((Tf.val < D ∧ Tf.val < depf.val ∧ depf.val ≤ D) ∧ Lf.val ≤ D) ∧ Rf.val ≤ D) ∧
        ∀ i < D, i < Lf.val → i < Rf.val) ∧
      (ps.take Lf.val).foldl (fun c step => step.fold Hn c)
          (if Lf = Rf then elem else Hn elem c0 c1) =
        (if Tf.val < D then rootsE.getD Tf.val 0 else 0) ↔
    (State.try_from_parts D Nf.val depf.val cnt.val).isSome ∧
      (∀ r ∈ State.rank ⟨Nf.val, depf.val, cnt.val⟩ Tf.val, r ≤ D) ∧
      Proof.verify Hn ⟨rootsE, ⟨Nf.val, depf.val, cnt.val⟩, elem, Tf.val, (c0, c1), Lf.val, ps⟩ := by
  have hfrom : (State.try_from_parts D Nf.val depf.val cnt.val).isSome = true ↔
      depf.val ≤ D := by
    unfold State.try_from_parts
    split_ifs <;> simp <;> omega
  rw [hfrom]
  simp only [Proof.verify, State.rank, hps]
  by_cases hlive : Tf.val < D ∧ Tf.val < depf.val
  · -- A live tree: the circuit's rank and root are tree `T`'s.
    obtain ⟨hTD, hTdep⟩ := hlive
    set R := State.rank_bits Nf.val Tf.val
    have hRlt : R < p := lt_of_lt_of_le (rank_bits_lt _ _) (le_trans
      (Nat.pow_le_pow_right (by norm_num) (by simp only [RANK_BITS]; omega)) hD.le)
    have hR : Rf.val = R := by
      rw [hRf]; simp only [hTD, ↓reduceIte]; exact ZMod.val_cast_of_lt hRlt
    have hleaf : Lf = Rf ↔ Lf.val = R := by
      rw [hRf]; simp only [hTD, ↓reduceIte]; exact eq_natCast_iff _ hRlt
    have hroot : rootsE[Tf.val]? = some (rootsE.getD Tf.val 0) := by
      rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (by omega)]; rfl
    -- With `L ≤ D`, every step below `L` sitting below the rank is `L ≤ rank`.
    have hsteps : Lf.val ≤ D → ((∀ i < D, i < Lf.val → i < R) ↔ Lf.val ≤ R) := fun hLD =>
      ⟨fun h => by
        by_contra hc
        exact lt_irrefl R (h R (by omega) (by omega)), fun h i _ hi => by omega⟩
    simp only [hR, hleaf, hroot, hTD, hTdep, not_le.mpr hTdep, true_and, ↓reduceIte,
      Option.mem_def, Option.some.injEq, forall_eq']
    by_cases h1 : depf.val ≤ D <;> by_cases h2 : Lf.val ≤ D <;> by_cases h3 : R ≤ D <;>
      by_cases h4 : Lf.val ≤ R <;> simp [h1, h2, h3, h4, hsteps]
  · -- Not a live tree: the circuit rejects, and so does `Proof::verify`.
    by_cases hTD : Tf.val < D
    · have hTdep : depf.val ≤ Tf.val := by omega
      simp [hTD, hTdep, not_lt.mpr hTdep]
    · simp [hTD, List.getElem?_eq_none (show rootsE.length ≤ Tf.val by omega)]

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
  simp only [verify_circuit, ProofVar.verify, CS.run_bind, constraintsHold_append] at h ⊢
  obtain ⟨hfp, htree, hrank, hroot, hpm, hrm, hv1, hv2, hvalid, hleaf, hnode, hcur0, hwalk, heq,
    hout⟩ := h
  -- `StateVar::from_parts`: the ranks, `populated` and `bounded` of the frontier.
  obtain ⟨hN, hranksE, hpopE, hbndE⟩ :=
    from_parts_sound D hD packed_ranks depth count hpacked k a hfp
  -- `let tree = one_hot(&self.tree)`: the bit of `tree = i` for each `i`.
  have htreeE := one_hot_sound D hDp.le proof.tree _ a htree
  -- `let (rank, live) = state.rank(&tree)`.
  obtain ⟨hrankE, hliveE⟩ := rank_sound D _ _ _ _ _ _ a htreeE hranksE hpopE hbndE hrank
  -- The root of the selected tree.
  have hrootE := select_root_sound D _ _ roots _ a htreeE hroots hroot
  -- `let (active, path_bounded)` and `let (within, rank_bounded)`.
  obtain ⟨hactE, hpbE⟩ := prefix_mask_sound D hDp proof.path_len _ a hpm
  obtain ⟨hwithinE, hrbE⟩ := prefix_mask_sound D hDp _ _ a hrm
  -- `valid`: a live tree, both bounds, and `path_len <= rank`.
  have hvalidE := check_steps_sound D _ _ _ _ _ _ _ a hactE hwithinE
    (and_bit (and_bit hliveE hpbE hv1) hrbE hv2) hvalid
  -- `current`: the leaf itself, or the hash of the node and its children.
  have hstart := select_bit (FpVar.is_eq_sound _ _ _ a hleaf) hcur0
  rw [H.sound _ _ _ _ a hnode] at hstart
  -- The walk up the path.
  have hcurE := walk_sound D _ H proof.path _ _ _ a hpath hright hactE hwalk
  rw [hstart] at hcurE
  -- `valid & current.is_eq(&root)`, against the specification.
  rw [and_bit hvalidE (is_eq_bit _ _ heq) hout]
  refine if_congr ?_ rfl rfl
  rw [hcurE, hrootE]
  exact accept_iff D hD H.hash_native _ _ _ _ _ _ _ _ _ hrankE _ (by simpa using hroots) _
    (by simpa using hpath) hN

end SkewMmr
