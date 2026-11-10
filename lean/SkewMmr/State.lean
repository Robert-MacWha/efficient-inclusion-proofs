/-
# `skew_mmr::constraints::state`

`StateVar`, built by `from_parts` (what `AllocVar::new_variable` calls once
the three words are allocated), and `StateVar::rank`.
-/
import SkewMmr.Mask
import SkewMmr.Native

namespace SkewMmr

open ArkR1CS

section Gadgets

variable {F : Type} [Field F] [DecidableEq F]

/-- `StateVar`. -/
structure StateVar (F : Type) where
  packed_ranks : FpVar F
  ranks : List (FpVar F)
  depth : FpVar F
  count : FpVar F
  /-- `i < depth` over each tree. -/
  populated : List (Boolean F)
  /-- Whether `depth` lands in `0..=MAX_DEPTH`. -/
  bounded : Boolean F

/-- `unpack::<MAX_DEPTH>`: the `RANK_BITS`-bit fields of `packed_ranks`. -/
def unpack [IntoBigInt F] (MAX_DEPTH : Nat) (packed_ranks : FpVar F) : CS F (List (FpVar F)) := do
  let r ← packed_ranks.to_bits_le_with_top_bits_zero (RANK_BITS * MAX_DEPTH)
  pure ((List.range MAX_DEPTH).map fun (i : Nat) =>
    Boolean.le_bits_to_fp ((r.1.drop (RANK_BITS * i)).take RANK_BITS))

/-- `StateVar::from_parts`. -/
def StateVar.from_parts [IntoBigInt F] (MAX_DEPTH : Nat) (packed_ranks depth count : FpVar F) :
    CS F (StateVar F) := do
  let ranks ← unpack MAX_DEPTH packed_ranks
  let m ← prefix_mask MAX_DEPTH depth
  pure ⟨packed_ranks, ranks, depth, count, m.1, m.2⟩

/-- `AllocVar::new_variable` for `StateVar`, in `AllocationMode::Witness`. -/
def StateVar.new_witness [IntoBigInt F] (MAX_DEPTH : Nat) (state : State) : CS F (StateVar F) := do
  let packed_ranks ← FpVar.new_witness (state.packed_ranks : F)
  let depth ← FpVar.new_witness (state.depth : F)
  let count ← FpVar.new_witness (state.count : F)
  StateVar.from_parts MAX_DEPTH packed_ranks depth count

/-- `StateVar::rank`: the rank of the tree selected by the one-hot mask `tree`,
and whether that tree is live. -/
def StateVar.rank (s : StateVar F) (tree : List (Boolean F)) : CS F (FpVar F × Boolean F) := do
  let acc ← ((tree.zip s.ranks).zip s.populated).foldlM
    (fun (acc : FpVar F × Boolean F) (x : (Boolean F × FpVar F) × Boolean F) => do
      let rank ← FpVar.conditionally_select x.1.1 x.1.2 acc.1
      let hp ← x.1.1.and x.2
      let live ← acc.2.or hp
      pure (rank, live)) (FpVar.zero, Boolean.FALSE)
  let live ← acc.2.and s.bounded
  pure (acc.1, live)

end Gadgets

/-! ### Soundness over `ZMod p` -/

/-- `RANK_BITS * i + RANK_BITS ≤ RANK_BITS * D` for `i < D`. -/
theorem rank_bits_le {i D : Nat} (hi : i < D) : RANK_BITS * i + RANK_BITS ≤ RANK_BITS * D := by
  simp only [RANK_BITS]; omega

theorem rank_bits_lt (N i : Nat) : State.rank_bits N i < 2 ^ RANK_BITS :=
  Nat.mod_lt _ (by positivity)

variable {p : Nat} [Fact p.Prime]

omit [Fact p.Prime] in
theorem D_lt_p {D : Nat} (hD : 2 ^ (RANK_BITS * D) < p) : D < p :=
  lt_of_le_of_lt (le_trans (Nat.lt_two_pow_self).le
    (Nat.pow_le_pow_right (by norm_num) (by simp [RANK_BITS]; omega))) hD

/-- Soundness of `unpack`: `packed_ranks` is below `2^(RANK_BITS * MAX_DEPTH)`, and
rank `i` is its rank bits for tree `i`. -/
theorem unpack_sound (D : Nat) (hD : 2 ^ (RANK_BITS * D) < p) (packed_ranks : FpVar (ZMod p))
    (hpacked : ¬ packed_ranks.isConstant) (k : Counters) (a : Assignment (ZMod p))
    (h : ConstraintsHold a ((unpack D packed_ranks).run k).2) :
    let N := (packed_ranks.eval a).val
    N < 2 ^ (RANK_BITS * D) ∧
      ((unpack D packed_ranks).run k).1.map (·.eval a) =
        (List.range D).map (fun i => (State.rank_bits N i : ZMod p)) := by
  simp only [unpack, CS.run_bind, CS.run_pure, constraintsHold_append, constraintsHold_nil,
    and_true] at h ⊢
  -- The bits spell `packed_ranks`, and bits `6i .. 6i + 6` spell rank `i`.
  obtain ⟨hN, hfield⟩ :=
    FpVar.to_bits_le_with_top_bits_zero_val packed_ranks hpacked _ hD k a h
  refine ⟨hN, ?_⟩
  rw [List.map_map]
  apply List.map_congr_left
  intro i hi
  rw [List.mem_range] at hi
  exact hfield _ _ (rank_bits_le hi)

