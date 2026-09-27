//! Skew-binary MMR.
//!
//! An append-only set commitment holding a stack of complete binary trees, where a rank-`k`
//! tree holds `2^(k+1) - 1` elements. The carry rule is skew binary addition: if the two
//! smallest trees have equal rank, the new element becomes the root of their combination;
//! otherwise it becomes a singleton. Either branch is **exactly one hash**.
//!
//! That flatness is the point. A standard MMR does `1 + trailing_ones(n)` hashes per append —
//! amortized ~2, but worst case `O(log n)`, which one unlucky caller pays in full. Here every
//! append costs the same, and the stack is touched either once (a push) or three times
//! (two pops and a push), never `O(log n)`.
//!
//! The element appended becomes the root of the new tree, so elements sit at every node rather
//! than only at leaves. Stack depth is `O(log n)` and an inclusion proof is one step per level
//! of the containing tree, so `O(log n)` hashes.

pub mod hash;

use hash::{EMPTY, Hash, node};

/// One node on the path: the element it holds and the roots of its two subtrees.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Step {
    pub element: Hash,
    pub left: Hash,
    pub right: Hash,
}

/// The proven node first, the containing tree's root last.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Proof {
    /// Index into the stack of roots.
    pub tree: usize,
    pub path: Vec<Step>,
}

pub struct SkewMmr {
    /// Trees of decreasing rank, except that the last two may be equal. The last entry is the
    /// smallest and newest, so appends push and pop at the end.
    stack: Vec<Node>,
    len: usize,
    hashes: usize,
}

impl SkewMmr {
    pub fn new() -> Self {
        Self {
            stack: Vec::new(),
            len: 0,
            hashes: 0,
        }
    }

    /// Append an element. Always performs exactly one hash.
    pub fn append(&mut self, element: Hash) {
        self.len += 1;
        self.hashes += 1;

        let top = self.stack.len();
        if top < 2 || self.stack[top - 1].rank != self.stack[top - 2].rank {
            self.stack.push(Node::leaf(element));
            return;
        }

        // The newer of the two goes left, which keeps preorder walking backwards through
        // append order.
        let left = self.stack.pop().expect("checked above");
        let right = self.stack.pop().expect("checked above");
        self.stack.push(Node::internal(element, left, right));
    }

    /// Build an inclusion proof for the element at `index`, in append order.
    pub fn prove(&self, index: usize) -> Proof {
        assert!(index < self.len, "index out of range");

        let (tree, offset) = self.locate(self.len - 1 - index);
        let mut path = Vec::new();
        self.stack[tree].walk(offset, &mut path);
        path.reverse();
        Proof { tree, path }
    }

    /// The commitment: one root per tree, which is the whole on-chain state alongside `len`.
    pub fn roots(&self) -> Vec<Hash> {
        self.stack.iter().map(|node| node.root).collect()
    }

    pub fn len(&self) -> usize {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Number of trees on the stack.
    pub fn depth(&self) -> usize {
        self.stack.len()
    }

    pub fn total_hashes(&self) -> usize {
        self.hashes
    }

    /// Map a newest-first position to the tree holding it and the offset within that tree.
    fn locate(&self, mut position: usize) -> (usize, usize) {
        for (tree, node) in self.stack.iter().enumerate().rev() {
            if position < node.size() {
                return (tree, position);
            }
            position -= node.size();
        }
        unreachable!("position is below len, so some tree holds it")
    }
}

impl Default for SkewMmr {
    fn default() -> Self {
        Self::new()
    }
}

/// Check that `element` is in the set committed to by `roots`.
///
/// Each step recomputes its node from the element it holds and both child roots, so the path is
/// pinned end to end by collision resistance: the last step must reproduce the tree's published
/// root, which forces the step below it, and so on down to the proven node.
pub fn verify(proof: &Proof, element: Hash, roots: &[Hash]) -> bool {
    let (Some(&root), Some(first)) = (roots.get(proof.tree), proof.path.first()) else {
        return false;
    };
    if first.element != element {
        return false;
    }

    let mut current = node(first.element, first.left, first.right);
    for step in &proof.path[1..] {
        // No direction bit: it is enough that the node below is one of this node's children.
        if current != step.left && current != step.right {
            return false;
        }
        current = node(step.element, step.left, step.right);
    }
    current == root
}

struct Node {
    root: Hash,
    rank: u32,
    element: Hash,
    children: Option<Box<(Node, Node)>>,
}

impl Node {
    fn leaf(element: Hash) -> Self {
        Self {
            root: node(element, EMPTY, EMPTY),
            rank: 0,
            element,
            children: None,
        }
    }

