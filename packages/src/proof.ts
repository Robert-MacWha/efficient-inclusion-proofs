import type { Hasher } from "./hasher.ts";

/** An inclusion proof for an element in a `SkewMmr`. */
export interface Proof<E> {
  /** Roots of the frontier's trees. */
  roots: E[];
  /** The proven element. */
  element: E;
  /** Index into `roots`. */
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
 * Verifies that `element` is held by the accumulator described by `roots`.
 *
 * The caller must authenticate `roots` against the accumulator before trusting a `true`.
 */
export function verify<E>(hasher: Hasher<E>, proof: Proof<E>): boolean {
  const root = proof.roots[proof.tree];
  if (root === undefined) return false;

  // Every node, leaf or not, hashes its element with its children.
  const [left, right] = proof.children ?? [hasher.zero, hasher.zero];
  let current = hasher.hash(proof.element, left, right);
  for (const step of proof.path) {
    current = fold(hasher, step, current);
  }
  return current === root;
}

function fold<E>(hasher: Hasher<E>, step: Step<E>, current: E): E {
  return step.right
    ? hasher.hash(step.element, step.sibling, current)
    : hasher.hash(step.element, current, step.sibling);
}
