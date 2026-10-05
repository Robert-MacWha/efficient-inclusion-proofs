use std::borrow::Borrow;

use ark_ff::PrimeField;
use ark_r1cs_std::{
    alloc::{AllocVar, AllocationMode},
    boolean::Boolean,
    eq::EqGadget,
    fields::{FieldVar, fp::FpVar},
};
use ark_relations::gr1cs::{Namespace, SynthesisError};

use crate::hasher::{Hasher, HasherGadget};
use crate::proof::{Proof, Step};

/// An inclusion proof for an element in a [`crate::SkewMmr`], padded to `MAX_DEPTH`.
#[derive(Debug, Clone)]
pub struct ProofVar<const MAX_DEPTH: usize, F: PrimeField> {
    /// Index into `roots` and the rank bytes of `state`.
    pub tree: FpVar<F>,
    /// The children of the proven node. Ignored when it is a leaf.
    pub children: [FpVar<F>; 2],
    /// Populated steps of `path`.
    pub path_len: FpVar<F>,
    /// Ancestors of the proven node, closest first. Steps from `path_len` on are padding.
    pub path: [StepVar<F>; MAX_DEPTH],
}

/// One ancestor of the proven node.
#[derive(Debug, Clone)]
pub struct StepVar<F: PrimeField> {
    pub element: FpVar<F>,
    pub sibling: FpVar<F>,
    /// Whether the path descends into the right child.
    pub right: Boolean<F>,
}

