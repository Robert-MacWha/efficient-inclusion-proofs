use std::borrow::Borrow;

use ark_ff::{BigInteger, PrimeField};
use ark_r1cs_std::{
    alloc::{AllocVar, AllocationMode},
    boolean::Boolean,
    eq::EqGadget,
    fields::{FieldVar, fp::FpVar},
};
use ark_relations::gr1cs::{Namespace, SynthesisError};

use super::{prefix_mask, try_from_fn};
use crate::state::State;

/// The R1CS form of [`crate::state::State`].
#[derive(Debug, Clone)]
pub struct StateVar<const MAX_DEPTH: usize, F: PrimeField> {
    word: FpVar<F>,
    ranks: [FpVar<F>; MAX_DEPTH],
    depth: FpVar<F>,
}

impl<const MAX_DEPTH: usize, F: PrimeField> StateVar<MAX_DEPTH, F> {
    /// The packed word.
    #[tracing::instrument(target = "r1cs", skip_all)]
    pub fn word(&self) -> &FpVar<F> {
        &self.word
    }

    /// The number of live trees.
    #[tracing::instrument(target = "r1cs", skip_all)]
    pub fn depth(&self) -> &FpVar<F> {
        &self.depth
    }

    /// The rank of `tree`, enforcing that it sits below [`Self::depth`]. Where the native
    /// [`State::rank`] would return `None`, this leaves the system unsatisfiable.
    #[tracing::instrument(target = "r1cs", skip_all)]
    pub fn rank(&self, tree: &FpVar<F>) -> Result<FpVar<F>, SynthesisError> {
        // A tree at or above `depth` is padding, which reads as rank 0 and would match an
        // empty path.
        let populated = prefix_mask::<MAX_DEPTH, F>(&self.depth)?;
        let mut rank = FpVar::zero();
        let mut live = Boolean::FALSE;
        for (i, populated) in populated.iter().enumerate() {
            let hit = tree.is_eq(&FpVar::constant(F::from(i as u64)))?;
            rank = hit.select(&self.ranks[i], &rank)?;
            live |= &hit & populated;
        }
        live.enforce_equal(&Boolean::TRUE)?;

        Ok(rank)
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
        let word = to_field::<F>(state.borrow().bytes()).ok_or(SynthesisError::Unsatisfiable)?;
        let word = FpVar::new_variable(cs, || Ok(word), mode)?;
        let (ranks, depth) = unpack::<MAX_DEPTH, F>(&word)?;

        Ok(Self { word, ranks, depth })
    }
}

/// Reads a packed word as a field element, or `None` when `F` is too small to hold it.
fn to_field<F: PrimeField>(bytes: &[u8; 32]) -> Option<F> {
    let field = F::from_le_bytes_mod_order(bytes);
    let reduced = field.into_bigint().to_bytes_le();

    let byte = |slice: &[u8], i: usize| slice.get(i).copied().unwrap_or(0);
    let fits =
        (0..reduced.len().max(bytes.len())).all(|i| byte(&reduced, i) == byte(bytes.as_slice(), i));

    fits.then_some(field)
}

/// Reads the `rank`s and `depth` from a word packed by [`State`].
#[tracing::instrument(target = "r1cs", skip_all)]
fn unpack<const MAX_DEPTH: usize, F: PrimeField>(
    word: &FpVar<F>,
) -> Result<([FpVar<F>; MAX_DEPTH], FpVar<F>), SynthesisError> {
    let (bits, _) = word.to_bits_le_with_top_bits_zero(8 * (MAX_DEPTH + 5) + 1)?;
    let byte = |i: usize| Boolean::le_bits_to_fp(&bits[8 * i..8 * (i + 1)]);

    Ok((try_from_fn(&byte)?, byte(MAX_DEPTH)?))
}

#[cfg(test)]
mod tests {
    use ark_bn254::Fr;
    use ark_r1cs_std::GR1CSVar;
    use ark_relations::gr1cs::{ConstraintSystem, ConstraintSystemRef};

    use super::super::testing::{MAX_DEPTH, Mmr};
    use super::*;
    use crate::testing::filled;

    #[test]
    fn reads_back_the_frontier_it_packed() {
        let mmr: Mmr = filled(60);
        let cs = ConstraintSystem::<Fr>::new_ref();
        let state = witness(&cs, &mmr);

        assert_eq!(state.depth().value().unwrap(), Fr::from(mmr.depth() as u64));
        for tree in 0..mmr.depth() {
            let rank = state.rank(&FpVar::constant(Fr::from(tree as u64))).unwrap();
            let packed = mmr.state().rank(tree).expect("a live tree");
            assert_eq!(rank.value().unwrap(), Fr::from(packed), "rank {tree}");
        }
        assert!(cs.is_satisfied().unwrap());
    }

    #[test]
    fn rejects_a_tree_at_or_above_the_depth() {
        let mmr: Mmr = filled(60);
        let cs = ConstraintSystem::<Fr>::new_ref();
        let state = witness(&cs, &mmr);

        let tree = FpVar::constant(Fr::from(mmr.depth() as u64));
        let _ = state.rank(&tree).unwrap();

        assert!(!cs.is_satisfied().unwrap());
    }

    #[test]
    fn rejects_a_word_above_the_layout() {
        let cs = ConstraintSystem::<Fr>::new_ref();
        let mut bytes = [0u8; 32];
        bytes[MAX_DEPTH + 5] = 2;
        let word =
            FpVar::new_input(cs.clone(), || Ok(Fr::from_le_bytes_mod_order(&bytes))).unwrap();

        let _ = unpack::<MAX_DEPTH, Fr>(&word).unwrap();

        assert!(!cs.is_satisfied().unwrap());
    }

    #[test]
    fn reads_a_word_that_fits_the_field() {
        let mmr: Mmr = filled(60);
        let word = to_field::<Fr>(mmr.state().bytes());

        assert_eq!(word, Some(Fr::from_le_bytes_mod_order(mmr.state().bytes())));
    }

    #[test]
    fn rejects_a_word_that_outgrows_the_field() {
        assert_eq!(to_field::<Fr>(&[0xff; 32]), None);
    }

    fn witness(cs: &ConstraintSystemRef<Fr>, mmr: &Mmr) -> StateVar<MAX_DEPTH, Fr> {
        StateVar::new_witness(cs.clone(), || Ok(mmr.state())).unwrap()
    }
}
