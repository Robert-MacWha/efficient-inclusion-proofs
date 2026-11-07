/-
# `skew_mmr::constraints::state`

`StateVar`, built by `from_parts` (what `AllocVar::new_variable` calls once
the three words are allocated), and `StateVar::rank`.
-/
import SkewMmr.Mask
import SkewMmr.Native
import Mathlib.Data.Nat.Digits.Defs

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

/-! ### Bits and digits -/

/-- A field of a little-endian digit string is the matching bits of its value. -/
theorem ofDigits_drop_take (L : List Nat) (hL : ∀ x ∈ L, x < 2) (m r : Nat)
    (hmr : m + r ≤ L.length) :
    Nat.ofDigits 2 ((L.drop m).take r) = Nat.ofDigits 2 L / 2 ^ m % 2 ^ r := by
  have hlt : ∀ l : List Nat, (∀ x ∈ l, x < 2) → Nat.ofDigits 2 l < 2 ^ l.length :=
    fun l hl => Nat.ofDigits_lt_base_pow_length (by norm_num) hl
  have h1 : Nat.ofDigits 2 (L.take m) < 2 ^ m := by
    have := hlt (L.take m) fun x hx => hL x (List.mem_of_mem_take hx)
    rwa [List.length_take_of_le (by omega)] at this
  have h2 : Nat.ofDigits 2 ((L.drop m).take r) < 2 ^ r := by
    have := hlt ((L.drop m).take r) fun x hx => hL x (List.mem_of_mem_drop (List.mem_of_mem_take hx))
    rwa [List.length_take_of_le (by simp; omega)] at this
  conv_rhs => rw [← List.take_append_drop m L, Nat.ofDigits_append]
  rw [List.length_take_of_le (by omega), Nat.add_mul_div_left _ _ (by positivity),
    Nat.div_eq_of_lt h1, Nat.zero_add]
  conv_rhs => rw [← List.take_append_drop r (L.drop m), Nat.ofDigits_append]
  rw [List.length_take_of_le (by simp; omega), Nat.add_mul_mod_self_left, Nat.mod_eq_of_lt h2]

theorem leBitsValue_natCast {F : Type} [Field F] (L : List Nat) :
    leBitsValue (L.map (Nat.cast : Nat → F)) = ((Nat.ofDigits 2 L : Nat) : F) := by
  rw [Nat.coe_ofDigits]
  induction L with
  | nil => rfl
  | cons x L ih => simp only [List.map_cons, leBitsValue_cons, ih, Nat.ofDigits, Nat.cast_ofNat]

variable {p : Nat} [Fact p.Prime]

theorem val_of_bit {x : ZMod p} (hx : x = 0 ∨ x = 1) : x.val < 2 := by
  rcases hx with rfl | rfl
  · simp
  · rw [ZMod.val_one]; norm_num

/-- `RANK_BITS * i + RANK_BITS ≤ RANK_BITS * D` for `i < D`. -/
theorem rank_bits_le {i D : Nat} (hi : i < D) : RANK_BITS * i + RANK_BITS ≤ RANK_BITS * D := by
  simp only [RANK_BITS]; omega

/-- Soundness of `from_parts`: `packed_ranks` is a word below `2^(RANK_BITS *
MAX_DEPTH)` whose `RANK_BITS`-bit fields are `ranks`, `populated` is
`i < depth` and `bounded` is `depth ≤ MAX_DEPTH`. -/
theorem from_parts_sound (D : Nat) (hD : 2 ^ (RANK_BITS * D) < p)
    (packed_ranks depth count : FpVar (ZMod p)) (hpacked : ¬ packed_ranks.isConstant)
    (k : Counters) (a : Assignment (ZMod p))
    (h : ConstraintsHold a ((StateVar.from_parts D packed_ranks depth count).run k).2) :
    let s := ((StateVar.from_parts D packed_ranks depth count).run k).1
    let N := (packed_ranks.eval a).val
    N < 2 ^ (RANK_BITS * D) ∧
      s.ranks.map (·.eval a) =
        (List.range D).map (fun i => ((N / 2 ^ (RANK_BITS * i) % 2 ^ RANK_BITS : Nat) : ZMod p)) ∧
      s.populated.map (·.eval a) =
        (List.range D).map (fun i => if i < (depth.eval a).val then 1 else 0) ∧
      s.bounded.eval a = (if (depth.eval a).val ≤ D then 1 else 0) := by
  have hDp : D < p := lt_of_le_of_lt
    (le_trans (Nat.lt_two_pow_self).le (Nat.pow_le_pow_right (by norm_num) (by simp [RANK_BITS]; omega))) hD
  simp only [StateVar.from_parts, unpack, CS.run_bind, CS.run_pure, constraintsHold_append] at h ⊢
  obtain ⟨⟨hbits, -⟩, hmask, -⟩ := h
  obtain ⟨hlen, hbit, hval⟩ :=
    FpVar.to_bits_le_with_top_bits_zero_sound packed_ranks hpacked _ k a hbits
  obtain ⟨hpop, hbnd⟩ := prefix_mask_sound D hDp depth _ a hmask
  -- The bits as natural numbers.
  set bits := ((packed_ranks.to_bits_le_with_top_bits_zero (RANK_BITS * D)).run k).1.1
  set L := bits.map fun b => (b.eval a).val
  have hL : ∀ x ∈ L, x < 2 := by
    simp only [L, List.mem_map]
    rintro _ ⟨b, hb, rfl⟩
    exact val_of_bit (hbit b hb)
  have hcast : ∀ l : List (Boolean (ZMod p)), l.map (·.eval a) =
      (l.map fun b => (b.eval a).val).map (Nat.cast : Nat → ZMod p) := by
    intro l; simp [Function.comp_def]
  have hLlen : L.length = RANK_BITS * D := by simp [L, hlen]
  have hNlt : Nat.ofDigits 2 L < 2 ^ (RANK_BITS * D) := by
    rw [← hLlen]; exact Nat.ofDigits_lt_base_pow_length (by norm_num) hL
  have hN : (packed_ranks.eval a).val = Nat.ofDigits 2 L := by
    rw [hval, hcast, leBitsValue_natCast, ZMod.val_cast_of_lt (hNlt.trans hD)]
  refine ⟨hN ▸ hNlt, ?_, hpop, hbnd⟩
  rw [List.map_map]
  apply List.map_congr_left
  intro i hi
  rw [List.mem_range] at hi
  simp only [Function.comp_apply, Boolean.eval_le_bits_to_fp, hcast, hN]
  rw [List.map_take, List.map_drop, leBitsValue_natCast]
  congr 1
  exact ofDigits_drop_take L hL _ _ (hLlen ▸ rank_bits_le hi)

