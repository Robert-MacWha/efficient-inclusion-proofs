use ark_ff::PrimeField;
use ark_r1cs_std::{
    boolean::Boolean,
    eq::EqGadget,
    fields::{FieldVar, fp::FpVar},
};
use ark_relations::gr1cs::SynthesisError;

use super::array::try_from_fn;

/// Expands `value` into the mask `i < value` over `0..N`, enforcing that it lands in `0..=N`.
pub fn prefix_mask<const N: usize, F: PrimeField>(
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
