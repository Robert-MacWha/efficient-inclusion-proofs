import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { poseidonHasher } from "../src/hasher.ts";
import type { SkewMmr } from "../src/mmr.ts";
import type { Proof } from "../src/proof.ts";
import { MAX_RANK, MAX_TREES, filled, mmr } from "./helpers.ts";
import { accepts, compiled, reference, rejects } from "./verifiers.ts";

for (const verifier of [reference, await compiled()]) {
  describe(verifier.name, () => {
    test("proves every element at every size", async () => {
      const accumulator = mmr();
      for (let i = 0; i < verifier.sweep; i++) {
        accumulator.append(BigInt(i));

        for (let j = 0; j <= i; j++) {
          await accepts(
            verifier.verify(accumulator, accumulator.prove(j), BigInt(j)),
            `element ${j} at len ${i + 1}`,
          );
        }
      }
    });

    test("proves an internal node", async () => {
      const accumulator = filled(100);
      const proof = accumulator.prove(99);
      assert.notEqual(proof.children, null, "an internal node");

      await accepts(verifier.verify(accumulator, proof, 99n));
    });

    test("proves a leaf at the maximum path length", async () => {
      const accumulator = filled(2 ** (MAX_RANK + 1) - 1);

      let index = 0;
      while (accumulator.prove(index).path.length < MAX_RANK) index++;

      await accepts(verifier.verify(accumulator, accumulator.prove(index), BigInt(index)));
    });

    test("proves the root of a tree that outgrows the circuit", async () => {
      const accumulator = filled(2 ** (MAX_RANK + 2) - 1);
      assert.ok(accumulator.ranks()[0]! > MAX_RANK, "tree outgrows the circuit");

      const index = accumulator.len() - 1;
      await accepts(verifier.verify(accumulator, accumulator.prove(index), BigInt(index)));
    });

    test("proves an element on a full frontier", async () => {
      const accumulator = mmr();
      while (accumulator.depth() < MAX_TREES) {
        accumulator.append(BigInt(accumulator.len()));
      }

      const index = accumulator.len() - 1;
      assert.equal(accumulator.prove(index).tree, MAX_TREES - 1);

      await accepts(verifier.verify(accumulator, accumulator.prove(index), BigInt(index)));
    });

    test("rejects an element the proof was not made for", async () => {
      const accumulator = filled(100);
      const proof = accumulator.prove(40);

      // 41 is in the accumulator, 1000 is not.
      await rejects(verifier.verify(accumulator, proof, 41n));
      await rejects(verifier.verify(accumulator, proof, 1000n));
    });

    test("rejects a proof from another accumulator", async () => {
      const accumulator = filled(100);

      const other = mmr();
      other.append(1000n);

      await rejects(verifier.verify(accumulator, other.prove(0), 1000n));
    });

    test("rejects a tree out of range", async () => {
      const accumulator = filled(100);
      const proof = accumulator.prove(40);

      await rejects(
        verifier.verify(accumulator, { ...proof, tree: accumulator.depth() }, 40n),
      );
    });

    test("rejects a flipped direction", async () => {
      const accumulator = filled(100);
      const proof = accumulator.prove(40);
      const step = proof.path[0]!;
      step.right = !step.right;

      await rejects(verifier.verify(accumulator, proof, 40n));
    });

    test("rejects a tampered sibling", async () => {
      const accumulator = filled(100);
      const proof = accumulator.prove(40);
      const step = proof.path[0]!;
      step.sibling += 1n;

      await rejects(verifier.verify(accumulator, proof, 40n));
    });

    test("rejects a tree root claimed as a leaf", async () => {
      const accumulator = filled(100);
      const tree = tall(accumulator);
      const forged: Proof<bigint> = { tree, children: null, path: [] };

      await rejects(verifier.verify(accumulator, forged, accumulator.roots()[tree]!));
    });

    test("rejects a leaf claimed as a tree root", async () => {
      const accumulator = filled(100);

      const forged: Proof<bigint> = {
        tree: tall(accumulator),
        children: [0n, 1n],
        path: [],
      };

      await rejects(verifier.verify(accumulator, forged, 0n));
    });

    test("rejects a path longer than the tree", async () => {
      const accumulator = filled(100);
      const proof = accumulator.prove(98);
      const path = [...proof.path, ...proof.path];
      assert.ok(path.length > accumulator.ranks()[proof.tree]!, "path outgrows the tree");

      await rejects(verifier.verify(accumulator, { ...proof, path }, 98n));
    });

    test("rejects a leaf crafted to sit one level above a forged element", async () => {
      const secret = 123456789n;
      const { hash } = poseidonHasher;
      const crafted = hash(999n, hash(secret, 0n, 0n), 0n);

      const accumulator = filled(101);
      accumulator.append(crafted);
      const tree = accumulator.depth() - 1;
      assert.equal(accumulator.roots()[tree], crafted, "crafted value is a leaf root");

      const forged: Proof<bigint> = {
        tree,
        children: [0n, 0n],
        path: [{ element: 999n, sibling: 0n, right: false }],
      };

      await rejects(verifier.verify(accumulator, forged, secret));
    });
  });
}

/** A tree tall enough that its root cannot also be a leaf. */
function tall(accumulator: SkewMmr<bigint>): number {
  const tree = accumulator.ranks().findIndex((rank) => rank > 0);
  assert.notEqual(tree, -1, "a tall tree");
  return tree;
}
