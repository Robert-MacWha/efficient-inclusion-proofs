import { poseidon3 } from "poseidon-lite";

export interface Hasher<E> {
  /** A collision-resistant hash function that hashes three elements. */
  hash(element: E, left: E, right: E): E;
}

/** Matches `Hash3` in circuits/hasher.circom. */
export const poseidonHasher: Hasher<bigint> = {
  hash: (element, left, right) => poseidon3([element, left, right]),
};
