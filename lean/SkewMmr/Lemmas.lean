/-
# Proof tools

Lemmas the circuit proofs share. None of them is specific to the skew-MMR.

* Bits as propositions: `IsBit a b P` says `b` evaluates to `1` when `P` holds
  and to `0` otherwise. Each boolean gadget is restated on bits as logic
  (`and` is `∧`, `or` is `∨`, `select` is `if`), so the circuit proofs never
  do field arithmetic on bits.
* Loops: `CS.foldlM_inv` proves a loop by an invariant on the number of
  steps taken, and `getElem_of_map_eq` reads one entry of a list whose
  values are known.
-/
import SkewMmr.Hasher
import Mathlib.Algebra.Field.ZMod

namespace SkewMmr

open ArkR1CS

/-! ### Bits -/

section Bits

variable {F : Type} [Field F] {a : Assignment F} {k : Counters}

/-- `b` evaluates to the bit of `P`. -/
abbrev IsBit (a : Assignment F) (b : Boolean F) (P : Prop) [Decidable P] : Prop :=
  b.eval a = if P then 1 else 0

theorem IsBit.congr {b : Boolean F} {P Q : Prop} [Decidable P] [Decidable Q] (hb : IsBit a b P)
    (h : P ↔ Q) : IsBit a b Q := by
  rw [IsBit, hb]; exact if_congr h rfl rfl

theorem IsBit.false : IsBit a (Boolean.FALSE : Boolean F) False := by
  rw [IsBit, Boolean.eval_FALSE]; simp

theorem not_bit {b : Boolean F} {P : Prop} [Decidable P] (hb : IsBit a b P) :
    IsBit a b.not (¬ P) := by
  rw [IsBit, Boolean.eval_not, hb]; split_ifs <;> simp_all

theorem and_bit {x y : Boolean F} {P Q : Prop} [Decidable P] [Decidable Q]
    (hx : IsBit a x P) (hy : IsBit a y Q) (h : ConstraintsHold a ((x.and y).run k).2) :
    IsBit a ((x.and y).run k).1 (P ∧ Q) := by
  rw [IsBit, Boolean.and_sound x y k a h, hx, hy]; split_ifs <;> simp_all

theorem or_bit {x y : Boolean F} {P Q : Prop} [Decidable P] [Decidable Q]
    (hx : IsBit a x P) (hy : IsBit a y Q) (h : ConstraintsHold a ((x.or y).run k).2) :
    IsBit a ((x.or y).run k).1 (P ∨ Q) := by
  rw [IsBit, Boolean.or_sound x y k a h, hx, hy]; split_ifs <;> simp_all

variable [DecidableEq F]

/-- Selecting on the bit of `P` is `if P`. -/
theorem select_bit {c : Boolean F} {P : Prop} [Decidable P] {t f : FpVar F} (hc : IsBit a c P)
    (h : ConstraintsHold a ((FpVar.conditionally_select c t f).run k).2) :
    ((FpVar.conditionally_select c t f).run k).1.eval a = if P then t.eval a else f.eval a := by
  rw [FpVar.conditionally_select_sound c t f k a h, hc]; split_ifs <;> ring

theorem is_eq_bit (x y : FpVar F) (h : ConstraintsHold a ((EqGadget.is_eq (F := F) x y).run k).2) :
    IsBit a ((EqGadget.is_eq (F := F) x y).run k).1 (x.eval a = y.eval a) :=
  FpVar.is_eq_sound x y k a h

end Bits

/-! ### Small constants in `ZMod p` -/

section ZMod

variable {p : Nat} [Fact p.Prime]

theorem eq_natCast_iff (x : ZMod p) {i : Nat} (hi : i < p) : x = (i : ZMod p) ↔ x.val = i := by
  constructor
  · rintro rfl
    exact ZMod.val_cast_of_lt hi
  · intro h
    rw [← h, ZMod.natCast_zmod_val]

/-- Comparing with a small constant reads the value through `ZMod.val`. -/
theorem is_eq_const_bit (value : FpVar (ZMod p)) {i : Nat} (hi : i < p) {k : Counters}
    {a : Assignment (ZMod p)}
    (h : ConstraintsHold a
      ((EqGadget.is_eq (F := ZMod p) value (FpVar.Constant (i : ZMod p))).run k).2) :
    IsBit a ((EqGadget.is_eq (F := ZMod p) value (FpVar.Constant (i : ZMod p))).run k).1
      ((value.eval a).val = i) :=
  (is_eq_bit _ _ h).congr (by simp [eq_natCast_iff _ hi])

theorem val_lt_two_of_bit {x : ZMod p} (hx : x = 0 ∨ x = 1) : x.val < 2 := by
  rcases hx with rfl | rfl
  · simp
  · rw [ZMod.val_one]; norm_num

end ZMod

/-! ### Loops -/

section Loops

variable {F : Type} [Field F] {σ α β γ : Type}

/-- A loop invariant for `List.foldlM`: if `I 0` holds at the start, and step `i`
takes `I i` to `I (i + 1)` whenever its rows hold, then `I` holds after every
step. -/
theorem CS.foldlM_inv (f : σ → α → CS F σ) (a : Assignment F) :
    ∀ (xs : List α) (I : Nat → σ → Prop) (s : σ) (k : Counters), I 0 s →
      (∀ i (hi : i < xs.length) s k, I i s → ConstraintsHold a ((f s xs[i]).run k).2 →
        I (i + 1) ((f s xs[i]).run k).1) →
      ConstraintsHold a ((xs.foldlM f s).run k).2 → I xs.length ((xs.foldlM f s).run k).1
  | [], _, _, _, h0, _, _ => h0
  | x :: xs, I, s, k, h0, step, h => by
    simp only [List.foldlM_cons, CS.run_bind, constraintsHold_append] at h ⊢
    exact CS.foldlM_inv f a xs (fun i => I (i + 1)) _ _ (step 0 (by simp) s k h0 h.1)
      (fun i hi s k => step (i + 1) (by simp; omega) s k) h.2

theorem length_of_map_eq {l : List α} {g : α → β} {f : Nat → β} {n : Nat}
    (h : l.map g = (List.range n).map f) : l.length = n := by
  simpa using congrArg List.length h

/-- One entry of a list whose values are known. -/
theorem getElem_of_map_eq {l : List α} {g : α → β} {f : Nat → β} {n : Nat}
    (h : l.map g = (List.range n).map f) (i : Nat) (hi : i < l.length) : g l[i] = f i := by
  have := congrArg (·[i]?) h
  simp only [List.getElem?_map, List.getElem?_eq_getElem hi, List.getElem?_range
    (length_of_map_eq h ▸ hi), Option.map_some, Option.some.injEq] at this
  exact this

end Loops

end SkewMmr
