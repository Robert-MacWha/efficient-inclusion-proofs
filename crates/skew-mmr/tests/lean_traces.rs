//! Builds the circuit of `lean/Traces.lean` with the real gadgets and checks
//! that the arkworks constraint matrices and assignment match the trace the
//! Lean model renders into `crates/target/lean-traces` (`just lean`).

use ark_ff::{Field, Fp64, MontBackend, MontConfig};
use ark_r1cs_std::{GR1CSVar, alloc::AllocVar, fields::fp::FpVar};
use ark_r1cs_trace::{read_traces, render_trace};
use ark_relations::gr1cs::{ConstraintSystem, OptimizationGoal, SynthesisError};
use skew_mmr::{
    SkewMmr,
    constraints::{ProofVar, hasher::HasherGadget},
    hasher::Hasher,
    proof::Proof,
};

/// Configuration of [`F`].
#[derive(MontConfig)]
#[modulus = "65537"]
#[generator = "3"]
pub struct FConfig;

/// The prime field of order 65537, which the Lean traces use (`ZMod 65537`).
type F = Fp64<MontBackend<FConfig, 1>>;

const MAX_DEPTH: usize = 2;

/// `Traces.hasher`: `element * (left + 1) + right`.
struct TestHasher;

impl Hasher<F> for TestHasher {
    fn hash(element: &F, left: &F, right: &F) -> F {
        *element * (*left + F::ONE) + right
    }
}

impl HasherGadget<F> for TestHasher {
    fn hash(
        element: &FpVar<F>,
        left: &FpVar<F>,
        right: &FpVar<F>,
    ) -> Result<FpVar<F>, SynthesisError> {
        Ok(element * (left + F::ONE) + right)
    }
}

/// `Traces.check`: allocates the proof as the crate's own tests do and verifies it.
fn check(proof: &Proof<MAX_DEPTH, F, TestHasher>) -> String {
    let cs = ConstraintSystem::<F>::new_ref();
    cs.set_optimization_goal(OptimizationGoal::Constraints);
    let roots: [FpVar<F>; MAX_DEPTH] = std::array::from_fn(|i| {
        FpVar::new_witness(cs.clone(), || Ok(proof.roots[i].unwrap_or_default())).unwrap()
    });
    let element = FpVar::new_witness(cs.clone(), || Ok(proof.element)).unwrap();
    let proof_var = ProofVar::new_witness(cs.clone(), || Ok(proof)).unwrap();
    let valid = proof_var.verify(&element, &roots).unwrap();

    assert!(cs.is_satisfied().unwrap());
    assert_eq!(valid.value().unwrap(), proof.verify());
    render_trace(&cs).unwrap()
}

/// The proof `Traces.lean` renders: element 0 of an accumulator holding `0..4`.
///
/// The constraint matrices do not depend on the witness values, so one proof covers them.
fn proofs() -> Vec<(String, Proof<MAX_DEPTH, F, TestHasher>)> {
    let mut mmr = SkewMmr::<MAX_DEPTH, F, TestHasher>::new();
    for i in 0..4u64 {
        mmr.append(F::from(i));
    }
    vec![("verify".to_string(), mmr.prove(0))]
}

#[test]
#[ignore = "needs the traces rendered by the Lean model; run `just lean`"]
fn traces_match_lean_model() {
    let expected = read_traces(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../target/lean-traces"
    ))
    .expect("traces written by `lake env lean --run Traces.lean` (see `just lean`)");
    let proofs = proofs();
    assert_eq!(
        expected.len(),
        proofs.len(),
        "trace set differs from the Lean cases"
    );

    for (name, proof) in &proofs {
        assert_eq!(
            check(proof),
            expected[name],
            "{name}: arkworks trace differs from the Lean model"
        );
    }
}
