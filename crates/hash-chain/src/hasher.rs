use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash as _, Hasher as _};

/// Hasher trait for folding elements into a chain in a `HashChain`.
pub trait Hasher<E> {
    /// The initial value of the hash chain.
    fn iv() -> E;

    /// A collision-resistant hash function that folds an element into a chain.
    fn hash(chain: &E, element: &E) -> E;
}

/// Basic hasher for u64 elements, using the [`DefaultHasher`] impl.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StdHasher;

impl Hasher<u64> for StdHasher {
    fn iv() -> u64 {
        0
    }

    fn hash(chain: &u64, element: &u64) -> u64 {
        let mut state = DefaultHasher::new();
        chain.hash(&mut state);
        element.hash(&mut state);
        state.finish()
    }
}
