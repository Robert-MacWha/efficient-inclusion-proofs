//! The single place the hash function is defined.
//!
//! A real deployment would use an algebraic hash (Poseidon, arity 3) over a field element type.
//! Nothing else in this crate depends on the choice, so swapping it is a local edit.

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash as _, Hasher as _};

pub type Hash = u64;

/// Stands in for the children of a leaf, so leaves and internal nodes share one arity.
pub const EMPTY: Hash = 0;

/// Commit to a node: the element it holds and the roots of its two subtrees.
pub fn node(element: Hash, left: Hash, right: Hash) -> Hash {
    let mut h = DefaultHasher::new();
    element.hash(&mut h);
    left.hash(&mut h);
    right.hash(&mut h);
    h.finish()
}
