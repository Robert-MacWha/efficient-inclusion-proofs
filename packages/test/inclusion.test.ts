import assert from "node:assert/strict";
import { before, describe, test } from "node:test";

import type { WasmTester } from "circom_tester";

import type { SkewMmr } from "../src/mmr.ts";
import type { Proof } from "../src/proof.ts";
import { MAX_RANK, MAX_TREES, RANK_BITS, filled, input, mmr } from "./helpers.ts";
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

  test("refuses a non-member through `valid`, not an unsatisfiable witness", async () => {
    const accumulator = filled(100);
    const witness = await circuit.calculateWitness(
      input(accumulator, accumulator.prove(40), 1000n),
    );
    await circuit.checkConstraints(witness);
    assert.equal(witness[1], 0n);
  });

  test("outputs the insertion index of every element", async () => {
    const accumulator = mmr();
    for (let i = 0; i < 40; i++) {
      accumulator.append(BigInt(i));

      for (let j = 0; j <= i; j++) {
        const message = `element ${j} at len ${i + 1}`;
        assert.equal(await index(circuit, accumulator, j), BigInt(j), message);
      }
    }
  });

  test("outputs the index of a leaf at the maximum path length", async () => {
    const accumulator = filled(2 ** (MAX_RANK + 1) - 1);

    let j = 0;
    while (accumulator.prove(j).path.length < MAX_RANK) j++;

    assert.equal(await index(circuit, accumulator, j), BigInt(j));
  });

  test("outputs the index of the root of a tree that outgrows the circuit", async () => {
    const accumulator = filled(2 ** (MAX_RANK + 2) - 1);
    const j = accumulator.len() - 1;

    assert.equal(await index(circuit, accumulator, j), BigInt(j));
  });

  test("outputs the index of every element on a full frontier", async () => {
    const accumulator = mmr();
    while (accumulator.depth() < MAX_TREES) {
      accumulator.append(BigInt(accumulator.len()));
    }

    for (let j = 0; j < accumulator.len(); j++) {
      assert.equal(await index(circuit, accumulator, j), BigInt(j), `element ${j}`);
    }
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

  test("rejects packed ranks wider than their packing", async () => {
    const accumulator = filled(100);
    const forged = input(accumulator, accumulator.prove(40), 40n);
    forged.packedRanks |= 1n << BigInt(RANK_BITS * MAX_TREES);

    await rejects(satisfies(circuit, forged));
  });

  test("rejects a depth wider than a rank", async () => {
    const accumulator = filled(100);
    const forged = input(accumulator, accumulator.prove(40), 40n);
    forged.depth = forged.tree + (1n << BigInt(RANK_BITS));

    await rejects(satisfies(circuit, forged));
  });
});

/** The `index` the circuit outputs for a valid proof of the element at `j`. */
async function index(
  circuit: WasmTester,
  accumulator: SkewMmr<bigint>,
  j: number,
): Promise<bigint> {
  const witness = await circuit.calculateWitness(
    input(accumulator, accumulator.prove(j), BigInt(j)),
  );
  await circuit.checkConstraints(witness);
  assert.equal(witness[1], 1n, `element ${j} is a member`);
  return witness[2]!;
}

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