impl<const MAX_DEPTH: usize, F: PrimeField, H: Hasher<F>> AllocVar<Proof<MAX_DEPTH, F, H>, F>
    for ProofVar<MAX_DEPTH, F>
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
        let (left, right) = proof.children.unwrap_or((F::zero(), F::zero()));
        let path_len = proof.path_len();

        Ok(Self {
            tree: FpVar::new_variable(cs.clone(), || Ok(F::from(proof.tree as u64)), mode)?,
            children: [
                FpVar::new_variable(cs.clone(), || Ok(left), mode)?,
                FpVar::new_variable(cs.clone(), || Ok(right), mode)?,
            ],
            path_len: FpVar::new_variable(cs.clone(), || Ok(F::from(path_len as u64)), mode)?,
            path: try_from_fn(|i| {
                let step = proof.path[i].clone().unwrap_or_default();
                StepVar::new_variable(cs.clone(), || Ok(step), mode)
            })?,
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

/// Verifies that `element` is held by the accumulator described by `roots` and `state`.
///
/// `roots` and `state` must come from the same frontier and be authenticated by the caller.
/// Returns the verdict rather than enforcing it.
pub fn verify<const MAX_DEPTH: usize, F: PrimeField, H: HasherGadget<F>>(
    roots: &[FpVar<F>; MAX_DEPTH],
    state: &FpVar<F>,
    element: &FpVar<F>,
    proof: &ProofVar<MAX_DEPTH, F>,
) -> Result<Boolean<F>, SynthesisError> {
    let (ranks, depth) = unpack::<MAX_DEPTH, F>(state)?;

    // Select the root and rank of the tree that the proven node belongs to. A tree at or above
    // `depth` is padding, which reads as root 0 of rank 0 and would match an empty path.
    let (populated, _) = prefix_mask::<MAX_DEPTH, F>(&depth)?;
    let mut root = FpVar::zero();
    let mut rank = FpVar::zero();
    let mut live = Boolean::FALSE;
    for i in 0..MAX_DEPTH {
        let hit = proof.tree.is_eq(&FpVar::constant(F::from(i as u64)))?;
        root = hit.select(&roots[i], &root)?;
        rank = hit.select(&ranks[i], &rank)?;
        live |= &hit & &populated[i];
    }

    // One step per level between the proven node and the tree root, so a node reached by
    // `L` steps in a tree of rank `r` has rank `r - L`, and is a leaf exactly when `L == r`.
    let is_leaf = proof.path_len.is_eq(&rank)?;
    let node = H::hash(element, &proof.children[0], &proof.children[1])?;
    let mut current = is_leaf.select(element, &node)?;

    let (active, bounded) = prefix_mask::<MAX_DEPTH, F>(&proof.path_len)?;
    let (within, rank_ok) = prefix_mask::<MAX_DEPTH, F>(&rank)?;
    for (step, active) in proof.path.iter().zip(&active) {
        let folded = fold::<F, H>(step, &current)?;
        current = active.select(&folded, &current)?;
    }

    // `path_len <= rank`, since every step below `path_len` must also sit below `rank`.
    let fits = Boolean::kary_and(&try_from_fn::<_, MAX_DEPTH>(|i| {
        Ok(!&active[i] | &within[i])
    })?)?;

    Boolean::kary_and(&[live, bounded, rank_ok, fits, current.is_eq(&root)?])
}

/// Reads the `rank`s and `depth` back out of a word packed by [`crate::SkewMmr::state`].
fn unpack<const MAX_DEPTH: usize, F: PrimeField>(
    state: &FpVar<F>,
) -> Result<([FpVar<F>; MAX_DEPTH], FpVar<F>), SynthesisError> {
    let (bits, _) = state.to_bits_le_with_top_bits_zero(8 * (MAX_DEPTH + 5) + 1)?;
    let byte = |i: usize| Boolean::le_bits_to_fp(&bits[8 * i..8 * (i + 1)]);

    Ok((try_from_fn(&byte)?, byte(MAX_DEPTH)?))
}

/// Expands `value` into the mask `i < value` over `0..N`, and whether `value` lands in `0..=N`.
fn prefix_mask<const N: usize, F: PrimeField>(
    value: &FpVar<F>,
) -> Result<([Boolean<F>; N], Boolean<F>), SynthesisError> {
    let mut reached = Boolean::FALSE;
    let mask = try_from_fn(|i| {
        reached |= &value.is_eq(&FpVar::constant(F::from(i as u64)))?;
        Ok(!&reached)
    })?;

    let bounded = reached | &value.is_eq(&FpVar::constant(F::from(N as u64)))?;
    Ok((mask, bounded))
}

/// Folds `current` into its parent.
fn fold<F: PrimeField, H: HasherGadget<F>>(
    step: &StepVar<F>,
    current: &FpVar<F>,
) -> Result<FpVar<F>, SynthesisError> {
    let left = step.right.select(&step.sibling, current)?;
    let right = step.right.select(current, &step.sibling)?;

    H::hash(&step.element, &left, &right)
}

/// Builds an array from one fallible item per index.
fn try_from_fn<T, const N: usize>(
    f: impl FnMut(usize) -> Result<T, SynthesisError>,
) -> Result<[T; N], SynthesisError> {
    let items = (0..N).map(f).collect::<Result<Vec<_>, _>>()?;
    Ok(items.try_into().ok().expect("N items"))
}

#[cfg(test)]
mod tests {
    use std::array::from_fn;

    use ark_bn254::Fr;
    use ark_r1cs_std::GR1CSVar;
    use ark_relations::gr1cs::{ConstraintSystem, ConstraintSystemRef};
    use ark_std::rand::Rng;
    use ark_std::test_rng;

    use super::*;
    use crate::hasher::MockHasher;
    use crate::testing::{FieldMmr, MAX_DEPTH, field_filled};

    type SampleProof = Proof<MAX_DEPTH, Fr, MockHasher>;

    #[test]
    fn agrees_with_native_on_random_proofs() {
        let mut rng = test_rng();
        for _ in 0..50 {
            let n = rng.gen_range(1..100u64);
            let index = rng.gen_range(0..n);

            let mmr = field_filled(n);
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

            let mmr = field_filled(n);
            let mut proof = mmr.prove(index as usize);
            let mut element = Fr::from(index);

            let slot = rng.gen_range(0..MAX_DEPTH);
            let noise = Fr::from(rng.r#gen::<u64>());
            let len = rng.gen_range(0..=MAX_DEPTH);

            match rng.gen_range(0..8) {
                0 => proof.tree = rng.gen_range(0..MAX_DEPTH),
                1 => proof.tree = mmr.depth(),
                2 => proof.path = resized(&proof.path, len),
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

    /// Native treats children on a leaf as malformed; the gadget selects on `path_len == rank`
    /// and never reads them, exactly as `SkewMmrInclusion` does.
    #[test]
    fn ignores_the_children_of_a_leaf() {
        let mmr = field_filled(60);
        let (index, leaf) = (0..60)
            .map(|i| (i, mmr.prove(i)))
            .find(|(_, proof)| proof.children.is_none())
            .expect("a leaf");
        let element = Fr::from(index as u64);

        let forged = SampleProof {
            children: Some((Fr::from(1u64), Fr::from(2u64))),
            ..leaf
        };

        assert!(check(&mmr, &forged, element));
        assert!(!native(&mmr, &forged, element));
    }

    #[test]
    fn is_unsatisfied_when_a_rejected_verdict_is_enforced() {
        let mmr = field_filled(60);
        let mut proof = mmr.prove(40);
        proof.path[0].as_mut().expect("a populated step").sibling = Fr::from(7u64);

        let (cs, verdict) = circuit(&mmr, &proof, Fr::from(40u64));
        verdict.enforce_equal(&Boolean::TRUE).unwrap();

        assert!(!cs.is_satisfied().unwrap());
    }

    fn check(mmr: &FieldMmr, proof: &SampleProof, element: Fr) -> bool {
        let (cs, verdict) = circuit(mmr, proof, element);
        assert!(cs.is_satisfied().unwrap(), "the gadget's own constraints");

        verdict.value().unwrap()
    }

    fn native(mmr: &FieldMmr, proof: &SampleProof, element: Fr) -> bool {
        proof.verify(&mmr.roots(), &mmr.ranks(), &element)
    }

    /// Rebuilds a path of `len` identical steps.
    fn resized(path: &[Option<Step<Fr>>; MAX_DEPTH], len: usize) -> [Option<Step<Fr>>; MAX_DEPTH] {
        from_fn(|i| match i < len {
            true => path[0].clone(),
            false => None,
        })
    }

    fn circuit(
        mmr: &FieldMmr,
        proof: &SampleProof,
        element: Fr,
    ) -> (ConstraintSystemRef<Fr>, Boolean<Fr>) {
        let cs = ConstraintSystem::<Fr>::new_ref();
        let frontier = mmr.roots();
        let packed = Fr::from_le_bytes_mod_order(&mmr.state());

        let roots =
            try_from_fn(|i| FpVar::new_input(cs.clone(), || Ok(frontier[i].unwrap_or_default())))
                .unwrap();
        let state = FpVar::new_input(cs.clone(), || Ok(packed)).unwrap();
        let element = FpVar::new_witness(cs.clone(), || Ok(element)).unwrap();
        let proof = ProofVar::new_witness(cs.clone(), || Ok(proof)).unwrap();

        let verdict =
            verify::<MAX_DEPTH, Fr, MockHasher>(&roots, &state, &element, &proof).unwrap();
        (cs, verdict)
    }
}
