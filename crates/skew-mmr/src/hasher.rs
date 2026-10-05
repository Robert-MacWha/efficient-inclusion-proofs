use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash as _, Hasher as _};

#[cfg(feature = "r1cs")]
use ark_ff::PrimeField;
#[cfg(feature = "r1cs")]
use ark_r1cs_std::{GR1CSVar, fields::FieldVar, fields::fp::FpVar};
#[cfg(feature = "r1cs")]
use ark_relations::gr1cs::SynthesisError;

/// Hasher trait for hashing an element in a `SkewMmr`.
pub trait Hasher<E> {
    /// A collision-resistant hash function that hashes three elements.
    fn hash(element: &E, left: &E, right: &E) -> E;
}

/// The R1CS form of [`Hasher`], over a field element.
#[cfg(feature = "r1cs")]
pub trait HasherGadget<F: PrimeField> {
    fn hash(
        element: &FpVar<F>,
        left: &FpVar<F>,
        right: &FpVar<F>,
    ) -> Result<FpVar<F>, SynthesisError>;
}

/// Basic hasher for u64 elements, using the [`DefaultHasher`] impl.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StdHasher;

/// Stand-in with the arithmetic shape of an algebraic hash. Not collision resistant.
#[cfg(feature = "r1cs")]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MockHasher;

impl Hasher<u64> for StdHasher {
    fn hash(element: &u64, left: &u64, right: &u64) -> u64 {
        let mut state = DefaultHasher::new();
        element.hash(&mut state);
        left.hash(&mut state);
        right.hash(&mut state);
        state.finish()
    }
}

#[cfg(feature = "r1cs")]
impl<F: PrimeField> Hasher<F> for MockHasher {
    fn hash(element: &F, left: &F, right: &F) -> F {
        <Self as HasherGadget<F>>::hash(
            &FpVar::Constant(*element),
            &FpVar::Constant(*left),
            &FpVar::Constant(*right),
        )
        .and_then(|out| out.value())
        .expect("a constant hash cannot fail")
    }
}

#[cfg(feature = "r1cs")]
impl<F: PrimeField> HasherGadget<F> for MockHasher {
    fn hash(
        element: &FpVar<F>,
        left: &FpVar<F>,
        right: &FpVar<F>,
    ) -> Result<FpVar<F>, SynthesisError> {
        let sum = element + &(left * F::from(2u64)) + &(right * F::from(3u64));
        sum.pow_by_constant([5u64])
    }
}
