//! Recursive hash-chain accumulator.
//!
//! An append-only set of commitments that can produce inclusion proofs. Each of
//! `DEPTH` levels keeps a running hash chain over its children updated every
//! `BATCH` elements.

pub mod hash;

use hash::{Hash, IV, hash};

/// A recursive hash-chain accumulator.
pub struct HashChainAccumulator<const BATCH: usize, const DEPTH: usize> {
    /// `accs[l]` is the open (not yet closed) chain at level `l`. This, plus a leaf counter, is
    /// the whole on-chain state.
    accs: [Hash; DEPTH],
    /// Every element ever pushed into each level: leaves at level 0, closed accumulators above.
    /// Prover-side history only; a contract does not keep this.
    levels: [Vec<Hash>; DEPTH],
}

/// One level's contribution to a proof: the full batch containing the value being proven.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Segment {
    /// Position of the proven value within `elements`.
    pub offset: usize,
    pub elements: Vec<Hash>,
}

/// Segments from the leaf's level upwards, stopping at the first still-open batch. A segment's
/// level is its index, so a proof's length is the level it terminates at.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Proof {
    pub segments: Vec<Segment>,
}

impl<const BATCH: usize, const DEPTH: usize> HashChainAccumulator<BATCH, DEPTH> {
    pub const CAPACITY: usize = BATCH.pow(DEPTH as u32);

    pub fn new() -> Self {
        Self {
            accs: [IV; DEPTH],
            levels: std::array::from_fn(|_| Vec::new()),
        }
    }

    /// Append a leaf. Returns the number of hashes performed.
    pub fn append(&mut self, leaf: Hash) -> usize {
        assert!(self.len() < Self::CAPACITY, "accumulator is full");

        let mut carry = leaf;
        let mut hashes = 0;
        for level in 0..DEPTH {
            self.accs[level] = hash(self.accs[level], carry);
            self.levels[level].push(carry);
            hashes += 1;

            // The top level is never closed, so its chain is the root; CAPACITY keeps it in
            // bounds. Below the top, a full batch closes and carries into the next level.
            if level == DEPTH - 1 || !self.levels[level].len().is_multiple_of(BATCH) {
                break;
            }

            carry = self.accs[level];
            self.accs[level] = IV;
        }
        hashes
    }

    /// Build an inclusion proof for the leaf at `index`.
    pub fn prove(&self, index: usize) -> Proof {
        assert!(index < self.len(), "index out of range");

        let mut segments = Vec::new();
        let mut level = 0;
        let mut index = index;
        loop {
            let start = (index / BATCH) * BATCH;
            let end = (start + BATCH).min(self.levels[level].len());
            segments.push(Segment {
                offset: index - start,
                elements: self.levels[level][start..end].to_vec(),
            });

            let closed = end == start + BATCH && level < DEPTH - 1;
            if !closed {
                return Proof { segments };
            }
            index = start / BATCH;
            level += 1;
        }
    }

    pub fn len(&self) -> usize {
        self.levels[0].len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn accumulators(&self) -> &[Hash; DEPTH] {
        &self.accs
    }
}

impl<const BATCH: usize, const DEPTH: usize> Default for HashChainAccumulator<BATCH, DEPTH> {
    fn default() -> Self {
        Self::new()
    }
}

/// Check that `leaf` is in the set committed to by `accumulators`.
///
/// A `k`-segment proof anchors at `accumulators[k - 1]`, so its length fixes the level it
/// terminates at. `chain(last) == accumulators[k - 1]` then forces the last segment to be the
/// genuine open batch at that level, whose elements are genuine level-`k-1` elements; that
/// forces the segment below it, and so on down to level 0, whose elements are leaves. Passing a
/// segment off as belonging to another level therefore requires a hash collision, and no
/// per-level domain separation is needed.
pub fn verify<const BATCH: usize, const DEPTH: usize>(
    proof: &Proof,
    leaf: Hash,
    accumulators: &[Hash; DEPTH],
) -> bool {
    if proof.segments.is_empty() || proof.segments.len() > DEPTH {
        return false;
    }

    let last = proof.segments.len() - 1;
    let mut expected = leaf;
    for (i, segment) in proof.segments.iter().enumerate() {
        if segment.elements.get(segment.offset) != Some(&expected) {
            return false;
        }
        // Only the terminal, still-open batch may be short.
        let length_ok = match i == last {
            true => segment.elements.len() <= BATCH,
            false => segment.elements.len() == BATCH,
        };
        if !length_ok {
            return false;
        }
        expected = chain(&segment.elements);
    }
    expected == accumulators[last]
}

fn chain(elements: &[Hash]) -> Hash {
    elements.iter().fold(IV, |acc, &e| hash(acc, e))
}

#[cfg(test)]
mod tests {
    use super::*;

