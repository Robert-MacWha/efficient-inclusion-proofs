/-
# `skew_mmr::constraints::mask`

The gadgets are generic in the field; their soundness lemmas are stated over
`ZMod p`, where a value compared against the constants `0, 1, …` is read
through `ZMod.val`.
-/
import SkewMmr.Hasher
import Mathlib.Algebra.Field.ZMod

namespace SkewMmr

open ArkR1CS

section Gadgets

variable {F : Type} [Field F] [DecidableEq F]

/-- `prefix_mask::<N>`: the mask `i < value` over `0..N`, and whether `value`
lands in `0..=N`. -/
def prefix_mask (N : Nat) (value : FpVar F) : CS F (List (Boolean F) × Boolean F) := do
  let acc ← (List.range N).foldlM (fun (acc : List (Boolean F) × Boolean F) (i : Nat) => do
      let e ← EqGadget.is_eq (F := F) value (FpVar.Constant (i : F))
      let reached ← acc.2.or e
      pure (acc.1 ++ [reached.not], reached)) ([], Boolean.FALSE)
  let e ← EqGadget.is_eq (F := F) value (FpVar.Constant (N : F))
  let bounded ← acc.2.or e
  pure (acc.1, bounded)

/-- `one_hot::<N>`: the mask `i == value` over `0..N`. -/
def one_hot (N : Nat) (value : FpVar F) : CS F (List (Boolean F)) :=
  (List.range N).mapM fun (i : Nat) => EqGadget.is_eq (F := F) value (FpVar.Constant (i : F))

end Gadgets

/-! ### Indicator arithmetic -/

section Indicators

variable {F : Type} [Field F]

theorem ite_mul_ite (P Q : Prop) [Decidable P] [Decidable Q] :
    (if P then 1 else 0 : F) * (if Q then 1 else 0) = if P ∧ Q then 1 else 0 := by
  by_cases P <;> by_cases Q <;> simp [*]

theorem one_sub_ite (P : Prop) [Decidable P] :
    1 - (if P then 1 else 0 : F) = if ¬ P then 1 else 0 := by
  by_cases P <;> simp [*]

theorem ite_or_ite (P Q : Prop) [Decidable P] [Decidable Q] :
    1 - (1 - (if P then 1 else 0 : F)) * (1 - if Q then 1 else 0) = if P ∨ Q then 1 else 0 := by
  by_cases P <;> by_cases Q <;> simp [*]

end Indicators

/-! ### Soundness over `ZMod p` -/

variable {p : Nat} [Fact p.Prime]

theorem eq_natCast_iff (x : ZMod p) {i : Nat} (hi : i < p) : x = (i : ZMod p) ↔ x.val = i := by
  constructor
  · rintro rfl
    exact ZMod.val_cast_of_lt hi
  · intro h
    rw [← h, ZMod.natCast_zmod_val]

theorem is_eq_constant_sound (value : FpVar (ZMod p)) (c : ZMod p) (k : Counters)
    (a : Assignment (ZMod p))
    (h : ConstraintsHold a ((EqGadget.is_eq (F := ZMod p) value (FpVar.Constant c)).run k).2) :
    ((EqGadget.is_eq (F := ZMod p) value (FpVar.Constant c)).run k).1.eval a =
      if value.eval a = c then 1 else 0 :=
  FpVar.is_eq_sound value (FpVar.Constant c) k a h

/-- The accumulator of `prefix_mask` after `n` steps, for `value = v`. -/
theorem prefix_mask_foldl (v : ZMod p) (n : Nat) (hn : n ≤ p) :
    (List.range n).foldl
        (fun (acc : List (ZMod p) × ZMod p) (i : Nat) =>
          (acc.1 ++ [1 - (1 - (1 - acc.2) * (1 - if v = (i : ZMod p) then 1 else 0))],
            1 - (1 - acc.2) * (1 - if v = (i : ZMod p) then 1 else 0)))
        ([], 0) =
      ((List.range n).map fun i => if i < v.val then 1 else 0, if v.val < n then 1 else 0) := by
  induction n with
  | zero => simp
  | succ n ih =>
    rw [List.range_succ, List.foldl_append, ih (by omega)]
    have hv : (if v = (n : ZMod p) then 1 else 0 : ZMod p) = if v.val = n then 1 else 0 := by
      simp only [eq_natCast_iff v (show n < p by omega)]
    simp only [List.foldl_cons, List.foldl_nil, hv, List.map_append, List.map_cons, List.map_nil,
      Prod.mk.injEq]
    refine ⟨?_, ?_⟩
    · congr 2
      by_cases h1 : v.val < n <;> by_cases h2 : v.val = n <;> simp [h1, h2] <;> omega
    · by_cases h1 : v.val < n <;> by_cases h2 : v.val = n <;> simp [h1, h2] <;> omega

