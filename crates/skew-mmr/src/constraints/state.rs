use std::borrow::Borrow;

use ark_ff::{BigInteger, PrimeField};
use ark_r1cs_std::{
    GR1CSVar,
    alloc::{AllocVar, AllocationMode},
    boolean::Boolean,
    eq::EqGadget,
    fields::{FieldVar, fp::FpVar},
};
use ark_relations::gr1cs::{ConstraintSystemRef, Namespace, SynthesisError};

use crate::{
    constraints::{array::try_from_fn, mask::prefix_mask},
    state::{RANK_BITS, State},
};

/// The R1CS form of [`crate::state::State`].
/// within the functions and just hold `packed_ranks` in the struct.
#[derive(Debug, Clone)]
pub struct StateVar<const MAX_DEPTH: usize, F: PrimeField> {
    packed_ranks: FpVar<F>,
    ranks: [FpVar<F>; MAX_DEPTH],
    depth: FpVar<F>,
    count: FpVar<F>,
    /// `i < depth` over each tree, computed once so every [`Self::rank`] shares it.
    populated: [Boolean<F>; MAX_DEPTH],
    /// Whether `depth` lands in `0..=MAX_DEPTH`.
    bounded: Boolean<F>,
}

impl<const MAX_DEPTH: usize, F: PrimeField> StateVar<MAX_DEPTH, F> {
    /// The packed `rank`s.
    #[tracing::instrument(target = "r1cs", skip_all)]
    pub fn packed_ranks(&self) -> &FpVar<F> {
        &self.packed_ranks
    }

    /// The number of live trees.
    #[tracing::instrument(target = "r1cs", skip_all)]
    pub fn depth(&self) -> &FpVar<F> {
        &self.depth
    }

    /// The number of elements held by the accumulator.
    #[tracing::instrument(target = "r1cs", skip_all)]
    pub fn count(&self) -> &FpVar<F> {
        &self.count
    }

    /// The rank of the tree selected by the one-hot mask `tree` (see
    /// [`crate::constraints::mask::one_hot`]), and whether it sits below [`Self::depth`].
    /// Where the native [`State::rank`] would return `None`, this reports `false`.
    #[tracing::instrument(target = "r1cs", skip_all)]
    pub fn rank(
        &self,
        tree: &[Boolean<F>; MAX_DEPTH],
    ) -> Result<(FpVar<F>, Boolean<F>), SynthesisError> {
        // A tree at or above `depth` is padding, which reads as rank 0 and would match an
        // empty path.
        let mut rank = FpVar::zero();
        let mut live = Boolean::FALSE;
        for ((hit, rank_i), populated) in tree.iter().zip(&self.ranks).zip(&self.populated) {
            rank = hit.select(rank_i, &rank)?;
            live |= hit & populated;
        }

        Ok((rank, live & &self.bounded))
    }

    /// Builds the state from its allocated parts, unpacking `packed_ranks` and masking
    /// the trees below `depth`.
    fn from_parts(
        packed_ranks: FpVar<F>,
        depth: FpVar<F>,
        count: FpVar<F>,
    ) -> Result<Self, SynthesisError> {
        let ranks = unpack::<MAX_DEPTH, F>(&packed_ranks)?;
        let (populated, bounded) = prefix_mask::<MAX_DEPTH, F>(&depth)?;

        Ok(Self {
            packed_ranks,
            ranks,
            depth,
            count,
            populated,
            bounded,
        })
    }
}

impl<const MAX_DEPTH: usize, F: PrimeField> AllocVar<State<MAX_DEPTH>, F>
    for StateVar<MAX_DEPTH, F>
{
    fn new_variable<T: Borrow<State<MAX_DEPTH>>>(
        cs: impl Into<Namespace<F>>,
        f: impl FnOnce() -> Result<T, SynthesisError>,
        mode: AllocationMode,
    ) -> Result<Self, SynthesisError> {
        let ns = cs.into();
        let cs = ns.cs();

        let state = f()?;
        let state = state.borrow();
        const {
            assert!(
                F::MODULUS_BIT_SIZE as usize > RANK_BITS * MAX_DEPTH,
                "the ranks outgrow the field"
            )
        }
        let packed_ranks = F::from_le_bytes_mod_order(state.packed_ranks());
        let packed_ranks = FpVar::new_variable(cs.clone(), || Ok(packed_ranks), mode)?;
        let depth = FpVar::new_variable(cs.clone(), || Ok(F::from(state.depth() as u64)), mode)?;
        let count = FpVar::new_variable(cs, || Ok(F::from(state.count())), mode)?;

        Self::from_parts(packed_ranks, depth, count)
    }
}

impl<const MAX_DEPTH: usize, F: PrimeField> EqGadget<F> for StateVar<MAX_DEPTH, F> {
    #[tracing::instrument(target = "r1cs", skip(self, other))]
    fn is_eq(&self, other: &Self) -> Result<Boolean<F>, SynthesisError> {
        Ok(self.packed_ranks.is_eq(&other.packed_ranks)?
            & self.depth.is_eq(&other.depth)?
            & self.count.is_eq(&other.count)?)
    }
}

impl<const MAX_DEPTH: usize, F: PrimeField> GR1CSVar<F> for StateVar<MAX_DEPTH, F> {
    type Value = State<MAX_DEPTH>;

    fn cs(&self) -> ConstraintSystemRef<F> {
        self.packed_ranks.cs()
    }

