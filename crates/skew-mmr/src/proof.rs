use std::marker::PhantomData;

use crate::element::Element;
use crate::hasher::Hasher;

/// An inclusion proof for an element in a [`crate::SkewMmr`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Proof<E: Element, H: Hasher<E>> {
    /// Index into `roots` and `ranks`.
    pub tree: usize,
    /// The children of the proven node. None if it is a leaf.
    pub children: Option<(E, E)>,
    /// Ancestors of the proven node, closest first.
    pub path: Vec<Step<E>>,
    pub(crate) hasher: PhantomData<H>,
}

/// One ancestor of the proven node.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Step<E: Element> {
    pub element: E,
    /// The child that the path does not descend into.
    pub sibling: E,
    /// Whether the path descends into the right child.
    pub right: bool,
}

impl<E: Element, H: Hasher<E>> Proof<E, H> {
    /// Verifies that `element` is held by the accumulator described by `roots` and `ranks`.
    pub fn verify(&self, roots: &[E], ranks: &[u32], element: &E) -> bool {
        let (Some(root), Some(&rank)) = (roots.get(self.tree), ranks.get(self.tree)) else {
            return false;
        };
        if self.path.len() > rank as usize {
            return false;
        }

        // One step per level between the proven node and the tree root, so a node reached by
        // `L` steps in a tree of rank `r` has rank `r - L`, and is a leaf exactly when `L == r`.
        let mut current = match (&self.children, self.path.len() == rank as usize) {
            (None, true) => element.clone(),
            (Some((left, right)), false) => H::hash(element, left, right),
            _ => return false,
        };

        for step in &self.path {
            current = match step.right {
                true => H::hash(&step.element, &step.sibling, &current),
                false => H::hash(&step.element, &current, &step.sibling),
            };
        }
        current == *root
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hasher::StdHasher;
    use crate::testing::{Mmr, filled};

    type SampleProof = Proof<u64, StdHasher>;

    #[test]
    fn proves_every_element_at_every_size() {
        let mut mmr = Mmr::new();
        for i in 0..200 {
            mmr.append(i);

            let (roots, ranks) = (mmr.roots(), mmr.ranks());
            for j in 0..=i {
                let proof = mmr.prove(j as usize);
                assert!(
                    proof.verify(&roots, &ranks, &j),
                    "element {j} at len {}",
                    i + 1
                );
            }
        }
    }

    #[test]
    fn rejects_a_different_element() {
        let (roots, ranks, proof) = sample(40);
        assert!(!proof.verify(&roots, &ranks, &41), "another member");
        assert!(!proof.verify(&roots, &ranks, &1000), "a non-member");
    }

    #[test]
    fn rejects_a_proof_from_another_accumulator() {
        let (roots, ranks, _) = sample(40);

        let mut other = Mmr::new();
        other.append(1000);
        let forged = other.prove(0);

        assert!(!forged.verify(&roots, &ranks, &1000));
    }

    #[test]
    fn rejects_a_tree_out_of_range() {
        let (roots, ranks, proof) = sample(40);
        let tree = roots.len();
        assert!(!SampleProof { tree, ..proof }.verify(&roots, &ranks, &40));
    }

    #[test]
    fn rejects_a_flipped_direction() {
        let (roots, ranks, mut proof) = sample(40);
        let step = proof.path.first_mut().unwrap();
        step.right = !step.right;
        assert!(!proof.verify(&roots, &ranks, &40));
    }

    #[test]
    fn rejects_a_tree_root_claimed_as_a_leaf() {
        let mmr = filled(100);
        let (roots, ranks) = (mmr.roots(), mmr.ranks());
        let tree = ranks
            .iter()
            .position(|&rank| rank > 0)
            .expect("a tall tree");

        let forged = SampleProof {
            tree,
            children: None,
            path: Vec::new(),
            hasher: PhantomData,
        };
        assert!(!forged.verify(&roots, &ranks, &roots[tree]));
    }

    fn sample(element: u64) -> (Vec<u64>, Vec<u32>, SampleProof) {
        let mmr = filled(100);
        (mmr.roots(), mmr.ranks(), mmr.prove(element as usize))
    }
}
