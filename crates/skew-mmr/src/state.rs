/// The frontier of a [`crate::SkewMmr`], packed little-endian into the `state` word of
/// `SkewMmr.sol`:
///  - `0..26`   - `rank`s
///  - `26`      - `depth`
///  - `27..31`  - `count`
///  - `31`      - a sentinel, so that a live accumulator is never zero
#[derive(Debug, Copy, Clone, Default, PartialEq, Eq)]
pub struct State<const MAX_DEPTH: usize>([u8; 32]);

/// The byte that holds `depth`, and the ceiling on `MAX_DEPTH` that follows from it.
pub const DEPTH_BYTE: usize = 26;

impl<const MAX_DEPTH: usize> State<MAX_DEPTH> {
    /// Packs the `rank`s of a frontier, which are `Some` below its depth, alongside its count.
    pub fn new(ranks: &[Option<u32>; MAX_DEPTH], count: u32) -> Self {
        const { assert!(MAX_DEPTH <= DEPTH_BYTE, "the ranks outgrow the state word") }

        let mut state = [0u8; 32];
        let mut depth = 0;
        for (slot, rank) in state.iter_mut().zip(ranks.iter().map_while(|rank| *rank)) {
            *slot = rank as u8;
            depth += 1;
        }

        state[DEPTH_BYTE] = depth as u8;
        state[DEPTH_BYTE + 1..DEPTH_BYTE + 5].copy_from_slice(&count.to_le_bytes());
        state[DEPTH_BYTE + 5] = 1;
        Self(state)
    }

    /// The number of live trees, which is never above `MAX_DEPTH`.
    pub fn depth(&self) -> usize {
        self.0[DEPTH_BYTE] as usize
    }

    /// The rank of `tree`, or `None` when it sits at or above [`Self::depth`].
    pub fn rank(&self, tree: usize) -> Option<u32> {
        (tree < self.depth()).then(|| self.0[tree] as u32)
    }

    /// The number of elements held by the accumulator.
    pub fn count(&self) -> u32 {
        let count = self.0[DEPTH_BYTE + 1..DEPTH_BYTE + 5]
            .try_into()
            .expect("four bytes");
        u32::from_le_bytes(count)
    }

    pub fn bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

#[cfg(test)]
mod tests {
    use std::array::from_fn;

    use super::*;

    const MAX_DEPTH: usize = 8;

    #[test]
    fn reads_back_the_frontier_it_packed() {
        let ranks = from_fn(|i| (i < 3).then(|| 5 - i as u32));
        let state = State::<MAX_DEPTH>::new(&ranks, 40);

        assert_eq!(state.depth(), 3);
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
    fn is_never_zero_while_live() {
        let state = State::<MAX_DEPTH>::new(&from_fn(|_| None), 0);

        assert_ne!(state.bytes(), &[0u8; 32]);
    }
}
