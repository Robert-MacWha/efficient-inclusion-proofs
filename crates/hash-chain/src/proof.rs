use std::marker::PhantomData;

use crate::hasher::Hasher;

/// An inclusion proof for an element in a [`crate::HashChain`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Proof<const BATCH: usize, E, H: Hasher<E>> {
    /// One per level, from level 0 up to the first batch that is still open.
    pub segments: Vec<Segment<E>>,
    pub hasher: PhantomData<H>,
}

/// One level's batch.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Segment<E> {
    /// Position of the proven value within `elements`.
    pub offset: usize,
    pub elements: Vec<E>,
}

impl<const BATCH: usize, E, H: Hasher<E>> Proof<BATCH, E, H> {
    pub fn new(segments: Vec<Segment<E>>) -> Self {
        Self {
            segments,
            hasher: PhantomData,
        }
    }
}

impl<const BATCH: usize, E: Clone + PartialEq, H: Hasher<E>> Proof<BATCH, E, H> {
    /// Verifies that `element` is held by the accumulator described by `accumulators`.
    pub fn verify(&self, accumulators: &[E], element: &E) -> bool {
        let Some((open, closed)) = self.segments.split_last() else {
            return false;
        };
        let Some(anchor) = accumulators.get(closed.len()) else {
            return false;
        };

        let mut expected = element.clone();
        for segment in closed {
            if !segment.holds(&expected) || segment.elements.len() != BATCH {
                return false;
            }
            expected = segment.chain::<H>();
        }

        // Only the terminating batch is still open, so only it may be short.
        if !open.holds(&expected) || open.elements.len() > BATCH {
            return false;
        }
        open.chain::<H>() == *anchor
    }
}

impl<E: Clone + PartialEq> Segment<E> {
    fn holds(&self, element: &E) -> bool {
        self.elements.get(self.offset) == Some(element)
    }

    fn chain<H: Hasher<E>>(&self) -> E {
        self.elements
            .iter()
            .fold(H::iv(), |chain, element| H::hash(&chain, element))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hasher::StdHasher;
    use crate::testing::{Chain, filled};

    type SampleProof = Proof<4, u64, StdHasher>;

    #[test]
    fn proves_every_element_at_every_size() {
        let mut chain = Chain::new();
        for i in 0..Chain::CAPACITY as u64 {
            chain.append(i);

            for j in 0..=i {
                let proof = chain.prove(j as usize);
                assert!(
                    proof.verify(chain.accumulators(), &j),
                    "element {j} at len {}",
                    i + 1
                );
            }
        }
    }

    #[test]
    fn rejects_another_member() {
        let (chain, proof) = sample(7);
        assert!(!proof.verify(chain.accumulators(), &8));
    }

    #[test]
    fn rejects_an_empty_proof() {
        let (chain, _) = sample(7);
        assert!(!SampleProof::new(Vec::new()).verify(chain.accumulators(), &7));
    }

    #[test]
    fn rejects_a_proof_deeper_than_the_chain() {
        let (chain, proof) = sample(7);
        let mut segments = proof.segments.clone();
        segments.push(proof.segments[0].clone());

        assert!(!SampleProof::new(segments).verify(chain.accumulators(), &7));
    }

    #[test]
    fn rejects_a_proof_from_another_accumulator() {
        let (chain, _) = sample(7);

        let mut other = Chain::new();
        other.append(1000);
        let forged = other.prove(0);

        assert!(!forged.verify(chain.accumulators(), &1000));
    }

    #[test]
    fn rejects_a_closed_batch_as_the_terminal_segment() {
        let (chain, proof) = sample(7);
        let segments = proof.segments[..1].to_vec();

        assert!(!SampleProof::new(segments).verify(chain.accumulators(), &7));
    }

    #[test]
    fn rejects_a_level_shifted_proof() {
        let (chain, proof) = sample(7);
        let above = &proof.segments[1];
        let element = above.elements[above.offset];

        let segments = proof.segments[1..].to_vec();
        assert!(!SampleProof::new(segments).verify(chain.accumulators(), &element));
    }

    #[test]
    fn rejects_a_truncated_segment() {
        let (chain, mut proof) = sample(7);
        proof.segments[0].elements.truncate(2);

        assert!(!proof.verify(chain.accumulators(), &7));
    }

    fn sample(element: u64) -> (Chain, SampleProof) {
        let chain = filled(20);
        let proof = chain.prove(element as usize);
        (chain, proof)
    }
}
