use std::cell::Cell;

use skew_mmr::hasher::{Hasher, StdHasher};

/// Delegates to [`StdHasher`] and counts the calls. The count is per-thread.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CountingHasher;

thread_local! {
    static HASHES: Cell<usize> = const { Cell::new(0) };
}

impl Hasher<u64> for CountingHasher {
    fn hash(element: &u64, left: &u64, right: &u64) -> u64 {
        HASHES.with(|count| count.set(count.get() + 1));
        StdHasher::hash(element, left, right)
    }
}

impl CountingHasher {
    pub fn count() -> usize {
        HASHES.with(Cell::get)
    }
}
