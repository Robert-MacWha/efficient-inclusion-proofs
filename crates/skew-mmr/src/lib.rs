pub mod element;
pub mod hasher;
pub mod proof;

use std::marker::PhantomData;

use element::Element;
use hasher::Hasher;
use proof::{Proof, Step};

/// An append-only set commitment structure.
///
/// SkewMmr is a modified MMR (Merkle Mountain Range) that uses skew-binary-style
/// carrying to append new elements in a maximum of O(1) hashes.
pub struct SkewMmr<const MAX_DEPTH: usize, E: Element, H: Hasher<E>> {
    /// Perfect binary trees of decreasing ranks. Entires above `depth` are `None`.
    stack: [Option<Node<E>>; MAX_DEPTH],
    depth: usize,
    len: usize,
    hasher: PhantomData<H>,
}

struct Node<E: Element> {
    root: E,
    rank: u32,
    element: E,
    children: Option<Box<(Node<E>, Node<E>)>>,
}

impl<const MAX_DEPTH: usize, E: Element, H: Hasher<E>> SkewMmr<MAX_DEPTH, E, H> {
    pub fn new() -> Self {
        Self {
            stack: std::array::from_fn(|_| None),
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

    /// Prove the element at `index`.
    pub fn prove(&self, index: usize) -> Proof<E, H> {
        assert!(index < self.len, "index out of range");

        let (tree, offset) = self.locate(self.len - 1 - index);
        let mut path = Vec::new();
        self.node(tree).walk(offset, &mut path);
        path.reverse();

        Proof {
            roots: self.roots(),
            ranks: self.ranks(),
            tree,
            path,
            hasher: PhantomData,
        }
    }

    pub fn roots(&self) -> Vec<E> {
        (0..self.depth).map(|i| self.node(i).root.clone()).collect()
    }

    pub fn ranks(&self) -> Vec<u32> {
        (0..self.depth).map(|i| self.node(i).rank).collect()
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

impl<const MAX_DEPTH: usize, E: Element, H: Hasher<E>> Default for SkewMmr<MAX_DEPTH, E, H> {
    fn default() -> Self {
        Self::new()
    }
}

impl<E: Element> Node<E> {
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

    /// Push the steps from this node down to `offset`, root first. Offset 0 is
    /// this node, then the left subtree, then the right.
    fn walk(&self, offset: usize, path: &mut Vec<Step<E>>) {
        path.push(self.step());
        if offset == 0 {
            return;
        }

        let children = self.children.as_ref().expect("a leaf holds only offset 0");
        let left_size = children.0.size();
        match offset <= left_size {
            true => children.0.walk(offset - 1, path),
            false => children.1.walk(offset - 1 - left_size, path),
        }
    }

    fn step(&self) -> Step<E> {
        Step {
            element: self.element.clone(),
            children: self
                .children
                .as_ref()
                .map(|children| (children.0.root.clone(), children.1.root.clone())),
        }
    }

    fn size(&self) -> usize {
        (1 << (self.rank + 1)) - 1
    }
}

#[cfg(test)]
pub mod testing {
    use super::SkewMmr;
    use crate::hasher::StdHasher;

    pub type Mmr = SkewMmr<32, u64, StdHasher>;

    pub fn filled(n: u64) -> Mmr {
        let mut mmr = Mmr::new();
        for i in 0..n {
            mmr.append(i);
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

            let ranks = mmr.ranks();
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

            let covered: usize = mmr.ranks().iter().map(|&rank| (1 << (rank + 1)) - 1).sum();
            assert_eq!(covered, mmr.len());
        }
    }

    #[test]
    #[should_panic(expected = "stack is full")]
    fn rejects_overflowing_max_depth() {
        let mut mmr: SkewMmr<3, u64, hasher::StdHasher> = SkewMmr::new();
        for i in 0..1000 {
            mmr.append(i);
        }
    }
}
