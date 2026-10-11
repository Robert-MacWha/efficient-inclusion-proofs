import { poseidonHasher } from "../src/hasher.ts";
import { SkewMmr } from "../src/mmr.ts";
import type { Proof } from "../src/proof.ts";

/** Matches the parameters of test/circuits/inclusion.circom. */
export const MAX_TREES = 8;
export const MAX_RANK = MAX_TREES - 1;

/** Width of each `rank` in `packedRanks`, matching `LibSkewMmr.sol`. */
export const RANK_BITS = 6;

/** The input signals of `SkewMmrInclusion`. */
export interface Input {
  roots: bigint[];
  packedRanks: bigint;
  depth: bigint;
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

export function input(
  accumulator: SkewMmr<bigint>,
  proof: Proof<bigint>,
  element: bigint,
): Input {
  return {
    roots: pad(accumulator.roots(), MAX_TREES),
    packedRanks: pack(accumulator.ranks()),
    depth: BigInt(accumulator.depth()),
    element,
    tree: BigInt(proof.tree),
    children: proof.children ?? [0n, 0n],
    pathLen: BigInt(proof.path.length),
    pathElements: pad(proof.path.map((step) => step.element), MAX_RANK),
    pathSiblings: pad(proof.path.map((step) => step.sibling), MAX_RANK),
    pathRight: pad(proof.path.map((step) => (step.right ? 1n : 0n)), MAX_RANK),
  };
}

/** Packs `rank`s into the `packedRanks` word `LibSkewMmr.sol` holds. */
function pack(ranks: number[]): bigint {
  return ranks.reduce(
    (packed, rank, i) => packed | (BigInt(rank) << BigInt(RANK_BITS * i)),
    0n,
  );
}

function pad(values: bigint[], length: number): bigint[] {
  return [...values, ...Array<bigint>(length - values.length).fill(0n)];
}