    fn internal(element: Hash, left: Node, right: Node) -> Self {
        Self {
            root: node(element, left.root, right.root),
            rank: left.rank + 1,
            element,
            children: Some(Box::new((left, right))),
        }
    }

    fn size(&self) -> usize {
        (1 << (self.rank + 1)) - 1
    }

    fn step(&self) -> Step {
        let (left, right) = match &self.children {
            Some(children) => (children.0.root, children.1.root),
            None => (EMPTY, EMPTY),
        };
        Step {
            element: self.element,
            left,
            right,
        }
    }

    /// Push the steps from this node down to `offset`, root first. Preorder: offset 0 is this
    /// node, then the left subtree, then the right.
    fn walk(&self, offset: usize, path: &mut Vec<Step>) {
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
}

#[cfg(test)]
mod tests {
    use super::*;

    fn element(i: usize) -> Hash {
        1_000_000 + i as Hash
    }

    fn filled(n: usize) -> SkewMmr {
        let mut mmr = SkewMmr::new();
        for i in 0..n {
            mmr.append(element(i));
        }
        mmr
    }

    /// Every element proves at every intermediate size, which covers every stack shape.
    #[test]
    fn round_trip() {
        let mut mmr = SkewMmr::new();
        for i in 0..200 {
            mmr.append(element(i));
            let roots = mmr.roots();
            for j in 0..=i {
                let proof = mmr.prove(j);
                assert!(
                    verify(&proof, element(j), &roots),
                    "element {j} failed at len {}",
                    i + 1
                );
            }
        }
    }

    /// The whole point of the skew carry rule.
    #[test]
    fn one_hash_per_append() {
        let mmr = filled(100_000);
        assert_eq!(mmr.total_hashes(), mmr.len());
    }

    #[test]
    fn stack_shape() {
        let mut mmr = SkewMmr::new();
        for _ in 0..1000 {
            mmr.append(element(mmr.len()));

            let ranks: Vec<u32> = mmr.stack.iter().map(|node| node.rank).collect();
            let sizes: usize = mmr.stack.iter().map(|node| node.size()).sum();
            assert_eq!(sizes, mmr.len());

            // Strictly decreasing, except the last two may tie.
            for window in ranks.windows(2).take(ranks.len().saturating_sub(2)) {
                assert!(window[0] > window[1], "bad rank order {ranks:?}");
            }
            if let [.., a, b] = ranks[..] {
                assert!(a >= b, "bad rank order {ranks:?}");
            }
        }
    }

    #[test]
    fn rejects_bad_proofs() {
        let mmr = filled(100);
        let roots = mmr.roots();
        let proof = mmr.prove(40);
        assert!(verify(&proof, element(40), &roots));

        assert!(!verify(&proof, element(41), &roots));
        assert!(!verify(&proof, 0, &roots));

        let elsewhere = Proof {
            tree: (proof.tree + 1) % roots.len(),
            ..proof.clone()
        };
        assert!(!verify(&elsewhere, element(40), &roots));

        let out_of_range = Proof {
            tree: roots.len(),
            ..proof.clone()
        };
        assert!(!verify(&out_of_range, element(40), &roots));

        let mut tampered = proof.clone();
        tampered.path.last_mut().unwrap().element ^= 1;
        assert!(!verify(&tampered, element(40), &roots));

        let mut truncated = proof.clone();
        truncated.path.pop();
        assert!(!verify(&truncated, element(40), &roots));

        let stale: Vec<Hash> = roots.iter().map(|r| r.wrapping_add(1)).collect();
        assert!(!verify(&proof, element(40), &stale));
    }

    #[test]
    fn scale() {
        const N: usize = 1 << 20;

        let mut mmr = SkewMmr::new();
        let mut combines = 0;
        let mut max_depth = 0;
        for i in 0..N {
            let before = mmr.depth();
            mmr.append(element(i));
            if mmr.depth() < before {
                combines += 1;
            }
            max_depth = max_depth.max(mmr.depth());
        }
        assert_eq!(mmr.total_hashes(), N);

        let roots = mmr.roots();
        let mut max_path = 0;
        for i in (0..N).step_by(997) {
            let proof = mmr.prove(i);
            assert!(verify(&proof, element(i), &roots));
            max_path = max_path.max(proof.path.len());
        }

        assert!(max_depth <= 32, "stack depth {max_depth}");
        assert!(max_path <= 32, "path length {max_path}");

        println!(
            "n={N} hashes/append={:.4} max stack depth={max_depth} max proof hashes={max_path} \
             combines={:.1}% stack ops/append={:.2}",
            mmr.total_hashes() as f64 / N as f64,
            100.0 * combines as f64 / N as f64,
            (N + 2 * combines) as f64 / N as f64,
        );
    }
}
