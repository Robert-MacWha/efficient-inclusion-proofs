//! The single place the hash function is defined.
//!
//! A real deployment would use an algebraic hash (Poseidon) over a field element type.
//! Nothing else in this crate depends on the choice, so swapping it is a local edit.

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash as _, Hasher as _};

pub type Hash = u64;

/// Starting value of every chain.
pub const IV: Hash = 0;

/// Compress an accumulator and the next element into the next accumulator.
pub fn hash(acc: Hash, element: Hash) -> Hash {
    let mut h = DefaultHasher::new();
    acc.hash(&mut h);
    element.hash(&mut h);
    h.finish()
}
