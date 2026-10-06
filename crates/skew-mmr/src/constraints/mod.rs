mod array;
pub mod hasher;
mod mask;
pub mod state;

use std::borrow::Borrow;
use std::marker::PhantomData;

use ark_ff::PrimeField;
use ark_r1cs_std::{
    alloc::{AllocVar, AllocationMode},
    boolean::Boolean,
    eq::EqGadget,
    fields::{FieldVar, fp::FpVar},
};
use ark_relations::gr1cs::{Namespace, SynthesisError};

use crate::{
    constraints::{array::try_from_fn, hasher::HasherGadget, mask::prefix_mask, state::StateVar},
    hasher::Hasher,
    proof::{Proof, Step},
};

/// An inclusion proof for an element in a [`crate::SkewMmr`], padded to `MAX_DEPTH`.
#[derive(Debug, Clone)]
pub struct ProofVar<const MAX_DEPTH: usize, F: PrimeField, H: HasherGadget<F>> {
    /// Roots of the frontier's trees. Entries above `depth` are padding.
    pub roots: [FpVar<F>; MAX_DEPTH],
    /// The frontier the proof is checked against.
    pub state: StateVar<MAX_DEPTH, F>,
    /// The proven element.
    pub element: FpVar<F>,

    /// Index into `roots` and the rank bytes of `state`.
    pub tree: FpVar<F>,
    /// The children of the proven node. Ignored when it is a leaf.
    pub children: [FpVar<F>; 2],
    /// Populated steps of `path`.
    pub path_len: FpVar<F>,
    /// Ancestors of the proven node, closest first. Steps from `path_len` on are padding.
    pub path: [StepVar<F>; MAX_DEPTH],
    pub hasher: PhantomData<H>,
}

/// One ancestor of the proven node.
#[derive(Debug, Clone)]
pub struct StepVar<F: PrimeField> {
    pub element: FpVar<F>,
    pub sibling: FpVar<F>,
    /// Whether the path descends into the right child.
    pub right: Boolean<F>,
}

impl<const MAX_DEPTH: usize, F: PrimeField, H: HasherGadget<F>> ProofVar<MAX_DEPTH, F, H> {
    /// Verifies the MMR inclusion proof.
    ///
    /// `roots` and `state` are witnesses like the rest of the proof, so they must be bound
    /// to authenticated public inputs in the circuit.
    ///
    /// See [`crate::proof::Proof::verify`] for the native implementation.
    #[tracing::instrument(target = "r1cs", skip_all)]
    pub fn verify(&self) -> Result<(), SynthesisError> {
        // `rank` enforces that the tree is live, so the root selected below is never padding.
        let rank = self.state.rank(&self.tree)?;
        let mut root = FpVar::zero();
        for (i, candidate) in self.roots.iter().enumerate() {
            let hit = self.tree.is_eq(&FpVar::constant(F::from(i as u64)))?;
            root = hit.select(candidate, &root)?;
        }

        let active = prefix_mask::<MAX_DEPTH, F>(&self.path_len)?;
        let within = prefix_mask::<MAX_DEPTH, F>(&rank)?;
        for (active, within) in active.iter().zip(&within) {
            // `path_len <= rank`, since every step the path takes must sit below `rank`.
            within.conditional_enforce_equal(&Boolean::TRUE, active)?;
        }

        // One step per level between the proven node and the tree root, so a node reached by
        // `L` steps in a tree of rank `r` has rank `r - L`, and is a leaf exactly when `L == r`.
        let is_leaf = self.path_len.is_eq(&rank)?;
        let node = H::hash(&self.element, &self.children[0], &self.children[1])?;
        let mut current = is_leaf.select(&self.element, &node)?;
        for (step, active) in self.path.iter().zip(&active) {
            current = active.select(&step.fold::<H>(&current)?, &current)?;
        }

        current.enforce_equal(&root)
    }
}

impl<F: PrimeField> StepVar<F> {
    /// Folds `current` into its parent.
    #[tracing::instrument(target = "r1cs", skip_all)]
    fn fold<H: HasherGadget<F>>(&self, current: &FpVar<F>) -> Result<FpVar<F>, SynthesisError> {
        let left = self.right.select(&self.sibling, current)?;
        let right = self.right.select(current, &self.sibling)?;

        H::hash(&self.element, &left, &right)
    }
}

