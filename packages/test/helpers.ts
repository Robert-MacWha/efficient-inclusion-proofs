import { poseidonHasher } from "../src/hasher.ts";
import { SkewMmr } from "../src/mmr.ts";
import type { Proof } from "../src/proof.ts";

/** Matches the parameters of test/circuits/inclusion.circom. */
export const MAX_DEPTH = 8;

/** The input signals of `SkewMmrInclusion`. */
export interface Input {
  roots: bigint[];
  element: bigint;
  tree: bigint;
  children: [bigint, bigint];
  pathLen: bigint;
  pathElements: bigint[];
  pathSiblings: bigint[];
  pathRight: bigint[];
}

export function mmr(): SkewMmr<bigint> {
  return new SkewMmr(poseidonHasher, 32);
}

/** An MMR holding `0..n`, so the element at any index equals that index. */
export function filled(n: number): SkewMmr<bigint> {
  const filling = mmr();
  for (let i = 0; i < n; i++) {
    filling.append(BigInt(i));
  }
  return filling;
}

export function input(proof: Proof<bigint>): Input {
  return {
    roots: pad(proof.roots),
    element: proof.element,
    tree: BigInt(proof.tree),
    children: proof.children ?? [0n, 0n],
    pathLen: BigInt(proof.path.length),
    pathElements: pad(proof.path.map((step) => step.element)),
    pathSiblings: pad(proof.path.map((step) => step.sibling)),
    pathRight: pad(proof.path.map((step) => (step.right ? 1n : 0n))),
  };
}

/** Fits `values` to `MAX_DEPTH` signals, zero-padded. */
function pad(values: bigint[]): bigint[] {
  return Array.from({ length: MAX_DEPTH }, (_, i) => values[i] ?? 0n);
}
