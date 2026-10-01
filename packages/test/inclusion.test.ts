import { before, describe, test } from "node:test";

import type { WasmTester } from "circom_tester";

import type { Proof } from "../src/proof.ts";
import { MAX_RANK, SENTINEL_BIT, filled, input } from "./helpers.ts";
import { accepts, compile, rejects, satisfies } from "./verifiers.ts";

const FIELD =
  21888242871839275222246405745257275088548364400416034343698204186575808495617n;

/**
 * Signals a forged proof can carry that a `Proof` cannot express, so verify.test.ts
 * cannot reach them.
 */
describe("SkewMmrInclusion signals", () => {
  let circuit: WasmTester;

  before(async () => {
    circuit = await compile("inclusion.circom");
  });

  test("accepts the signals an honest proof encodes to", async () => {
    const accumulator = filled(100);
    await accepts(satisfies(circuit, input(accumulator, accumulator.prove(40), 40n)));
  });

  test("rejects a direction that is not a bit", async () => {
    //? Need to forge a proof that has a path element with a non-binary direction.
    const accumulator = filled(2 ** (MAX_RANK + 1) - 1);
    const ranks = accumulator.ranks();

    // A node one level above the leaves, so the forged element lands at a leaf's depth.
    let index = 0;
    const above = (proof: Proof<bigint>) =>
      proof.children !== null && proof.path.length === ranks[proof.tree]! - 1;
    while (!above(accumulator.prove(index))) index++;

    const node = accumulator.prove(index);
    const [left, right] = node.children!;
    const element = mod((left + 2n * right) * inverse(3n));

    const forged = input(
      accumulator,
      { tree: node.tree, children: null, path: [] },
      element,
    );
    forged.pathLen = BigInt(1 + node.path.length);
    forged.pathElements[0] = BigInt(index);
    forged.pathSiblings[0] = mod(2n * element - right);
    forged.pathRight[0] = 2n;
    node.path.forEach((step, i) => {
      forged.pathElements[i + 1] = step.element;
      forged.pathSiblings[i + 1] = step.sibling;
      forged.pathRight[i + 1] = step.right ? 1n : 0n;
    });

    await rejects(satisfies(circuit, forged));
  });

  test("rejects a path length outside the one-hot range", async () => {
    const accumulator = filled(2 ** (MAX_RANK + 2) - 1);
    const root = accumulator.roots()[0]!;

    const forged = input(accumulator, accumulator.prove(accumulator.len() - 1), root);
    forged.children = [0n, 0n];
    forged.pathLen = BigInt(accumulator.ranks()[0]!);

    await rejects(satisfies(circuit, forged));
  });

  test("rejects a tree at or above the frontier depth", async () => {
    const accumulator = filled(100);
    const depth = accumulator.depth();

    const superseded = filled(50).roots()[0]!;
    const forged = input(
      accumulator,
      { tree: depth, children: null, path: [] },
      superseded,
    );
    forged.roots[depth] = superseded;

    await rejects(satisfies(circuit, forged));
  });

  test("rejects a state wider than its packing", async () => {
    const accumulator = filled(100);
    const forged = input(accumulator, accumulator.prove(40), 40n);
    forged.state |= 1n << BigInt(SENTINEL_BIT + 1);

    await rejects(satisfies(circuit, forged));
  });
});

function mod(value: bigint): bigint {
  return ((value % FIELD) + FIELD) % FIELD;
}

/** Fermat's little theorem, so the forgery can divide in the field. */
function inverse(value: bigint): bigint {
  let result = 1n;
  let base = mod(value);
  for (let exponent = FIELD - 2n; exponent > 0n; exponent >>= 1n) {
    if (exponent & 1n) result = mod(result * base);
    base = mod(base * base);
  }
  return result;
}
