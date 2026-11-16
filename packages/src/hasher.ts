import { poseidon3 } from "poseidon-lite";

export interface Hasher<E> {
  /** The empty element, hashed in place of a leaf's missing children. */
  zero: E;
  /** A collision-resistant hash function that hashes three elements. */
  hash(element: E, left: E, right: E): E;
}

/** Matches `Poseidon(3)` in circuits/inclusion.circom. */
export const poseidonHasher: Hasher<bigint> = {
  zero: 0n,
  hash: (element, left, right) => poseidon3([element, left, right]),
};
