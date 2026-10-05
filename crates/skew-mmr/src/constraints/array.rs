use ark_relations::gr1cs::SynthesisError;

/// Builds an array from one fallible item per index.
pub fn try_from_fn<T, const N: usize>(
    f: impl FnMut(usize) -> Result<T, SynthesisError>,
) -> Result<[T; N], SynthesisError> {
    let items = (0..N).map(f).collect::<Result<Vec<_>, _>>()?;
    Ok(items.try_into().ok().expect("N items"))
}