impl<const MAX_DEPTH: usize, F, H> AllocVar<Proof<MAX_DEPTH, F, H>, F> for ProofVar<MAX_DEPTH, F, H>
where
    F: PrimeField,
    H: Hasher<F> + HasherGadget<F>,
{
    fn new_variable<T: Borrow<Proof<MAX_DEPTH, F, H>>>(
        cs: impl Into<Namespace<F>>,
        f: impl FnOnce() -> Result<T, SynthesisError>,
        mode: AllocationMode,
    ) -> Result<Self, SynthesisError> {
        let ns = cs.into();
        let cs = ns.cs();

        let proof = f()?;
        let proof = proof.borrow();
        let (left, right) = proof.children.unwrap_or_default();

        Ok(Self {
            roots: try_from_fn(|i| {
                FpVar::new_variable(cs.clone(), || Ok(proof.roots[i].unwrap_or_default()), mode)
            })?,
            state: StateVar::new_variable(cs.clone(), || Ok(proof.state), mode)?,
            element: FpVar::new_variable(cs.clone(), || Ok(proof.element), mode)?,
            tree: FpVar::new_variable(cs.clone(), || Ok(F::from(proof.tree as u64)), mode)?,
            children: [
                FpVar::new_variable(cs.clone(), || Ok(left), mode)?,
                FpVar::new_variable(cs.clone(), || Ok(right), mode)?,
            ],
            path_len: FpVar::new_variable(cs.clone(), || Ok(F::from(proof.path_len as u64)), mode)?,
            path: try_from_fn(|i| {
                let step = proof.path[i].clone().unwrap_or_default();
                StepVar::new_variable(cs.clone(), || Ok(step), mode)
            })?,
            hasher: PhantomData,
        })
    }
}

impl<F: PrimeField> AllocVar<Step<F>, F> for StepVar<F> {
    fn new_variable<T: Borrow<Step<F>>>(
        cs: impl Into<Namespace<F>>,
        f: impl FnOnce() -> Result<T, SynthesisError>,
        mode: AllocationMode,
    ) -> Result<Self, SynthesisError> {
        let ns = cs.into();
        let cs = ns.cs();

        let step = f()?;
        let step = step.borrow();

        Ok(Self {
            element: FpVar::new_variable(cs.clone(), || Ok(step.element), mode)?,
            sibling: FpVar::new_variable(cs.clone(), || Ok(step.sibling), mode)?,
            right: Boolean::new_variable(cs, || Ok(step.right), mode)?,
        })
    }
}

#[cfg(test)]
pub mod testing {
    use ark_bn254::Fr;

    use crate::SkewMmr;
    use crate::hasher::MockHasher;

    pub const MAX_DEPTH: usize = 8;

    pub type Mmr = SkewMmr<MAX_DEPTH, Fr, MockHasher>;
}

#[cfg(test)]
mod tests {
    use ark_bn254::Fr;
    use ark_relations::gr1cs::{ConstraintSystem, ConstraintSystemRef};
    use ark_std::rand::Rng;
    use ark_std::test_rng;

    use super::testing::{MAX_DEPTH, Mmr};
    use super::*;
    use crate::hasher::MockHasher;
    use crate::testing::filled;

    type SampleProof = Proof<MAX_DEPTH, Fr, MockHasher>;

    #[test]
    fn agrees_with_native_on_random_proofs() {
        let mut rng = test_rng();
        for _ in 0..50 {
            let n = rng.gen_range(1..100u64);
            let index = rng.gen_range(0..n);

            let mmr: Mmr = filled(n);
            let proof = mmr.prove(index as usize);

            assert!(check(&proof), "element {index} of {n}");
            assert_eq!(check(&proof), native(&proof));
        }
    }

    #[test]
    fn agrees_with_native_on_random_tampers() {
        let mut rng = test_rng();
        for _ in 0..100 {
            let n = rng.gen_range(1..100u64);
            let index = rng.gen_range(0..n);

            let mmr: Mmr = filled(n);
            let mut proof = mmr.prove(index as usize);

            let slot = rng.gen_range(0..MAX_DEPTH);
            let noise = Fr::from(rng.r#gen::<u64>());
            let len = rng.gen_range(0..=MAX_DEPTH);

            match rng.gen_range(0..8) {
                0 => proof.tree = rng.gen_range(0..MAX_DEPTH),
                1 => proof.tree = mmr.depth(),
                2 => proof.path_len = len,
                3 => proof.path[slot] = None,
                4 => {
                    if let Some(step) = proof.path[slot].as_mut() {
                        step.right ^= true;
                    }
                }
                5 => {
                    if let Some(step) = proof.path[slot].as_mut() {
                        step.sibling = noise;
                    }
                }
                6 => proof.children = proof.children.map(|(left, right)| (right, left)),
                _ => proof.element = noise,
            }

            assert_eq!(
                check(&proof),
                native(&proof),
                "tampered proof of element {index} of {n}"
            );
        }
    }

    fn check(proof: &SampleProof) -> bool {
        circuit(proof).is_satisfied().unwrap()
    }

    fn native(proof: &SampleProof) -> bool {
        proof.verify()
    }

    fn circuit(proof: &SampleProof) -> ConstraintSystemRef<Fr> {
        let cs = ConstraintSystem::<Fr>::new_ref();
        let proof = ProofVar::new_witness(cs.clone(), || Ok(proof)).unwrap();
        proof.verify().unwrap();
        cs
    }
}
