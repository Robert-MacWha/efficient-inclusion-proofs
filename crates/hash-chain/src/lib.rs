pub mod hasher;
pub mod proof;

use std::{array::from_fn, marker::PhantomData};

use hasher::Hasher;
use proof::{Proof, Segment};

/// An append-only set commitment structure.
///
/// A HashChain keeps a running hash chain per level. Level 0 folds in every appended element,
/// and each batch of `BATCH` elements closes and folds into the level above, giving an
/// amortised 1 hash per append.
#[derive(Debug, Clone)]
pub struct HashChain<const BATCH: usize, const DEPTH: usize, E: Clone, H: Hasher<E>> {
    /// The open chain at each level.
    chains: [E; DEPTH],
    /// Every element pushed into each level: appended elements at level 0, closed chains above.
    levels: [Vec<E>; DEPTH],
    hasher: PhantomData<H>,
}

impl<const BATCH: usize, const DEPTH: usize, E: Clone, H: Hasher<E>> HashChain<BATCH, DEPTH, E, H> {
    pub const CAPACITY: usize = BATCH.pow(DEPTH as u32);

    pub fn new() -> Self {
        Self {
            chains: from_fn(|_| H::iv()),
            levels: from_fn(|_| Vec::new()),
            hasher: PhantomData,
        }
    }

    /// Appends an element to the chain in an amortised O(1) hashes.
    pub fn append(&mut self, element: E) {
        assert!(self.len() < Self::CAPACITY, "chain is full");

        let mut carry = element;
        for level in 0..DEPTH {
            self.chains[level] = H::hash(&self.chains[level], &carry);
            self.levels[level].push(carry);

            if level == DEPTH - 1 || !self.levels[level].len().is_multiple_of(BATCH) {
                return;
            }
            carry = self.chains[level].clone();
            self.chains[level] = H::iv();
        }
    }

    /// Prove the element at `index`, counted in insertion order.
    pub fn prove(&self, mut index: usize) -> Proof<BATCH, E, H> {
        assert!(index < self.len(), "index out of range");

        let mut segments = Vec::new();
        for level in 0..DEPTH {
            let start = (index / BATCH) * BATCH;
            let end = (start + BATCH).min(self.levels[level].len());
            segments.push(Segment {
                offset: index - start,
                elements: self.levels[level][start..end].to_vec(),
            });

            let closed = end == start + BATCH;
            if !closed {
                break;
            }
            index = start / BATCH;
        }
        Proof::new(segments)
    }

    pub fn accumulators(&self) -> &[E; DEPTH] {
        &self.chains
    }

    pub fn len(&self) -> usize {
        self.levels[0].len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

impl<const BATCH: usize, const DEPTH: usize, E: Clone, H: Hasher<E>> Default
    for HashChain<BATCH, DEPTH, E, H>
{
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
pub mod testing {
    use super::HashChain;
    use crate::hasher::StdHasher;

    pub type Chain = HashChain<4, 3, u64, StdHasher>;

    pub fn filled(n: u64) -> Chain {
        let mut chain = Chain::new();
        for i in 0..n {
            chain.append(i);
        }
        chain
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use hasher::StdHasher;
    use testing::{Chain, filled};

    #[test]
    fn only_the_top_level_keeps_a_full_batch() {
        let chain = filled(Chain::CAPACITY as u64);
        let (top, closed) = chain.accumulators().split_last().expect("a level");

        assert!(closed.iter().all(|chain| *chain == StdHasher::iv()));
        assert_ne!(*top, StdHasher::iv());
    }

    #[test]
    #[should_panic(expected = "chain is full")]
    fn rejects_overflowing_capacity() {
        filled(Chain::CAPACITY as u64 + 1);
    }
}
