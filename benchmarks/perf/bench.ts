/**
 * Off-chain performance of skew-MMR against zk-kit's trees, following
 * https://github.com/zk-kit/zk-kit/tree/main/benchmarks: the same libraries (`@zk-kit/imt`,
 * `@zk-kit/lean-imt`), the same hash (`poseidon-lite`, the original circomlib Poseidon), and the
 * same operations (insert, generate proofs, verify proofs). Update and delete are left out because
 * skew-MMR is append-only.
 *
 * For each size, every tree is first built to that size (zk-kit's trees through their bulk
 * constructors, which only exist to make setup fast). Then it times:
 *   - insert: `OPS` more leaves, one `insert` call each;
 *   - prove:  `OPS` random leaves;
 *   - verify: those proofs.
 * and reports µs per operation (the median over repeated runs for prove and verify).
 *
 * Writes `results/perf-js.csv`. Run from `benchmarks/` with Node >= 23.6 (type stripping).
 */
import { writeFileSync } from "node:fs";
import { performance } from "node:perf_hooks";

import { IMT } from "@zk-kit/imt";
import { LeanIMT } from "@zk-kit/lean-imt";
import { poseidon2, poseidon5 } from "poseidon-lite";

import { SkewMmr, poseidonHasher, verify } from "../../packages/src/index.ts";

const SIZES = process.env.SIZES?.split(",").map(Number) ?? [1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000];
/** Operations timed per size. */
const OPS = 1_000;
/** Minimum wall time and run count for the repeated (prove, verify) measurements. */
const MIN_MS = 200;
const MIN_RUNS = 3;

/** One structure under test. */
interface Subject<T, P> {
  name: string;
  /** A tree holding `leaves`, with room for `OPS` more. */
  build(leaves: bigint[]): T;
  insert(tree: T, leaf: bigint): void;
  prove(tree: T, index: number): P;
  verify(tree: T, proof: P, leaf: bigint): boolean;
}

/** zk-kit's fixed-depth IMT, at the smallest depth that fits `leaves` plus `OPS` inserts. */
function imt(name: string, arity: number, hash: (nodes: bigint[]) => bigint): Subject<IMT, ReturnType<IMT["createProof"]>> {
  return {
    name,
    build(leaves) {
      const depth = Math.ceil(Math.log(leaves.length + OPS) / Math.log(arity) - 1e-9);
      // The constructor keeps the array it is given, so hand it a copy.
      return new IMT(hash as never, depth, 0, arity, leaves.slice());
    },
    insert: (tree, leaf) => tree.insert(leaf),
    prove: (tree, index) => tree.createProof(index),
    verify: (tree, proof) => tree.verifyProof(proof),
  };
}

const binaryImt = imt("binary-imt", 2, poseidon2);
const quinaryImt = imt("quinary-imt", 5, poseidon5);

const leanImt: Subject<LeanIMT<bigint>, ReturnType<LeanIMT<bigint>["generateProof"]>> = {
  name: "leanimt",
  build: (leaves) => new LeanIMT<bigint>((a, b) => poseidon2([a, b]), leaves.slice()),
  insert: (tree, leaf) => tree.insert(leaf),
  prove: (tree, index) => tree.generateProof(index),
  verify: (tree, proof) => tree.verifyProof(proof),
};

const skewMmr: Subject<SkewMmr<bigint>, ReturnType<SkewMmr<bigint>["prove"]>> = {
  name: "skew-mmr",
  build(leaves) {
    const mmr = new SkewMmr(poseidonHasher, 64);
    for (const leaf of leaves) mmr.append(leaf);
    return mmr;
  },
  insert: (tree, leaf) => tree.append(leaf),
  prove: (tree, index) => tree.prove(index),
  // The verifier is handed the frontier; reading it is not part of verification.
  verify: (tree, proof, leaf) => verify(poseidonHasher, proof, frontier.roots, frontier.ranks, leaf),
};
/** The frontier of the skew-MMR being verified against, read once per size. */
let frontier: { roots: bigint[]; ranks: number[] } = { roots: [], ranks: [] };

/** Median milliseconds per call of `batch`, repeated for at least `MIN_MS` and `MIN_RUNS`. */
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

/** `count` distinct pseudo-random indices below `n`, the same for every structure. */
function sample(n: number, count: number): number[] {
  let seed = 0x2545f491;
  const picked = new Set<number>();
  while (picked.size < Math.min(count, n)) {
    seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
    picked.add(seed % n);
  }
  return [...picked];
}

const rows = ["structure,leaves,op,us_per_op"];
const log = (name: string, n: number, op: string, us: number) => {
  rows.push(`${name},${n},${op},${us.toFixed(3)}`);
  console.log(`${name.padEnd(12)} ${String(n).padStart(8)} leaves  ${op.padEnd(6)} ${us.toFixed(2).padStart(9)} µs/op`);
};

const all = Array.from({ length: SIZES.at(-1)! + OPS }, (_, i) => BigInt(i + 1));
for (const n of SIZES) {
  const leaves = all.slice(0, n);
  const extra = all.slice(n, n + OPS);
  const indices = sample(n, OPS);

  for (const subject of [binaryImt, quinaryImt, leanImt, skewMmr] as Subject<any, any>[]) {
    const tree = subject.build(leaves);
    if (subject === skewMmr) frontier = { roots: tree.roots(), ranks: tree.ranks() };

    const proofs = indices.map((index) => subject.prove(tree, index));
    proofs.forEach((proof, i) => {
      if (!subject.verify(tree, proof, leaves[indices[i]!]!)) {
        throw new Error(`${subject.name}: proof of ${indices[i]} rejected`);
      }
    });

    log(subject.name, n, "prove", (time(() => indices.forEach((i) => subject.prove(tree, i))) * 1000) / OPS);
    log(subject.name, n, "verify", (time(() => proofs.forEach((p, i) => subject.verify(tree, p, leaves[indices[i]!]!))) * 1000) / OPS);

    // Inserting changes the tree, so this one is timed once, last.
    const t = performance.now();
    for (const leaf of extra) subject.insert(tree, leaf);
    log(subject.name, n, "insert", ((performance.now() - t) * 1000) / OPS);
  }
}

writeFileSync(process.env.OUT ?? new URL("../results/perf-js.csv", import.meta.url), rows.join("\n") + "\n");
