import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { wasm } from "circom_tester";
import type { WasmTester } from "circom_tester";

import { poseidonHasher } from "../src/hasher.ts";
import type { SkewMmr } from "../src/mmr.ts";
import { verify } from "../src/proof.ts";
import type { Proof } from "../src/proof.ts";
import { input } from "./helpers.ts";
import type { Input } from "./helpers.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const modules = path.join(here, "..", "node_modules");

/** An implementation of inclusion-proof verification. */
export interface Verifier {
  name: string;
  /** Longest MMR the shared suite proves every element of. */
  sweep: number;
  verify(
    accumulator: SkewMmr<bigint>,
    proof: Proof<bigint>,
    element: bigint,
  ): Promise<boolean>;
}

export const reference: Verifier = {
  name: "verify",
  sweep: 100,
  verify(accumulator, proof, element) {
    const accepted = verify(
      poseidonHasher,
      proof,
      accumulator.roots(),
      accumulator.ranks(),
      element,
    );
    return Promise.resolve(accepted);
  },
};

export async function compiled(): Promise<Verifier> {
  const circuit = await compile("inclusion.circom");

  return {
    name: "SkewMmrInclusion",
    sweep: 20,
    verify: (accumulator, proof, element) =>
      satisfies(circuit, input(accumulator, proof, element)),
  };
}

export function compile(name: string): Promise<WasmTester> {
  return wasm(path.join(here, "circuits", name), { include: [modules] });
}

/**
 * Whether `signals` yield a witness for `circuit`. A witness that generates but violates a
 * constraint throws, since that means the generator and the R1CS disagree.
 */
export async function satisfies(circuit: WasmTester, signals: Input): Promise<boolean> {
  let witness;
  try {
    witness = await circuit.calculateWitness(signals);
  } catch {
    return false;
  }
  await circuit.checkConstraints(witness);
  return true;
}

export function accepts(verdict: Promise<boolean>, message?: string): Promise<void> {
  return verdict.then((accepted) => assert.ok(accepted, message));
}

export function rejects(verdict: Promise<boolean>): Promise<void> {
  return verdict.then((accepted) => assert.ok(!accepted));
}
