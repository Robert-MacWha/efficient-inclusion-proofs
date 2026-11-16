import assert from "node:assert/strict";
import { describe, test } from "node:test";

import type { SkewMmr } from "../src/mmr.ts";
import type { Proof } from "../src/proof.ts";
import { MAX_DEPTH, filled, mmr } from "./helpers.ts";
import { accepts, compiled, reference, rejects } from "./verifiers.ts";

for (const verifier of [reference, await compiled()]) {
  describe(verifier.name, () => {
    test("proves every element at every size", async () => {
      const accumulator = mmr();
      for (let i = 0; i < verifier.sweep; i++) {
        accumulator.append(BigInt(i));

        for (let j = 0; j <= i; j++) {
          await accepts(verifier.verify(accumulator.prove(j)), `element ${j} at len ${i + 1}`);
        }
      }
    });

    test("proves an internal node", async () => {
      const proof = filled(100).prove(99);
      assert.notEqual(proof.children, null, "an internal node");

      await accepts(verifier.verify(proof));
    });

    test("proves a leaf at the maximum path length", async () => {
      const accumulator = filled(2 ** (MAX_DEPTH + 1) - 1);

      let index = 0;
      while (accumulator.prove(index).path.length < MAX_DEPTH) index++;

      await accepts(verifier.verify(accumulator.prove(index)));
    });

    test("proves the root of a tree that outgrows the circuit", async () => {
      const accumulator = filled(2 ** (MAX_DEPTH + 2) - 1);
      assert.ok(accumulator.ranks()[0]! > MAX_DEPTH, "tree outgrows the circuit");

      await accepts(verifier.verify(accumulator.prove(accumulator.len() - 1)));
    });

    test("proves an element on a full frontier", async () => {
      const accumulator = mmr();
      while (accumulator.depth() < MAX_DEPTH) {
        accumulator.append(BigInt(accumulator.len()));
      }

      const proof = accumulator.prove(accumulator.len() - 1);
      assert.equal(proof.tree, MAX_DEPTH - 1);

      await accepts(verifier.verify(proof));
    });

    test("rejects another member", async () => {
      const proof = filled(100).prove(40);

      // 41 is in the accumulator, 1000 is not.
      await rejects(verifier.verify({ ...proof, element: 41n }));
      await rejects(verifier.verify({ ...proof, element: 1000n }));
    });

    test("rejects a proof from another accumulator", async () => {
      const accumulator = filled(100);

      const other = mmr();
      other.append(1000n);
      const forged = other.prove(0);

      await rejects(verifier.verify({ ...forged, roots: accumulator.roots() }));
    });

    test("rejects a tree above the depth", async () => {
      const accumulator = filled(100);
      const proof = accumulator.prove(40);

      await rejects(verifier.verify({ ...proof, tree: accumulator.depth() }));
    });

    test("rejects a flipped direction", async () => {
      const proof = filled(100).prove(40);
      const step = proof.path[0]!;
      step.right = !step.right;

      await rejects(verifier.verify(proof));
    });

    test("rejects a tampered sibling", async () => {
      const proof = filled(100).prove(40);
      const step = proof.path[0]!;
      step.sibling += 1n;

      await rejects(verifier.verify(proof));
    });

    test("rejects a tree root claimed as a leaf", async () => {
      const accumulator = filled(100);
      const tree = tall(accumulator);
      const roots = accumulator.roots();
      const forged: Proof<bigint> = {
        roots,
        element: roots[tree]!,
        tree,
        children: null,
        path: [],
      };

      await rejects(verifier.verify(forged));
    });

    test("rejects a leaf claimed as a tree root", async () => {
      const accumulator = filled(100);
      const forged: Proof<bigint> = {
        roots: accumulator.roots(),
        element: 0n,
        tree: tall(accumulator),
        children: [0n, 1n],
        path: [],
      };

      await rejects(verifier.verify(forged));
    });

    test("rejects a path longer than the tree", async () => {
      const accumulator = filled(100);
      const proof = accumulator.prove(98);
      const path = [...proof.path, ...proof.path];
      assert.ok(path.length > accumulator.ranks()[proof.tree]!, "path outgrows the tree");

      await rejects(verifier.verify({ ...proof, path }));
    });
  });
}

/** A tree tall enough that its root cannot also be a leaf. */
function tall(accumulator: SkewMmr<bigint>): number {
  const tree = accumulator.ranks().findIndex((rank) => rank > 0);
  assert.notEqual(tree, -1, "a tall tree");
  return tree;
}