    type Acc = HashChainAccumulator<4, 3>;

    fn leaf(i: usize) -> Hash {
        1_000_000 + i as Hash
    }

    fn filled(leaves: usize) -> Acc {
        let mut acc = Acc::new();
        for i in 0..leaves {
            acc.append(leaf(i));
        }
        acc
    }

    /// Every leaf proves at every intermediate size, which covers partially filled batches at
    /// every level.
    #[test]
    fn round_trip() {
        let mut acc = Acc::new();
        for i in 0..Acc::CAPACITY {
            acc.append(leaf(i));
            for j in 0..=i {
                let proof = acc.prove(j);
                assert!(
                    verify::<4, 3>(&proof, leaf(j), acc.accumulators()),
                    "leaf {j} failed at len {}",
                    i + 1
                );
            }
        }
    }

    #[test]
    fn rejects_non_members() {
        let acc = filled(20);
        let proof = acc.prove(7);

        assert!(!verify::<4, 3>(&proof, leaf(8), acc.accumulators()));
        assert!(!verify::<4, 3>(&proof, 0, acc.accumulators()));

        let stale = acc.accumulators().map(|a| a.wrapping_add(1));
        assert!(!verify::<4, 3>(&proof, leaf(7), &stale));
    }

    /// Dropping the leaf's own segment, to claim a closed level-0 accumulator is itself a leaf,
    /// shortens the proof and so anchors it one accumulator too low.
    #[test]
    fn rejects_level_shifted_proof() {
        let acc = filled(20);
        let proof = acc.prove(7);
        assert_eq!(proof.segments.len(), 3);

        let victim = proof.segments[1].elements[proof.segments[1].offset];
        let forged = Proof {
            segments: proof.segments[1..].to_vec(),
        };
        assert!(!verify::<4, 3>(&forged, victim, acc.accumulators()));
    }

    #[test]
    fn rejects_malformed_segments() {
        let acc = filled(20);
        let proof = acc.prove(7);
        assert!(verify::<4, 3>(&proof, leaf(7), acc.accumulators()));

        // A closed (full) batch presented as the terminal segment.
        let truncated = Proof {
            segments: proof.segments[..1].to_vec(),
        };
        assert!(!verify::<4, 3>(&truncated, leaf(7), acc.accumulators()));

        // A prefix of a batch, dropping the elements after the leaf.
        let mut short = proof.clone();
        short.segments[0].elements.truncate(4 - 1);
        assert!(!verify::<4, 3>(&short, leaf(7), acc.accumulators()));
    }

    #[test]
    #[should_panic(expected = "accumulator is full")]
    fn rejects_overflow() {
        filled(Acc::CAPACITY + 1);
    }

    #[test]
    fn amortized_cost() {
        const BATCH: usize = 32;
        const DEPTH: usize = 3;
        type Big = HashChainAccumulator<BATCH, DEPTH>;

        let mut acc = Big::new();
        let mut hashes = 0;
        for i in 0..Big::CAPACITY {
            hashes += acc.append(leaf(i));
        }

        // One hash per element pushed into each level.
        let expected = Big::CAPACITY + Big::CAPACITY / BATCH + Big::CAPACITY / (BATCH * BATCH);
        assert_eq!(hashes, expected);

        let widest = (0..Big::CAPACITY)
            .map(|i| {
                acc.prove(i)
                    .segments
                    .iter()
                    .map(|s| s.elements.len())
                    .sum::<usize>()
            })
            .max()
            .unwrap();
        assert!(widest <= BATCH * DEPTH);

        println!(
            "BATCH={BATCH} DEPTH={DEPTH} capacity={} hashes/append={:.4} max proof hashes={widest}",
            Big::CAPACITY,
            hashes as f64 / Big::CAPACITY as f64,
        );
    }
}