    fn value(&self) -> Result<Self::Value, SynthesisError> {
        let packed_ranks = self.packed_ranks.value()?.into_bigint().to_bytes_le();
        let packed_ranks = packed_ranks.try_into().ok();
        let depth = to_u64(self.depth.value()?).and_then(|depth| u8::try_from(depth).ok());
        let count = to_u64(self.count.value()?);

        let (Some(packed_ranks), Some(depth), Some(count)) = (packed_ranks, depth, count) else {
            return Err(SynthesisError::Unsatisfiable);
        };
        State::try_from_parts(packed_ranks, depth, count).ok_or(SynthesisError::Unsatisfiable)
    }
}

/// Reads a field element as a `u64`, or `None` when it is too large.
fn to_u64<F: PrimeField>(value: F) -> Option<u64> {
    let bigint = value.into_bigint();
    let (low, high) = bigint.as_ref().split_first()?;
    high.iter().all(|limb| *limb == 0).then_some(*low)
}

/// Reads the `rank`s from a word packed by [`State`].
#[tracing::instrument(target = "r1cs", skip_all)]
fn unpack<const MAX_DEPTH: usize, F: PrimeField>(
    packed_ranks: &FpVar<F>,
) -> Result<[FpVar<F>; MAX_DEPTH], SynthesisError> {
    let (bits, _) = packed_ranks.to_bits_le_with_top_bits_zero(RANK_BITS * MAX_DEPTH)?;

    try_from_fn(|i| Boolean::le_bits_to_fp(&bits[RANK_BITS * i..RANK_BITS * (i + 1)]))
}

#[cfg(test)]
mod tests {
    use ark_bn254::Fr;
    use ark_ff::Field;
    use ark_r1cs_std::GR1CSVar;
    use ark_relations::gr1cs::{ConstraintSystem, ConstraintSystemRef};

    use super::super::testing::{MAX_DEPTH, Mmr};
    use super::*;
    use crate::constraints::mask::one_hot;
    use crate::testing::filled;

    #[test]
    fn reads_back_the_frontier_it_packed() {
        let mmr: Mmr = filled(60);
        let cs = ConstraintSystem::<Fr>::new_ref();
        let state = witness(&cs, &mmr);

        assert_eq!(state.depth().value().unwrap(), Fr::from(mmr.depth() as u64));
        assert_eq!(state.count().value().unwrap(), Fr::from(mmr.len() as u64));
        for tree in 0..mmr.depth() {
            let (rank, live) = rank(&state, &FpVar::constant(Fr::from(tree as u64)));
            let packed = mmr.state().rank(tree).expect("a live tree");
            assert!(live.value().unwrap(), "tree {tree} is live");
            assert_eq!(rank.value().unwrap(), Fr::from(packed), "rank {tree}");
        }
        assert!(cs.is_satisfied().unwrap());
    }

    #[test]
    fn reads_an_empty_frontier() {
        let mmr: Mmr = filled(0);
        let cs = ConstraintSystem::<Fr>::new_ref();
        let state = witness(&cs, &mmr);

        let (_, live) = rank(&state, &FpVar::zero());

        assert_eq!(state.depth().value().unwrap(), Fr::from(0u64));
        assert_eq!(state.count().value().unwrap(), Fr::from(0u64));
        assert!(!live.value().unwrap());
        assert!(cs.is_satisfied().unwrap());
    }

    #[test]
    fn rejects_a_tree_at_or_above_the_depth() {
        let mmr: Mmr = filled(60);
        let cs = ConstraintSystem::<Fr>::new_ref();
        let state = witness(&cs, &mmr);

        let tree = FpVar::constant(Fr::from(mmr.depth() as u64));
        let (_, live) = rank(&state, &tree);

        assert!(!live.value().unwrap());
        assert!(cs.is_satisfied().unwrap());
    }

    #[test]
    fn rejects_a_depth_above_the_maximum() {
        let mmr: Mmr = filled(60);
        let cs = ConstraintSystem::<Fr>::new_ref();
        let state = witness(&cs, &mmr);
        let depth = FpVar::new_witness(cs.clone(), || Ok(Fr::from(MAX_DEPTH as u64 + 1))).unwrap();
        let state = StateVar::from_parts(state.packed_ranks, depth, state.count).unwrap();

        for tree in 0..MAX_DEPTH {
            let (_, live) = rank(&state, &FpVar::constant(Fr::from(tree as u64)));
            assert!(!live.value().unwrap(), "tree {tree} is not live");
        }
        assert!(cs.is_satisfied().unwrap());
    }

    #[test]
    fn rejects_a_word_above_the_layout() {
        let cs = ConstraintSystem::<Fr>::new_ref();
        let word = Fr::from(2u64).pow([(RANK_BITS * MAX_DEPTH) as u64]);
        let word = FpVar::new_input(cs.clone(), || Ok(word)).unwrap();

        let _ = unpack::<MAX_DEPTH, Fr>(&word).unwrap();

        assert!(!cs.is_satisfied().unwrap());
    }

    fn witness(cs: &ConstraintSystemRef<Fr>, mmr: &Mmr) -> StateVar<MAX_DEPTH, Fr> {
        StateVar::new_witness(cs.clone(), || Ok(mmr.state())).unwrap()
    }

    fn rank(state: &StateVar<MAX_DEPTH, Fr>, tree: &FpVar<Fr>) -> (FpVar<Fr>, Boolean<Fr>) {
        state.rank(&one_hot(tree).unwrap()).unwrap()
    }
}
