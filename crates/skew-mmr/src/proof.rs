use std::marker::PhantomData;

use crate::hasher::Hasher;
use crate::state::State;

/// An inclusion proof for an element in a [`crate::SkewMmr`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Proof<const MAX_DEPTH: usize, E, H: Hasher<E>> {
    /// Roots of the frontier's trees. Entries above `depth` are `None`.
    pub roots: [Option<E>; MAX_DEPTH],
    /// The frontier the proof is checked against.
    pub state: State<MAX_DEPTH>,
    /// The proven element.
    pub element: E,
    /// Index into `roots` and the rank bytes of `state`.
    pub tree: usize,
    /// The children of the proven node. Ignored when it is a leaf.
    pub children: Option<(E, E)>,
    /// Ancestors of the proven node held by `path`.
    pub path_len: usize,
    /// Ancestors of the proven node, closest first. Steps from `path_len` on are ignored.
    pub path: [Option<Step<E>>; MAX_DEPTH],
    pub hasher: PhantomData<H>,
}

/// One ancestor of the proven node.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Step<E> {
    pub element: E,
    /// The child that the path does not descend into.
    pub sibling: E,
    /// Whether the path descends into the right child.
    pub right: bool,
}

impl<const MAX_DEPTH: usize, E, H: Hasher<E>> Proof<MAX_DEPTH, E, H> {
    pub fn new(
        roots: [Option<E>; MAX_DEPTH],
        state: State<MAX_DEPTH>,
        element: E,
        tree: usize,
        children: Option<(E, E)>,
        path_len: usize,
        path: [Option<Step<E>>; MAX_DEPTH],
    ) -> Self {
        Self {
            roots,
            state,
            element,
            tree,
            children,
            path_len,
            path,
            hasher: PhantomData,
        }
    }
}

impl<const MAX_DEPTH: usize, E: Clone + Default + PartialEq, H: Hasher<E>> Proof<MAX_DEPTH, E, H> {
    /// Verifies that `element` is held by the accumulator described by `roots` and `state`.
    ///
    /// `roots` and `state` must come from the same frontier, and the caller must authenticate
    /// them against the accumulator before trusting a `true`. Mixing frontiers lets a tree
    /// root pass as a leaf.
    pub fn verify(&self) -> bool {
        let (Some(Some(root)), Some(rank)) =
            (self.roots.get(self.tree), self.state.rank(self.tree))
        else {
            return false;
        };
        let rank = rank as usize;
        let Some(path) = self.path.get(..self.path_len) else {
            return false;
        };
        if self.path_len > rank {
            return false;
        }

        // One step per level between the proven node and the tree root, so a node reached by
        // `L` steps in a tree of rank `r` has rank `r - L`, and is a leaf exactly when `L == r`.
        let (left, right) = self.children.clone().unwrap_or_default();
        let mut current = match self.path_len == rank {
            true => self.element.clone(),
            false => H::hash(&self.element, &left, &right),
        };

        for step in path {
            current = step.clone().unwrap_or_default().fold::<H>(current);
        }
        current == *root
    }
}

impl<E> Step<E> {
    fn fold<H: Hasher<E>>(&self, current: E) -> E {
        match self.right {
            true => H::hash(&self.element, &self.sibling, &current),
            false => H::hash(&self.element, &current, &self.sibling),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::array::from_fn;

    use super::*;
    use crate::hasher::MockHasher;
    use crate::testing::{MAX_DEPTH, Mmr, filled};

    type SampleProof = Proof<MAX_DEPTH, u64, MockHasher>;

    #[test]
    fn proves_every_element_at_every_size() {
        let mut mmr = Mmr::new();
        for i in 0..200 {
            mmr.append(i);

            for j in 0..=i {
                let proof = mmr.prove(j as usize);
                assert!(proof.verify(), "element {j} at len {}", i + 1);
            }
        }
    }

    #[test]
    fn rejects_another_member() {
        let (_, proof) = sample(40);
        assert!(
            !SampleProof {
                element: 41,
                ..proof
            }
            .verify()
        );
    }

    #[test]
    fn rejects_a_non_member() {
        let (_, proof) = sample(40);
        assert!(
            !SampleProof {
                element: 1000,
                ..proof
            }
            .verify()
        );
    }

    #[test]
    fn rejects_a_proof_from_another_accumulator() {
        let (mmr, _) = sample(40);

        let mut other = Mmr::new();
        other.append(1000);
        let forged = other.prove(0);

        assert!(
            !SampleProof {
                roots: mmr.roots(),
                state: mmr.state(),
                ..forged
            }
            .verify()
        );
    }

    #[test]
    fn rejects_a_tree_above_the_depth() {
        let (mmr, proof) = sample(40);
        let tree = mmr.depth();

        assert!(!SampleProof { tree, ..proof }.verify());
    }

    #[test]
    fn rejects_a_flipped_direction() {
        let (_, mut proof) = sample(40);
        let step = proof.path[0].as_mut().expect("a populated step");
        step.right = !step.right;

        assert!(!proof.verify());
    }

    #[test]
    fn rejects_a_tree_root_claimed_as_a_leaf() {
        let (mmr, tree) = tall_tree();
        let root = mmr.roots()[tree].expect("a live tree");

        let forged = SampleProof::new(mmr.roots(), mmr.state(), root, tree, None, 0, empty());
        assert!(!forged.verify());
    }

    #[test]
    fn rejects_a_leaf_claimed_as_a_tree_root() {
        let (mmr, tree) = tall_tree();

        let forged = SampleProof::new(mmr.roots(), mmr.state(), 0, tree, Some((0, 1)), 0, empty());
        assert!(!forged.verify());
    }

    #[test]
    fn rejects_a_path_longer_than_the_tree() {
        let (_, proof) = sample(40);
        let step = proof.path[0].clone();
        let path = from_fn(|_| step.clone());

        let forged = SampleProof {
            path,
            path_len: MAX_DEPTH,
            ..proof
        };
        assert!(!forged.verify());
    }

    #[test]
    fn rejects_a_length_beyond_the_path() {
        let (_, proof) = sample(40);
        let forged = SampleProof {
            path_len: MAX_DEPTH + 1,
            ..proof
        };

        assert!(!forged.verify());
    }

    #[test]
    fn ignores_steps_past_the_length() {
        let (_, mut proof) = sample(40);
        let stranded = proof.path_len + 1;
        proof.path[stranded] = proof.path[0].clone();

        assert!(proof.verify());
    }

    fn sample(element: u64) -> (Mmr, SampleProof) {
        let mmr = filled(100);
        let proof = mmr.prove(element as usize);
        (mmr, proof)
    }

    fn tall_tree() -> (Mmr, usize) {
        let mmr = filled(100);
        let tree = mmr
            .ranks()
            .iter()
            .position(|rank| rank.is_some_and(|rank| rank > 0))
            .expect("a tall tree");
        (mmr, tree)
    }

    fn empty() -> [Option<Step<u64>>; MAX_DEPTH] {
        from_fn(|_| None)
    }
}
