use std::marker::PhantomData;

use crate::element::Element;
use crate::hasher::Hasher;

/// An inclusion proof for an element in a [`crate::SkewMmr`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Proof<E: Element, H: Hasher<E>> {
    /// The accumulator state this proof was built against.
    pub roots: Vec<E>,
    pub ranks: Vec<u32>,

    /// Index into `roots`.
    pub tree: usize,
    pub path: Vec<Step<E>>,
    pub(crate) hasher: PhantomData<H>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Step<E: Element> {
    pub element: E,
    /// The children of this node, if any. None if this is a leaf.
    pub children: Option<(E, E)>,
}

impl<E: Element, H: Hasher<E>> Proof<E, H> {
    /// Verifies that the proof is valid for the given `element`.
    pub fn verify(&self, element: &E) -> bool {
        let (Some(root), Some(&rank), Some(first)) = (
            self.roots.get(self.tree),
            self.ranks.get(self.tree),
            self.path.first(),
        ) else {
            return false;
        };
        if first.element != *element || self.path.len() > rank as usize + 1 {
            return false;
        }

        // A path of L `Step`s into a tree of rank r reaches a subtree of rank `r - L + 1`, so the
        // proven node is a leaf when `L == r + 1`.
        let proven_is_leaf = self.path.len() == rank as usize + 1;
        let mut current = match (&first.children, proven_is_leaf) {
            (None, true) => first.element.clone(),
            (Some((left, right)), false) => H::hash(&first.element, left, right),
            _ => return false,
        };

        for step in &self.path[1..] {
            let Some((left, right)) = &step.children else {
                return false;
            };
            if current != *left && current != *right {
                return false;
            }
            current = H::hash(&step.element, left, right);
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
            for j in 0..=i {
                let proof = mmr.prove(j as usize);
                assert!(proof.verify(&j), "element {j} at len {}", i + 1);
            }
        }
    }

    #[test]
    fn rejects_a_different_element() {
        let proof = sample(40);
        assert!(!proof.verify(&41), "another member");
        assert!(!proof.verify(&1000), "a non-member");
    }

    #[test]
    fn rejects_another_tree() {
        let proof = sample(40);
        let tree = (proof.tree + 1) % proof.roots.len();
        assert!(!SampleProof { tree, ..proof }.verify(&40));
    }

    #[test]
    fn rejects_a_tree_out_of_range() {
        let proof = sample(40);
        let tree = proof.roots.len();
        assert!(!SampleProof { tree, ..proof }.verify(&40));
    }

    #[test]
    fn rejects_a_tampered_step() {
        let mut proof = sample(40);
        proof.path.last_mut().unwrap().element ^= 1;
        assert!(!proof.verify(&40));
    }

    #[test]
    fn rejects_a_truncated_path() {
        let mut proof = sample(40);
        proof.path.pop();
        assert!(!proof.verify(&40));
    }

    #[test]
    fn rejects_roots_from_another_state() {
        let mut proof = sample(40);
        proof.roots = proof
            .roots
            .iter()
            .map(|root| root.wrapping_add(1))
            .collect();
        assert!(!proof.verify(&40));
    }

    #[test]
    fn rejects_a_step_without_children() {
        let mut proof = sample(40);
        proof.path.last_mut().unwrap().children = None;
        assert!(!proof.verify(&40));
    }

    #[test]
    fn rejects_an_internal_root_claimed_as_a_leaf() {
        let mmr = filled(100);
        let roots = mmr.roots();
        let ranks = mmr.ranks();
        let tree = ranks
            .iter()
            .position(|&rank| rank > 0)
            .expect("a tall tree");

        let forged = SampleProof {
            path: vec![Step {
                element: roots[tree],
                children: None,
            }],
            roots: roots.clone(),
            ranks,
            tree,
            hasher: PhantomData,
        };
        assert!(!forged.verify(&roots[tree]));
    }

    fn sample(element: u64) -> SampleProof {
        filled(100).prove(element as usize)
    }
}
