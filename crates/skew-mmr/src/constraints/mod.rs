pub mod hasher;

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

use self::hasher::HasherGadget;
use crate::hasher::Hasher;
use crate::proof::{Proof, Step};

/// An inclusion proof for an element in a [`crate::SkewMmr`], padded to `MAX_DEPTH`.
#[derive(Debug, Clone)]
pub struct ProofVar<const MAX_DEPTH: usize, F: PrimeField, H: HasherGadget<F>> {
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
    /// See [`crate::proof::Proof::verify`] for the native implementation.
    pub fn verify(
        &self,
        roots: &[FpVar<F>; MAX_DEPTH],
        state: &FpVar<F>,
        element: &FpVar<F>,
    ) -> Result<(), SynthesisError> {
        let (ranks, depth) = unpack::<MAX_DEPTH, F>(state)?;

        // Select the root and rank of the tree that the proven node belongs to. A tree at or
        // above `depth` is padding, which reads as root 0 of rank 0 and would match an empty path.
        let populated = prefix_mask::<MAX_DEPTH, F>(&depth)?;
        let mut root = FpVar::zero();
        let mut rank = FpVar::zero();
        let mut live = Boolean::FALSE;
        for i in 0..MAX_DEPTH {
            let hit = self.tree.is_eq(&FpVar::constant(F::from(i as u64)))?;
            root = hit.select(&roots[i], &root)?;
            rank = hit.select(&ranks[i], &rank)?;
            live |= &hit & &populated[i];
        }
        live.enforce_equal(&Boolean::TRUE)?;

        let active = prefix_mask::<MAX_DEPTH, F>(&self.path_len)?;
        let within = prefix_mask::<MAX_DEPTH, F>(&rank)?;
        for (active, within) in active.iter().zip(&within) {
            // `path_len <= rank`, since every step the path takes must sit below `rank`.
            within.conditional_enforce_equal(&Boolean::TRUE, active)?;
        }

        // One step per level between the proven node and the tree root, so a node reached by
        // `L` steps in a tree of rank `r` has rank `r - L`, and is a leaf exactly when `L == r`.
        let is_leaf = self.path_len.is_eq(&rank)?;
        let node = H::hash(element, &self.children[0], &self.children[1])?;
        let mut current = is_leaf.select(element, &node)?;
        for (step, active) in self.path.iter().zip(&active) {
            current = active.select(&step.fold::<H>(&current)?, &current)?;
        }

        current.enforce_equal(&root)
    }
}
impl<F: PrimeField> StepVar<F> {
    /// Folds `current` into its parent.
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

/// Reads the `rank`s and `depth` from a word packed by [`crate::SkewMmr::state`].
fn unpack<const MAX_DEPTH: usize, F: PrimeField>(
    state: &FpVar<F>,
) -> Result<([FpVar<F>; MAX_DEPTH], FpVar<F>), SynthesisError> {
    let (bits, _) = state.to_bits_le_with_top_bits_zero(8 * (MAX_DEPTH + 5) + 1)?;
    let byte = |i: usize| Boolean::le_bits_to_fp(&bits[8 * i..8 * (i + 1)]);

    Ok((try_from_fn(&byte)?, byte(MAX_DEPTH)?))
}

/// Expands `value` into the mask `i < value` over `0..N`, enforcing that it lands in `0..=N`.
fn prefix_mask<const N: usize, F: PrimeField>(
    value: &FpVar<F>,
) -> Result<[Boolean<F>; N], SynthesisError> {
    let mut reached = Boolean::FALSE;
    let mask = try_from_fn(|i| {
        reached |= &value.is_eq(&FpVar::constant(F::from(i as u64)))?;
        Ok(!&reached)
    })?;

    let bounded = reached | &value.is_eq(&FpVar::constant(F::from(N as u64)))?;
    bounded.enforce_equal(&Boolean::TRUE)?;

    Ok(mask)
}

/// Builds an array from one fallible item per index.
fn try_from_fn<T, const N: usize>(
    f: impl FnMut(usize) -> Result<T, SynthesisError>,
) -> Result<[T; N], SynthesisError> {
    let items = (0..N).map(f).collect::<Result<Vec<_>, _>>()?;
    Ok(items.try_into().ok().expect("N items"))
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
    use ark_r1cs_std::GR1CSVar;
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

            let mmr = filled(n);
            let proof = mmr.prove(index as usize);
            let element = Fr::from(index);

            assert!(check(&mmr, &proof, element), "element {index} of {n}");
            assert_eq!(check(&mmr, &proof, element), native(&mmr, &proof, element));
        }
    }

    #[test]
    fn agrees_with_native_on_random_tampers() {
        let mut rng = test_rng();
        for _ in 0..100 {
            let n = rng.gen_range(1..100u64);
            let index = rng.gen_range(0..n);

            let mmr = filled(n);
            let mut proof = mmr.prove(index as usize);
            let mut element = Fr::from(index);

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
                _ => element = noise,
            }

            assert_eq!(
                check(&mmr, &proof, element),
                native(&mmr, &proof, element),
                "tampered proof of element {index} of {n}"
            );
        }
    }

    #[test]
    fn unpacks_a_packed_frontier() {
        let mmr: Mmr = filled(60);
        let cs = ConstraintSystem::<Fr>::new_ref();
        let state = input(&cs, Fr::from_le_bytes_mod_order(&mmr.state()));

        let (ranks, depth) = unpack::<MAX_DEPTH, Fr>(&state).unwrap();

        assert!(cs.is_satisfied().unwrap());
        assert_eq!(depth.value().unwrap(), Fr::from(mmr.depth() as u64));
        for (tree, rank) in ranks.iter().enumerate() {
            let packed = mmr.ranks()[tree].unwrap_or(0);
            assert_eq!(rank.value().unwrap(), Fr::from(packed), "rank {tree}");
        }
    }

    #[test]
    fn rejects_a_state_above_the_layout() {
        let cs = ConstraintSystem::<Fr>::new_ref();
        let mut bytes = [0u8; 32];
        bytes[MAX_DEPTH + 5] = 2;
        let state = input(&cs, Fr::from_le_bytes_mod_order(&bytes));

        let _ = unpack::<MAX_DEPTH, Fr>(&state).unwrap();

        assert!(!cs.is_satisfied().unwrap());
    }

    fn input(cs: &ConstraintSystemRef<Fr>, value: Fr) -> FpVar<Fr> {
        FpVar::new_input(cs.clone(), || Ok(value)).unwrap()
    }

    fn check(mmr: &Mmr, proof: &SampleProof, element: Fr) -> bool {
        circuit(mmr, proof, element).is_satisfied().unwrap()
    }

    fn native(mmr: &Mmr, proof: &SampleProof, element: Fr) -> bool {
        proof.verify(&mmr.roots(), &mmr.ranks(), &element)
    }

    fn circuit(mmr: &Mmr, proof: &SampleProof, element: Fr) -> ConstraintSystemRef<Fr> {
        let cs = ConstraintSystem::<Fr>::new_ref();
        let frontier = mmr.roots();

        let roots =
            try_from_fn(|i| FpVar::new_input(cs.clone(), || Ok(frontier[i].unwrap_or_default())))
                .unwrap();
        let state = input(&cs, Fr::from_le_bytes_mod_order(&mmr.state()));
        let element = FpVar::new_witness(cs.clone(), || Ok(element)).unwrap();
        let proof = ProofVar::new_witness(cs.clone(), || Ok(proof)).unwrap();

        proof.verify(&roots, &state, &element).unwrap();
        cs
    }
}
