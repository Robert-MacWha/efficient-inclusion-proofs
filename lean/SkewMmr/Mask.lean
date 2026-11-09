/-
# `skew_mmr::constraints::mask`

The gadgets are generic in the field. Their soundness lemmas are stated over
`ZMod p`, where a value compared with the constants `0, 1, …` is read through
`ZMod.val`.
-/
import SkewMmr.Lemmas

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

/-! ### Soundness over `ZMod p` -/

variable {p : Nat} [Fact p.Prime]

/-- Soundness of `prefix_mask`: entry `i` is the bit of `i < value`, and `bounded`
is the bit of `value ≤ N`. -/
theorem prefix_mask_sound (N : Nat) (hN : N < p) (value : FpVar (ZMod p)) (k : Counters)
    (a : Assignment (ZMod p)) (h : ConstraintsHold a ((prefix_mask N value).run k).2) :
    let v := (value.eval a).val
    ((prefix_mask N value).run k).1.1.map (·.eval a) =
        (List.range N).map (fun i => if i < v then 1 else 0) ∧
      IsBit a ((prefix_mask N value).run k).1.2 (v ≤ N) := by
  intro v
  simp only [prefix_mask, CS.run_bind, CS.run_pure, constraintsHold_append] at h ⊢
  obtain ⟨hloop, he, hor, -⟩ := h
  -- After `i` steps, the mask holds `j < value` for each `j < i`, and `reached`
  -- is `value < i`.
  have loop := CS.foldlM_inv _ a (List.range N)
    (fun i (acc : List (Boolean (ZMod p)) × Boolean (ZMod p)) =>
      acc.1.map (·.eval a) = (List.range i).map (fun j => if j < v then 1 else 0) ∧
        IsBit a acc.2 (v < i))
    _ k ⟨rfl, IsBit.false.congr (by simp)⟩
    (fun i hi acc k' ⟨hmask, hreached⟩ h' => by
      simp only [List.length_range] at hi
      simp only [List.getElem_range, CS.run_bind, CS.run_pure, constraintsHold_append] at h' ⊢
      have he' := is_eq_const_bit value (show i < p by omega) h'.1
      have hreached' := (or_bit hreached he' h'.2.1).congr (show v < i ∨ v = i ↔ v < i + 1 by omega)
      refine ⟨?_, hreached'⟩
      rw [List.map_append, hmask, List.range_succ, List.map_append, List.map_singleton,
        List.map_singleton, (not_bit hreached').congr (show ¬ v < i + 1 ↔ i < v by omega)])
    hloop
  rw [List.length_range] at loop
  exact ⟨loop.1, (or_bit loop.2 (is_eq_const_bit value hN he) hor).congr (by omega)⟩

/-- Soundness of `one_hot`: entry `i` is the bit of `value = i`. -/
theorem one_hot_sound (N : Nat) (hN : N ≤ p) (value : FpVar (ZMod p)) (k : Counters)
    (a : Assignment (ZMod p)) (h : ConstraintsHold a ((one_hot N value).run k).2) :
    ((one_hot N value).run k).1.map (·.eval a) =
      (List.range N).map (fun i => if (value.eval a).val = i then 1 else 0) := by
  rw [one_hot, CS.mapM_map _ (fun b : Boolean (ZMod p) => b.eval a)
    (fun i : Nat => if value.eval a = (i : ZMod p) then 1 else 0) a
    (fun i k' h' => FpVar.is_eq_sound value (FpVar.Constant (i : ZMod p)) k' a h') (List.range N) k h]
  apply List.map_congr_left
  intro i hi
  simp only [eq_natCast_iff _ (show i < p by simp at hi; omega)]

end SkewMmr
