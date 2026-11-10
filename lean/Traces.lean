/-
# Differential traces

The circuit of `crates/skew-mmr/tests/lean_traces.rs` (allocate a proof, then
`ProofVar::verify`) for one proof, rendered with `renderTrace`. That test
builds the same circuit with the real gadgets and checks that the arkworks
constraint matrices and assignment match, so any divergence between the model
and the Rust fails `just lean`.

The field is `ZMod 65537`, `MAX_DEPTH` is 2, and the hash is
`element * (left + 1) + right`.
-/
import SkewMmr
import Mathlib.Tactic.NormNum.Prime

open ArkR1CS SkewMmr

abbrev F := ZMod 65537

instance : Fact (Nat.Prime 65537) := ⟨by norm_num⟩

namespace Traces

/-- `TestHasher`: `element * (left + 1) + right`. -/
def hasher : HasherGadget F where
  hash_native e l r := e * (l + 1) + r
  hash e l r := do
    let m ← e.mul (l + FpVar.Constant 1)
    pure (m + r)
  sound e l r k a h := by
    simp only [CS.run_bind, CS.run_pure, constraintsHold_append] at h ⊢
    rw [FpVar.eval_hAdd, FpVar.mul_sound e _ k a h.1, FpVar.eval_hAdd, FpVar.eval_Constant]

/-- `check`: allocates the proof as the crate's tests do, then verifies it. -/
def check (q : Proof F) : CS F (Boolean F) := do
  let roots ← q.roots.mapM FpVar.new_witness
  let element ← FpVar.new_witness q.element
  let proof ← ProofVar.new_witness q
  proof.verify 2 hasher element roots

/-- `Step::default()`. -/
def pad : Step F := ⟨0, 0, false⟩

/-- A proof against the accumulator holding `0..4`: trees of rank 1 and 0, with roots 4 and 3. -/
def proof (element : F) (tree : Nat) (children : F × F) (path_len : Nat) (path : List (Step F)) :
    Proof F :=
  ⟨[4, 3], element, tree, children, path_len, path⟩

/-- Element 0 of the accumulator holding `0..4`. The constraint matrices do not
depend on the witness values, so one proof covers them. -/
def cases : List (String × Proof F) :=
  [("verify", proof 0 0 (0, 0) 1 [⟨2, 1, true⟩, pad])]

def render (q : Proof F) : String :=
  renderTrace (fun x : F => toString x.val) ((check q).run Counters.new).2

end Traces

/-- Write every trace to `<dir>/<name>.trace`. -/
def main (args : List String) : IO Unit := do
  let some dir := args.head? | throw (IO.userError "usage: lean --run Traces.lean <dir>")
  for (name, q) in Traces.cases do
    IO.FS.writeFile s!"{dir}/{name}.trace" (Traces.render q)

-- Every case is satisfied by the prover's own assignment, and the circuit
-- agrees with the native verifier.
#eval show IO Unit from do
  for (name, q) in Traces.cases do
    let (out, ops) := (Traces.check q).run Counters.new
    unless isSatisfied ops do
      throw (IO.userError s!"{name} is not satisfied by the prover's assignment")
    unless out.value == q.verify Traces.hasher.hash_native do
      throw (IO.userError s!"{name}: the circuit disagrees with the native verifier")
