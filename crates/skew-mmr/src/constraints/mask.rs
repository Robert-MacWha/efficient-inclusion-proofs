use ark_ff::PrimeField;
use ark_r1cs_std::{
    boolean::Boolean,
    eq::EqGadget,
    fields::{FieldVar, fp::FpVar},
};
use ark_relations::gr1cs::SynthesisError;

use super::array::try_from_fn;

/// Expands `value` into the mask `i < value` over `0..N`, and whether it lands in
/// `0..=N`. The mask is meaningless when it does not.
pub fn prefix_mask<const N: usize, F: PrimeField>(
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