/-- Soundness of `prefix_mask`: entry `i` is `i < value`, and `bounded` is
`value ≤ N`, reading `value` through `ZMod.val`. -/
theorem prefix_mask_sound (N : Nat) (hN : N < p) (value : FpVar (ZMod p)) (k : Counters)
    (a : Assignment (ZMod p)) (h : ConstraintsHold a ((prefix_mask N value).run k).2) :
    ((prefix_mask N value).run k).1.1.map (·.eval a) =
        (List.range N).map (fun i => if i < (value.eval a).val then 1 else 0) ∧
      ((prefix_mask N value).run k).1.2.eval a =
        if (value.eval a).val ≤ N then 1 else 0 := by
  simp only [prefix_mask, CS.run_bind, CS.run_pure, constraintsHold_append] at h ⊢
  obtain ⟨hloop, he, hor, -⟩ := h
  have loop := CS.foldlM_sound _ (fun _ => True)
    (fun acc : List (Boolean (ZMod p)) × Boolean (ZMod p) =>
      (acc.1.map (fun b => b.eval a), acc.2.eval a))
    (fun (acc : List (ZMod p) × ZMod p) (i : Nat) =>
      (acc.1 ++ [1 - (1 - (1 - acc.2) * (1 - if value.eval a = (i : ZMod p) then 1 else 0))],
        1 - (1 - acc.2) * (1 - if value.eval a = (i : ZMod p) then 1 else 0)))
    a (fun acc i k' _ h' => by
      simp only [CS.run_bind, CS.run_pure, constraintsHold_append] at h' ⊢
      have he' := is_eq_constant_sound value (i : ZMod p) k' a h'.1
      have hor' := Boolean.or_sound _ _ _ a h'.2.1
      refine ⟨trivial, ?_⟩
      simp only [List.map_append, List.map_cons, List.map_nil, Boolean.eval_not, hor', he'])
    (List.range N) ([], Boolean.FALSE) k trivial hloop
  simp only [List.map_nil, Boolean.eval_FALSE] at loop
  rw [prefix_mask_foldl _ N hN.le] at loop
  simp only [Prod.mk.injEq] at loop
  refine ⟨loop.2.1, ?_⟩
  rw [Boolean.or_sound _ _ _ a hor, loop.2.2, is_eq_constant_sound value _ _ a he]
  simp only [eq_natCast_iff _ hN]
  by_cases h1 : (value.eval a).val < N <;> by_cases h2 : (value.eval a).val = N <;>
    simp [h1, h2] <;> omega

/-- Soundness of `one_hot`: entry `i` is `value == i`, reading `value` through
`ZMod.val`. -/
theorem one_hot_sound (N : Nat) (hN : N ≤ p) (value : FpVar (ZMod p)) (k : Counters)
    (a : Assignment (ZMod p)) (h : ConstraintsHold a ((one_hot N value).run k).2) :
    ((one_hot N value).run k).1.map (·.eval a) =
      (List.range N).map (fun i => if (value.eval a).val = i then 1 else 0) := by
  rw [one_hot, CS.mapM_map _ (fun b : Boolean (ZMod p) => b.eval a) (fun i : Nat => if value.eval a = (i : ZMod p) then 1 else 0) a
    (fun i k' h' => is_eq_constant_sound value _ k' a h') (List.range N) k h]
  apply List.map_congr_left
  intro i hi
  simp only [eq_natCast_iff _ (show i < p by simp at hi; omega)]

end SkewMmr
