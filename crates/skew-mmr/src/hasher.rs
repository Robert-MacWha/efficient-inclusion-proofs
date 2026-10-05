#[cfg(test)]
use std::collections::hash_map::DefaultHasher;
#[cfg(test)]
use std::hash::{Hash as _, Hasher as _};

/// Hasher trait for hashing an element in a `SkewMmr`.
pub trait Hasher<E> {
    /// A collision-resistant hash function that hashes three elements.
    fn hash(element: &E, left: &E, right: &E) -> E;
}

/// Mock hasher impl for testing.
#[cfg(test)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MockHasher;

#[cfg(test)]
impl Hasher<u64> for MockHasher {
    fn hash(element: &u64, left: &u64, right: &u64) -> u64 {
        let mut state = DefaultHasher::new();
        element.hash(&mut state);
        left.hash(&mut state);
        right.hash(&mut state);
        state.finish()
    }
}
