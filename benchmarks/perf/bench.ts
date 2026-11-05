/**
 * Off-chain performance of skew-MMR against zk-kit's trees, mirroring
 * https://github.com/zk-kit/zk-kit/tree/main/benchmarks: the same libraries (`@zk-kit/imt`,
 * `@zk-kit/lean-imt`), the same hash (`poseidon-lite`, the original circomlib Poseidon), the same
 * tree sizes (depths 3, 7 and 10, i.e. 8, 128 and 1,024 leaves, plus 2^14), and the same
 * operations: insert every leaf, generate proofs for a random half of them, verify those proofs.
 * Update and delete are left out because skew-MMR is append-only.
 *
 * zk-kit's harness keeps calling a benny case after its work runs out (the insert and verify
 * cases become no-ops once every leaf is done), which inflates ops/sec. This one times a fixed
 * batch of real operations instead, repeated until it has run for long enough, and reports the
 * median time per operation.
 *
 * Writes `results/perf-js.csv`. Run from `benchmarks/` with Node >= 23.6 (type stripping).
 */
import { writeFileSync } from "node:fs";
import { performance } from "node:perf_hooks";

import { IMT } from "@zk-kit/imt";
import { LeanIMT } from "@zk-kit/lean-imt";
import { poseidon2, poseidon5 } from "poseidon-lite";

import { SkewMmr, poseidonHasher, verify } from "../../packages/src/index.ts";

const DEPTHS = [3, 7, 10, 14];
/** Minimum wall time and run count per measurement. */
const MIN_MS = 500;
const MIN_RUNS = 3;

/** One structure under test: build it, prove an index, verify the proof. */
interface Subject<T, P> {
  name: string;
  build(leaves: bigint[]): T;
  prove(tree: T, index: number): P;
  verify(tree: T, proof: P, leaves: bigint[], index: number): boolean;
}

const binaryImt: Subject<IMT, ReturnType<IMT["createProof"]>> = {
  name: "binary-imt",
  build(leaves) {
    const tree = new IMT(poseidon2, Math.ceil(Math.log2(leaves.length)), 0, 2);
    for (const leaf of leaves) tree.insert(leaf);
    return tree;
  },
  prove: (tree, index) => tree.createProof(index),
  verify: (tree, proof) => tree.verifyProof(proof),
};

const quinaryImt: Subject<IMT, ReturnType<IMT["createProof"]>> = {
  name: "quinary-imt",
  build(leaves) {
    const depth = Math.max(1, Math.ceil(Math.log(leaves.length) / Math.log(5) - 1e-9));
    const tree = new IMT(poseidon5, depth, 0, 5);
    for (const leaf of leaves) tree.insert(leaf);
    return tree;
  },
  prove: (tree, index) => tree.createProof(index),
  verify: (tree, proof) => tree.verifyProof(proof),
};

const leanImt: Subject<LeanIMT<bigint>, ReturnType<LeanIMT<bigint>["generateProof"]>> = {
  name: "leanimt",
  build(leaves) {
    const tree = new LeanIMT<bigint>((a, b) => poseidon2([a, b]));
    for (const leaf of leaves) tree.insert(leaf);
    return tree;
  },
  prove: (tree, index) => tree.generateProof(index),
  verify: (tree, proof) => tree.verifyProof(proof),
};

interface Skew {
  mmr: SkewMmr<bigint>;
  roots: bigint[];
  ranks: number[];
}

const skewMmr: Subject<Skew, ReturnType<SkewMmr<bigint>["prove"]>> = {
  name: "skew-mmr",
  build(leaves) {
    const mmr = new SkewMmr(poseidonHasher, 32);
    for (const leaf of leaves) mmr.append(leaf);
    return { mmr, roots: mmr.roots(), ranks: mmr.ranks() };
  },
  prove: (tree, index) => tree.mmr.prove(index),
  verify: (tree, proof, leaves, index) =>
    verify(poseidonHasher, proof, tree.roots, tree.ranks, leaves[index]!),
};

/**
 * Median milliseconds per call of `batch`, repeated for at least `MIN_MS` and `MIN_RUNS`. The
 * caller has already run every batch once (building, proving and checking each proof), which
 * warms the JIT.
 */
function time(batch: () => void): number {
  const runs: number[] = [];
  const start = performance.now();
  while (runs.length < MIN_RUNS || performance.now() - start < MIN_MS) {
    const t = performance.now();
    batch();
    runs.push(performance.now() - t);
  }
  runs.sort((a, b) => a - b);
  return runs[Math.floor(runs.length / 2)]!;
}

/** A deterministic sample of half the indices, so every structure proves the same leaves. */
function sample(n: number): number[] {
  let seed = 0x2545f491;
  const indices = Array.from({ length: n }, (_, i) => i);
  for (let i = n - 1; i > 0; i--) {
    seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
    const j = seed % (i + 1);
    [indices[i], indices[j]] = [indices[j]!, indices[i]!];
  }
  return indices.slice(0, Math.max(1, n / 2));
}

const rows = ["structure,leaves,op,us_per_op"];
for (const depth of DEPTHS) {
  const n = 2 ** depth;
  const leaves = Array.from({ length: n }, (_, i) => BigInt(i + 1));
  const indices = sample(n);

  for (const subject of [binaryImt, quinaryImt, leanImt, skewMmr] as Subject<unknown, unknown>[]) {
    const tree = subject.build(leaves);
    const proofs = indices.map((index) => subject.prove(tree, index));
    for (const [i, proof] of proofs.entries()) {
      if (!subject.verify(tree, proof, leaves, indices[i]!)) {
        throw new Error(`${subject.name}: proof of ${indices[i]} rejected`);
      }
    }

    const ops: [string, number, () => void][] = [
      ["insert", n, () => subject.build(leaves)],
      ["prove", indices.length, () => indices.forEach((index) => subject.prove(tree, index))],
      [
        "verify",
        indices.length,
        () => proofs.forEach((proof, i) => subject.verify(tree, proof, leaves, indices[i]!)),
      ],
    ];
    for (const [op, count, batch] of ops) {
      const us = (time(batch) * 1000) / count;
      rows.push(`${subject.name},${n},${op},${us.toFixed(3)}`);
      console.log(`${subject.name.padEnd(12)} ${String(n).padStart(6)} leaves  ${op.padEnd(6)} ${us.toFixed(2).padStart(9)} µs/op`);
    }
  }
}

writeFileSync(new URL("../results/perf-js.csv", import.meta.url), rows.join("\n") + "\n");
