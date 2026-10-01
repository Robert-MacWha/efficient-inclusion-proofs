import type { Hasher } from "./hasher.ts";

/** An inclusion proof for an element in a `SkewMmr`. */
export interface Proof<E> {
  /** Index into `roots` and `ranks`. */
  tree: number;
  /** The children of the proven node. Null if it is a leaf. */
  children: [E, E] | null;
  /** Ancestors of the proven node, closest first. */
  path: Step<E>[];
}

/** One ancestor of the proven node. */
export interface Step<E> {
  element: E;
  /** The child that the path does not descend into. */
  sibling: E;
  /** Whether the path descends into the right child. */
  right: boolean;
}

/**
 * Verifies that `element` is held by the accumulator described by `roots` and `ranks`.
 *
 * `roots` and `ranks` must come from the same frontier, and must be authenticated by
 * the caller. Mixing frontiers lets a tree root pass as a leaf.
 */
export function verify<E>(
  hasher: Hasher<E>,
  proof: Proof<E>,
  roots: E[],
  ranks: number[],
  element: E,
): boolean {
  const root = roots[proof.tree];
  const rank = ranks[proof.tree];
  if (root === undefined || rank === undefined) return false;
  if (proof.path.length > rank) return false;

  // One step per level between the proven node and the tree root, so a node reached by
  // `L` steps in a tree of rank `r` has rank `r - L`, and is a leaf exactly when `L == r`.
  const isLeaf = proof.path.length === rank;
  if ((proof.children === null) !== isLeaf) return false;

  let current = proof.children === null
    ? element
    : hasher.hash(element, proof.children[0], proof.children[1]);

  for (const step of proof.path) {
    current = step.right
      ? hasher.hash(step.element, step.sibling, current)
      : hasher.hash(step.element, current, step.sibling);
  }
  return current === root;
}
