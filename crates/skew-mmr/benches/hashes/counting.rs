use std::cell::Cell;

use skew_mmr::hasher::Hasher;

/// Counts the calls per-thread made to this `Hasher`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CountingHasher;

thread_local! {
    static HASHES: Cell<usize> = const { Cell::new(0) };
}

impl Hasher<u64> for CountingHasher {
    fn hash(element: &u64, left: &u64, right: &u64) -> u64 {
        HASHES.with(|count| count.set(count.get() + 1));
        element.wrapping_mul(31).wrapping_add(left.rotate_left(17)) ^ right
    }
}

impl CountingHasher {
    pub fn count() -> usize {
        HASHES.with(Cell::get)
    }
}
