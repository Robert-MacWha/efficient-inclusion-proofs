import assert from "node:assert/strict";
import { before, describe, test } from "node:test";

import type { WasmTester } from "circom_tester";

import { MAX_DEPTH, filled, input } from "./helpers.ts";
import { accepts, compile, rejects, satisfies } from "./verifiers.ts";

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
    await accepts(satisfies(circuit, input(filled(100).prove(40))));
  });

  test("refuses a non-member through `valid`, not an unsatisfiable witness", async () => {
    const proof = filled(100).prove(40);
    await refuses(circuit, input({ ...proof, element: 1000n }));
  });

  test("refuses a tree past the roots through `valid`", async () => {
    const proof = filled(100).prove(40);
    await refuses(circuit, input({ ...proof, tree: MAX_DEPTH }));
  });

  test("refuses a path length past the steps through `valid`", async () => {
    const forged = input(filled(100).prove(40));
    forged.pathLen = BigInt(MAX_DEPTH + 1);

    await refuses(circuit, forged);
  });

  test("ignores steps past the length", async () => {
    const forged = input(filled(100).prove(40));
    const stranded = Number(forged.pathLen) + 1;
    forged.pathElements[stranded] = 1n;
    forged.pathSiblings[stranded] = 1n;
    forged.pathRight[stranded] = 1n;

    await accepts(satisfies(circuit, forged));
  });

  test("rejects a direction that is not a bit", async () => {
    const forged = input(filled(100).prove(40));
    forged.pathRight[0] = 2n;

    await rejects(satisfies(circuit, forged));
  });
});

/** Asserts `signals` have a witness, and that it reports `valid` as 0. */
async function refuses(circuit: WasmTester, signals: object): Promise<void> {
  const witness = await circuit.calculateWitness(signals);
  await circuit.checkConstraints(witness);
  assert.equal(witness[1], 0n);
}
