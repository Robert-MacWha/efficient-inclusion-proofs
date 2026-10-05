#[cfg(test)]
use ark_bn254::Fr;
use ark_ff::PrimeField;
use ark_r1cs_std::fields::fp::FpVar;
#[cfg(test)]
use ark_r1cs_std::{GR1CSVar, fields::FieldVar};
use ark_relations::gr1cs::SynthesisError;

#[cfg(test)]
use crate::hasher::{Hasher, MockHasher};

/// Rounds of [`MockHasher`]'s permutation.
#[cfg(test)]
const ROUNDS: usize = 3;

/// The R1CS form of [`crate::hasher::Hasher`], over a field element.
pub trait HasherGadget<F: PrimeField> {
    fn hash(
        element: &FpVar<F>,
        left: &FpVar<F>,
        right: &FpVar<F>,
    ) -> Result<FpVar<F>, SynthesisError>;
}

#[cfg(test)]
impl Hasher<Fr> for MockHasher {
    fn hash(element: &Fr, left: &Fr, right: &Fr) -> Fr {
        <Self as HasherGadget<Fr>>::hash(
            &FpVar::Constant(*element),
            &FpVar::Constant(*left),
            &FpVar::Constant(*right),
        )
        .and_then(|out| out.value())
        .expect("a constant hash cannot fail")
    }
}

#[cfg(test)]
impl<F: PrimeField> HasherGadget<F> for MockHasher {
    fn hash(
        element: &FpVar<F>,
        left: &FpVar<F>,
        right: &FpVar<F>,
    ) -> Result<FpVar<F>, SynthesisError> {
        let mut state = [element.clone(), left.clone(), right.clone()];
        for round in 0..ROUNDS {
            for (lane, cell) in state.iter_mut().enumerate() {
                let constant = F::from((3 * round + lane + 1) as u64);
                *cell = (&*cell + constant).pow_by_constant([5u64])?;
            }
            state = mix(state);
        }

        Ok(state[0].clone())
    }
}

/// A circulant mix, so that every lane reaches every other.
#[cfg(test)]
fn mix<F: PrimeField>(state: [FpVar<F>; 3]) -> [FpVar<F>; 3] {
    let [a, b, c] = state;
    [
        &a * F::from(2u64) + &b * F::from(3u64) + &c,
        &a + &b * F::from(2u64) + &c * F::from(3u64),
        &a * F::from(3u64) + &b + &c * F::from(2u64),
    ]
}
