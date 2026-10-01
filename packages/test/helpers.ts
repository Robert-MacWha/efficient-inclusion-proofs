import { poseidonHasher } from "../src/hasher.ts";
import { SkewMmr } from "../src/mmr.ts";
import type { Proof } from "../src/proof.ts";

/** Matches the parameters of test/circuits/inclusion.circom. */
export const MAX_TREES = 8;
export const MAX_RANK = MAX_TREES - 1;

/** `state` layout, matching `SkewMmr.sol`. */
const DEPTH_BYTE = 26;
const COUNT_BYTE = 27;
export const SENTINEL_BIT = 248;

/** The input signals of `SkewMmrInclusion`. */
export interface Input {
  roots: bigint[];
  state: bigint;
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
    state: pack(accumulator.ranks(), accumulator.depth(), accumulator.len()),
    element,
    tree: BigInt(proof.tree),
    children: proof.children ?? [0n, 0n],
    pathLen: BigInt(proof.path.length),
    pathElements: pad(proof.path.map((step) => step.element), MAX_RANK),
    pathSiblings: pad(proof.path.map((step) => step.sibling), MAX_RANK),
    pathRight: pad(proof.path.map((step) => (step.right ? 1n : 0n)), MAX_RANK),
  };
}

/** Packs a frontier into the `state` word `SkewMmr.sol` holds. */
function pack(ranks: number[], depth: number, count: number): bigint {
  const bytes = ranks.reduce(
    (state, rank, i) => state | (BigInt(rank) << BigInt(8 * i)),
    0n,
  );
  return (
    bytes |
    (BigInt(depth) << BigInt(8 * DEPTH_BYTE)) |
    (BigInt(count) << BigInt(8 * COUNT_BYTE)) |
    (1n << BigInt(SENTINEL_BIT))
  );
}

function pad(values: bigint[], length: number): bigint[] {
  return [...values, ...Array<bigint>(length - values.length).fill(0n)];
}
