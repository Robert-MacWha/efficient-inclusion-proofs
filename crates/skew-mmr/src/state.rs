/// The frontier of a [`crate::SkewMmr`].
///
/// Matches the storage of `LibSkewMmr.sol`.
#[derive(Debug, Copy, Clone, Default, PartialEq, Eq)]
pub struct State<const MAX_DEPTH: usize> {
    /// Little-endian word holding the `rank` of tree `i` at bits `6i..6i+6`.
    packed_ranks: [u8; 32],
    depth: u8,
    count: u64,
}

/// The number of ranks `packed_ranks` holds, and the ceiling on `MAX_DEPTH` that follows from it.
pub const MAX_TREES: usize = 42;

pub const RANK_BITS: usize = 6;

impl<const MAX_DEPTH: usize> State<MAX_DEPTH> {
    /// Packs the `rank`s of a frontier, which are `Some` below its depth, alongside its count.
    pub fn new(ranks: &[Option<u32>; MAX_DEPTH], count: u64) -> Self {
        const { assert!(MAX_DEPTH <= MAX_TREES, "the ranks outgrow the rank word") }

        let mut packed_ranks = [0u8; 32];
        let mut depth = 0;
        for (tree, rank) in ranks.iter().map_while(|rank| *rank).enumerate() {
            let bit = RANK_BITS * tree;
            let spread = (rank as u16) << (bit % 8);
            packed_ranks[bit / 8] |= spread as u8;
            packed_ranks[bit / 8 + 1] |= (spread >> 8) as u8;
            depth += 1;
        }

        Self {
            packed_ranks,
            depth,
            count,
        }
    }

    /// Reads a frontier from its storage words, or `None` when it is invalid.
    pub fn try_from_parts(packed_ranks: [u8; 32], depth: u8, count: u64) -> Option<Self> {
        if depth as usize > MAX_DEPTH {
            return None;
        }
        if (RANK_BITS * MAX_DEPTH..256).any(|bit| packed_ranks[bit / 8] >> (bit % 8) & 1 == 1) {
            return None;
        }

        Some(Self {
            packed_ranks,
            depth,
            count,
        })
    }

    /// The number of live trees, which is never above `MAX_DEPTH`.
    pub fn depth(&self) -> usize {
        self.depth as usize
    }

    /// The rank of `tree`, or `None` when it sits at or above [`Self::depth`].
    pub fn rank(&self, tree: usize) -> Option<u32> {
        if tree >= self.depth() {
            return None;
        }

        let bit = RANK_BITS * tree;
        let low = self.packed_ranks[bit / 8] as u16;
        let high = self.packed_ranks[bit / 8 + 1] as u16;
        let spread = (high << 8 | low) >> (bit % 8);
        Some((spread & ((1 << RANK_BITS) - 1)) as u32)
    }

    /// The number of elements held by the accumulator.
    pub fn count(&self) -> u64 {
        self.count
    }

    pub fn packed_ranks(&self) -> &[u8; 32] {
        &self.packed_ranks
    }
}

#[cfg(test)]
mod tests {
    use std::array::from_fn;

    use super::*;

    const MAX_DEPTH: usize = 8;

    #[test]
    fn reads_back_the_frontier_it_packed() {
        let ranks = from_fn(|i| Some(i as u32));
        let state = State::<MAX_DEPTH>::new(&ranks, 40);

        assert_eq!(state.depth(), 8);
        assert_eq!(state.count(), 40);
        for (tree, rank) in ranks.iter().enumerate() {
            assert_eq!(state.rank(tree), *rank, "rank {tree}");
        }
    }

    #[test]
    fn reads_an_empty_frontier() {
        let state = State::<MAX_DEPTH>::new(&from_fn(|_| None), 0);

        assert_eq!(state.depth(), 0);
        assert_eq!(state.count(), 0);
        assert_eq!(state.rank(0), None);
    }

    #[test]
    fn rejects_a_tree_at_or_above_the_depth() {
        let ranks = from_fn(|i| (i < 3).then_some(0));
        let state = State::<MAX_DEPTH>::new(&ranks, 3);

        assert_eq!(state.rank(state.depth()), None);
    }

    #[test]
    fn rejects_a_depth_above_the_maximum() {
        let state = State::<MAX_DEPTH>::try_from_parts([0; 32], MAX_DEPTH as u8 + 1, 0);

        assert_eq!(state, None);
    }

    #[test]
    fn rejects_a_word_above_the_layout() {
        let bit = RANK_BITS * MAX_DEPTH;
        let mut packed_ranks = [0u8; 32];
        packed_ranks[bit / 8] = 1 << (bit % 8);

        assert_eq!(State::<MAX_DEPTH>::try_from_parts(packed_ranks, 0, 0), None);
    }
}