/-- Soundness of `from_parts`: the ranks are the rank bits of `packed_ranks`,
`populated` is `i < depth` and `bounded` is `depth ≤ MAX_DEPTH`. -/
theorem from_parts_sound (D : Nat) (hD : 2 ^ (RANK_BITS * D) < p)
    (packed_ranks depth count : FpVar (ZMod p)) (hpacked : ¬ packed_ranks.isConstant)
    (k : Counters) (a : Assignment (ZMod p))
    (h : ConstraintsHold a ((StateVar.from_parts D packed_ranks depth count).run k).2) :
    let s := ((StateVar.from_parts D packed_ranks depth count).run k).1
    let N := (packed_ranks.eval a).val
    let dep := (depth.eval a).val
    N < 2 ^ (RANK_BITS * D) ∧
      s.ranks.map (·.eval a) = (List.range D).map (fun i => (State.rank_bits N i : ZMod p)) ∧
      s.populated.map (·.eval a) = (List.range D).map (fun i => if i < dep then 1 else 0) ∧
      IsBit a s.bounded (dep ≤ D) := by
  simp only [StateVar.from_parts, CS.run_bind, CS.run_pure, constraintsHold_append] at h ⊢
  obtain ⟨hunpack, hmask, -⟩ := h
  obtain ⟨hN, hranks⟩ := unpack_sound D hD packed_ranks hpacked k a hunpack
  obtain ⟨hpop, hbnd⟩ := prefix_mask_sound D (D_lt_p hD) depth _ a hmask
  exact ⟨hN, hranks, hpop, hbnd⟩

/-- Soundness of `StateVar::rank` on a one-hot `tree` selecting tree `T`: the rank of
tree `T` (`0` when `T` is out of range), and whether `T` is a live tree of a
frontier with depth in range. -/
theorem rank_sound (D T dep : Nat) (R : Nat → ZMod p) (s : StateVar (ZMod p))
    (tree : List (Boolean (ZMod p))) (k : Counters) (a : Assignment (ZMod p))
    (htree : tree.map (·.eval a) = (List.range D).map (fun i => if T = i then 1 else 0))
    (hranks : s.ranks.map (·.eval a) = (List.range D).map R)
    (hpop : s.populated.map (·.eval a) = (List.range D).map (fun i => if i < dep then 1 else 0))
    (hbnd : IsBit a s.bounded (dep ≤ D))
    (h : ConstraintsHold a ((s.rank tree).run k).2) :
    ((s.rank tree).run k).1.1.eval a = (if T < D then R T else 0) ∧
      IsBit a ((s.rank tree).run k).1.2 (T < D ∧ T < dep ∧ dep ≤ D) := by
  simp only [StateVar.rank, CS.run_bind, CS.run_pure, constraintsHold_append] at h ⊢
  obtain ⟨hloop, hand, -⟩ := h
  have hlen : ((tree.zip s.ranks).zip s.populated).length = D := by
    simp [length_of_map_eq_range htree, length_of_map_eq_range hranks, length_of_map_eq_range hpop]
  -- After `i` trees, `rank` is tree `T`'s if `T < i`, and `live` is `T < i ∧ T < depth`.
  have loop := CS.foldlM_inv _ a ((tree.zip s.ranks).zip s.populated)
    (fun i (acc : FpVar (ZMod p) × Boolean (ZMod p)) =>
      acc.1.eval a = (if T < i then R T else 0) ∧ IsBit a acc.2 (T < i ∧ T < dep))
    _ k ⟨by simp, IsBit.false.congr (by simp)⟩
    (fun i hi acc k' ⟨hrank, hlive⟩ h' => by
      have hiD : i < D := hlen ▸ hi
      have ht : i < tree.length := by rw [length_of_map_eq_range htree]; exact hiD
      have hr : i < s.ranks.length := by rw [length_of_map_eq_range hranks]; exact hiD
      have hp : i < s.populated.length := by rw [length_of_map_eq_range hpop]; exact hiD
      have hhit : IsBit a tree[i] (T = i) := getElem_of_map_eq_range htree i ht
      have hri : s.ranks[i].eval a = R i := getElem_of_map_eq_range hranks i hr
      have hpi : IsBit a s.populated[i] (i < dep) := getElem_of_map_eq_range hpop i hp
      simp only [List.getElem_zip, CS.run_bind, CS.run_pure, constraintsHold_append] at h' ⊢
      refine ⟨?_, (Boolean.or_bit hlive (Boolean.and_bit hhit hpi h'.2.1) h'.2.2.1).congr (by omega)⟩
      rw [FpVar.select_bit hhit h'.1, hri, hrank]
      by_cases hTi : T = i
      · simp [hTi]
      · simp only [hTi, ↓reduceIte]
        exact if_congr (by omega) rfl rfl)
    hloop
  rw [hlen] at loop
  exact ⟨loop.1, (Boolean.and_bit loop.2 hbnd hand).congr (by omega)⟩

end SkewMmr