/-- The accumulator of `StateVar::rank` after `n` trees. -/
theorem rank_foldl (T dep : Nat) (R : Nat → ZMod p) (n : Nat) :
    (List.range n).foldl
        (fun (acc : ZMod p × ZMod p) (i : Nat) =>
          (acc.1 + (if T = i then 1 else 0) * (R i - acc.1),
            1 - (1 - acc.2) * (1 - (if T = i then 1 else 0) * (if i < dep then 1 else 0))))
        (0, 0) =
      (if T < n then R T else 0, if T < n ∧ T < dep then 1 else 0) := by
  induction n with
  | zero => simp
  | succ n ih =>
    rw [List.range_succ, List.foldl_append, ih]
    simp only [List.foldl_cons, List.foldl_nil, Prod.mk.injEq]
    refine ⟨?_, ?_⟩
    · by_cases h1 : T = n
      · subst h1; simp
      · have : T < n + 1 ↔ T < n := by omega
        simp [h1, this]
    · by_cases h1 : T = n <;> by_cases h2 : T < n <;> by_cases h3 : T < dep <;>
        simp [h1, h2, h3] <;> omega

/-- Soundness of `StateVar::rank` on a one-hot `tree` selecting `T`: the rank
of tree `T` and whether `T` is below `depth`, both zero when `T` falls outside
`0..MAX_DEPTH`. -/
theorem rank_sound (D T dep : Nat) (R : Nat → ZMod p) (s : StateVar (ZMod p))
    (tree : List (Boolean (ZMod p))) (k : Counters) (a : Assignment (ZMod p))
    (htree : tree.map (·.eval a) = (List.range D).map (fun i => if T = i then 1 else 0))
    (hranks : s.ranks.map (·.eval a) = (List.range D).map R)
    (hpop : s.populated.map (·.eval a) = (List.range D).map (fun i => if i < dep then 1 else 0))
    (h : ConstraintsHold a ((s.rank tree).run k).2) :
    ((s.rank tree).run k).1.1.eval a = (if T < D then R T else 0) ∧
      ((s.rank tree).run k).1.2.eval a =
        (if T < D ∧ T < dep then 1 else 0) * s.bounded.eval a := by
  simp only [StateVar.rank, CS.run_bind, CS.run_pure, constraintsHold_append] at h ⊢
  obtain ⟨hloop, hand, -⟩ := h
  -- The loop on values: select into the rank, `or` the live bit.
  let g : ZMod p × ZMod p → (ZMod p × ZMod p) × ZMod p → ZMod p × ZMod p :=
    fun acc x => (acc.1 + x.1.1 * (x.1.2 - acc.1), 1 - (1 - acc.2) * (1 - x.1.1 * x.2))
  let φ : (Boolean (ZMod p) × FpVar (ZMod p)) × Boolean (ZMod p) → (ZMod p × ZMod p) × ZMod p :=
    Prod.map (Prod.map (·.eval a) (·.eval a)) (·.eval a)
  have loop := CS.foldlM_sound _ (fun _ => True)
    (fun acc : FpVar (ZMod p) × Boolean (ZMod p) => (acc.1.eval a, acc.2.eval a))
    (fun acc x => g acc (φ x))
    a (fun acc x k' _ h' => by
      simp only [CS.run_bind, CS.run_pure, constraintsHold_append] at h' ⊢
      refine ⟨trivial, ?_⟩
      rw [FpVar.conditionally_select_sound _ _ _ _ a h'.1, Boolean.or_sound _ _ _ a h'.2.2.1,
        Boolean.and_sound _ _ _ a h'.2.1]
      rfl) _ _ k trivial hloop
  have hlist : ((tree.zip s.ranks).zip s.populated).map φ =
      (List.range D).map fun i => ((if T = i then 1 else 0, R i), if i < dep then 1 else 0) := by
    simp only [φ]
    rw [← List.zip_map, ← List.zip_map, htree, hranks, hpop, List.zip_map', List.zip_map']
  have hfold := loop.2
  rw [← List.foldl_map (f := φ) (g := g), hlist, List.foldl_map] at hfold
  simp only [FpVar.eval_zero, Boolean.eval_FALSE, g] at hfold
  rw [rank_foldl] at hfold
  simp only [Prod.mk.injEq] at hfold
  rw [Boolean.and_sound _ _ _ a hand, hfold.1, hfold.2]
  exact ⟨rfl, rfl⟩

end SkewMmr
