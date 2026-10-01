import type { Hasher } from "./hasher.ts";
import type { Proof, Step } from "./proof.ts";

/** Perfect binary tree of rank `rank`. Every node carries an element. */
interface Node<E> {
  root: E;
  rank: number;
  element: E;
  children: [Node<E>, Node<E>] | null;
}

/**
 * An append-only set commitment structure.
 *
 * SkewMmr is a modified MMR (Merkle Mountain Range) that uses skew-binary-style
 * carrying to append new elements in a maximum of O(1) hashes.
 */
export class SkewMmr<E> {
  /** Perfect binary trees of decreasing ranks. */
  private readonly stack: Node<E>[] = [];
  private readonly hasher: Hasher<E>;
  private readonly maxDepth: number;
  private count = 0;

  constructor(hasher: Hasher<E>, maxDepth: number) {
    this.hasher = hasher;
    this.maxDepth = maxDepth;
  }

  /** Appends an element to the MMR in O(1) hashes. */
  append(element: E): void {
    this.count += 1;

    const depth = this.stack.length;
    if (depth < 2 || this.stack[depth - 1]!.rank !== this.stack[depth - 2]!.rank) {
      this.push(leaf(element));
      return;
    }

    const left = this.pop();
    const right = this.pop();
    this.push(internal(this.hasher, element, left, right));
  }

  /** Prove the element at `index`, counted in insertion order. */
  prove(index: number): Proof<E> {
    if (index >= this.count) throw new Error("index out of range");

    const [tree, offset] = this.locate(this.count - 1 - index);
    const path: Step<E>[] = [];
    const children = walk(this.stack[tree]!, offset, path);
    path.reverse();

    return { tree, children, path };
  }

  roots(): E[] {
    return this.stack.map((node) => node.root);
  }

  ranks(): number[] {
    return this.stack.map((node) => node.rank);
  }

  len(): number {
    return this.count;
  }

  isEmpty(): boolean {
    return this.count === 0;
  }

  depth(): number {
    return this.stack.length;
  }

  /** Locates the tree and offset of the element at `position` in the MMR. */
  private locate(position: number): [number, number] {
    for (let tree = this.stack.length - 1; tree >= 0; tree--) {
      const span = size(this.stack[tree]!);
      if (position < span) return [tree, position];
      position -= span;
    }
    throw new Error("position is below len, so some tree holds it");
  }

  private push(node: Node<E>): void {
    if (this.stack.length === this.maxDepth) throw new Error("stack is full");
    this.stack.push(node);
  }

  private pop(): Node<E> {
    const node = this.stack.pop();
    if (node === undefined) throw new Error("populated below depth");
    return node;
  }
}

function leaf<E>(element: E): Node<E> {
  return { root: element, rank: 0, element, children: null };
}

function internal<E>(
  hasher: Hasher<E>,
  element: E,
  left: Node<E>,
  right: Node<E>,
): Node<E> {
  return {
    root: hasher.hash(element, left.root, right.root),
    rank: left.rank + 1,
    element,
    children: [left, right],
  };
}

/**
 * Push the ancestors of the node at `offset`, root first, and return that node's
 * children. Offset 0 is this node, then the left subtree, then the right.
 */
function walk<E>(node: Node<E>, offset: number, path: Step<E>[]): [E, E] | null {
  if (offset === 0) {
    return node.children && [node.children[0].root, node.children[1].root];
  }

  const children = node.children;
  if (children === null) throw new Error("a leaf holds only offset 0");

  const leftSize = size(children[0]);
  const right = offset > leftSize;
  const next = right ? children[1] : children[0];

  path.push({
    element: node.element,
    sibling: right ? children[0].root : children[1].root,
    right,
  });
  return walk(next, right ? offset - 1 - leftSize : offset - 1, path);
}

function size<E>(node: Node<E>): number {
  return 2 ** (node.rank + 1) - 1;
}
