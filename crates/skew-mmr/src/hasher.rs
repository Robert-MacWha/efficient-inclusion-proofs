use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash as _, Hasher as _};

use crate::element::Element;

/// Hasher trait for hashing an element in a `SkewMmr`.
pub trait Hasher<E: Element> {
    /// A collision-resistant hash function that hashes three elements.
    fn hash(element: &E, left: &E, right: &E) -> E;
}

/// Basic hasher for u64 elements, using the [`DefaultHasher`] impl.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StdHasher;

impl Hasher<u64> for StdHasher {
    fn hash(element: &u64, left: &u64, right: &u64) -> u64 {
        let mut state = DefaultHasher::new();
        element.hash(&mut state);
        left.hash(&mut state);
        right.hash(&mut state);
        state.finish()
    }
}
