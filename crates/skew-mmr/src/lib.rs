#[cfg(feature = "r1cs")]
pub mod constraints;
pub mod hasher;
pub mod proof;
pub mod state;

use std::{array::from_fn, marker::PhantomData};

use hasher::Hasher;
use proof::{Proof, Step};
use state::State;

/// An append-only set commitment structure.
///
/// SkewMmr is a modified MMR (Merkle Mountain Range) that uses skew-binary-style
/// carrying to append new elements in a maximum of O(1) hashes.
#[derive(Debug, Clone)]
pub struct SkewMmr<const MAX_DEPTH: usize, E: Clone, H: Hasher<E>> {
    /// Perfect binary trees of decreasing ranks. Entries above `depth` are `None`.
    stack: [Option<Node<E>>; MAX_DEPTH],
    depth: usize,
    len: usize,
    hasher: PhantomData<H>,
}

#[derive(Debug, Clone)]
struct Node<E: Clone> {
    root: E,
    rank: u32,
    element: E,
    children: Option<Box<(Node<E>, Node<E>)>>,
}

impl<const MAX_DEPTH: usize, E: Clone, H: Hasher<E>> SkewMmr<MAX_DEPTH, E, H> {
    pub fn new() -> Self {
        Self {
            stack: from_fn(|_| None),
            depth: 0,
            len: 0,
            hasher: PhantomData,
        }
    }

    /// Appends an element to the MMR in O(1) hashes.
    pub fn append(&mut self, element: E) {
        self.len += 1;

        if self.depth < 2 || self.rank(self.depth - 1) != self.rank(self.depth - 2) {
            self.push(Node::leaf(element));
            return;
        }

        let left = self.pop();
        let right = self.pop();
        self.push(Node::internal::<H>(element, left, right));
    }

    /// Prove the element at `index`, counted in insertion order.
    pub fn prove(&self, index: usize) -> Proof<MAX_DEPTH, E, H> {
        assert!(index < self.len, "index out of range");

        let (tree, offset) = self.locate(self.len - 1 - index);
        let mut path = from_fn(|_| None);
        let (proven, path_len) = self.node(tree).walk(offset, &mut path);
        let children = proven
            .children
            .as_ref()
            .map(|children| (children.0.root.clone(), children.1.root.clone()));

        Proof::new(
            self.roots(),
            self.state(),
            proven.element.clone(),
            tree,
            children,
            path_len,
            path,
        )
    }

    /// Roots of the trees, closest to the top of the stack last. Entries above `depth` are `None`.
    pub fn roots(&self) -> [Option<E>; MAX_DEPTH] {
        from_fn(|i| (i < self.depth).then(|| self.node(i).root.clone()))
    }

    /// Ranks of the trees, paired with [`Self::roots`].
    pub fn ranks(&self) -> [Option<u32>; MAX_DEPTH] {
        from_fn(|i| (i < self.depth).then(|| self.node(i).rank))
    }

    /// The frontier, packed by [`State`].
    pub fn state(&self) -> State<MAX_DEPTH> {
        State::new(&self.ranks(), self.len as u32)
    }

    pub fn len(&self) -> usize {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    pub fn depth(&self) -> usize {
        self.depth
    }

    /// Locates the tree and offset of the element at `position` in the MMR.
    fn locate(&self, mut position: usize) -> (usize, usize) {
        for tree in (0..self.depth).rev() {
            let size = self.node(tree).size();
            if position < size {
                return (tree, position);
            }
            position -= size;
        }
        unreachable!("position is below len, so some tree holds it")
    }

    fn node(&self, tree: usize) -> &Node<E> {
        self.stack[tree].as_ref().expect("populated below depth")
    }

    fn rank(&self, tree: usize) -> u32 {
        self.node(tree).rank
    }

    fn push(&mut self, node: Node<E>) {
        assert!(self.depth < MAX_DEPTH, "stack is full");
        self.stack[self.depth] = Some(node);
        self.depth += 1;
    }

    fn pop(&mut self) -> Node<E> {
        self.depth -= 1;
        self.stack[self.depth]
            .take()
            .expect("populated below depth")
    }
}

impl<const MAX_DEPTH: usize, E: Clone, H: Hasher<E>> Default for SkewMmr<MAX_DEPTH, E, H> {
    fn default() -> Self {
        Self::new()
    }
}

impl<E: Clone> Node<E> {
    fn leaf(element: E) -> Self {
        Self {
            root: element.clone(),
            rank: 0,
            element,
            children: None,
        }
    }

    fn internal<H: Hasher<E>>(element: E, left: Node<E>, right: Node<E>) -> Self {
        Self {
            root: H::hash(&element, &left.root, &right.root),
            rank: left.rank + 1,
            element,
            children: Some(Box::new((left, right))),
        }
    }

    /// Write the ancestors of the node at `offset` into `path`, closest first, and return that
    /// node alongside the number of ancestors written. Offset 0 is this node, then the left
    /// subtree, then the right.
    fn walk<'a>(&'a self, offset: usize, path: &mut [Option<Step<E>>]) -> (&'a Node<E>, usize) {
        if offset == 0 {
            return (self, 0);
        }

        let children = self.children.as_ref().expect("a leaf holds only offset 0");
        let left_size = children.0.size();
        let right = offset > left_size;
        let (next, offset) = match right {
            true => (&children.1, offset - 1 - left_size),
            false => (&children.0, offset - 1),
        };

        let (proven, len) = next.walk(offset, path);
        path[len] = Some(Step {
            element: self.element.clone(),
            sibling: match right {
                true => children.0.root.clone(),
                false => children.1.root.clone(),
            },
            right,
        });
        (proven, len + 1)
    }

    fn size(&self) -> usize {
        (1 << (self.rank + 1)) - 1
    }
}

#[cfg(test)]
pub mod testing {
    use super::{Hasher, SkewMmr};
    use crate::hasher::MockHasher;

    pub const MAX_DEPTH: usize = 26;

    pub type Mmr = SkewMmr<MAX_DEPTH, u64, MockHasher>;

    /// An accumulator holding `0..n`, so the element at any index equals that index.
    pub fn filled<const DEPTH: usize, E: Clone + From<u64>, H: Hasher<E>>(
        n: u64,
    ) -> SkewMmr<DEPTH, E, H> {
        let mut mmr = SkewMmr::new();
        for i in 0..n {
            mmr.append(E::from(i));
        }
        mmr
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use testing::Mmr;

    #[test]
    fn ranks_decrease_except_the_top_pair() {
        let mut mmr = Mmr::new();
        for i in 0..1000 {
            mmr.append(i);

            let ranks: Vec<u32> = mmr.ranks().into_iter().flatten().collect();
            for pair in ranks.windows(2).take(ranks.len().saturating_sub(2)) {
                assert!(pair[0] > pair[1], "{ranks:?}");
            }
            if let [.., a, b] = ranks[..] {
                assert!(a >= b, "{ranks:?}");
            }
        }
    }

    #[test]
    fn tree_sizes_cover_every_element() {
        let mut mmr = Mmr::new();
        for i in 0..1000 {
            mmr.append(i);

            let covered: usize = mmr
                .ranks()
                .into_iter()
                .flatten()
                .map(|rank| (1 << (rank + 1)) - 1)
                .sum();
            assert_eq!(covered, mmr.len());
        }
    }

    #[test]
    #[should_panic(expected = "stack is full")]
    fn rejects_overflowing_max_depth() {
        let mut mmr: SkewMmr<3, u64, hasher::MockHasher> = SkewMmr::new();
        for i in 0..1000 {
            mmr.append(i);
        }
    }
}
