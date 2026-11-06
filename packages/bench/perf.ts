/**
 * Times insert, prove and verify for skew-MMR, zk-kit's LeanIMT and zk-kit's IMT with tinybench.
 * Each iteration adds one member to a growing tree. Writes `bench/results/perf-js.csv`: each
 * insert's time in order (tinybench sorts its own samples), then the mean of each function.
 */
import { writeFileSync } from "node:fs";
import { performance } from "node:perf_hooks";

import { IMT } from "@zk-kit/imt";
import { LeanIMT } from "@zk-kit/lean-imt";
import { poseidon2 } from "poseidon-lite";
import { Bench } from "tinybench";

import { SkewMmr, poseidonHasher, verify } from "../src/index.ts";

const MEMBERS = 1_024;

interface Subject {
  name: string;
  reset(): void;
  /** Makes room for one more member. Only the IMT needs it: it is rebuilt one level deeper. */
  fit(): void;
  insert(): void;
  /** Proves the middle member. */
  prove(): void;
  /** Proves the middle member, untimed, and returns a function that verifies the proof. */
  verifier(): () => boolean;
}

function binaryImt(): Subject {
  let tree: IMT;
  let depth: number;
  return {
    name: "IMT",
    reset: () => {
      depth = 1;
      tree = new IMT(poseidon2, depth, 0, 2);
    },
    fit: () => {
      if (tree.leaves.length === 2 ** depth) tree = new IMT(poseidon2, ++depth, 0, 2, tree.leaves);
    },
    insert: () => tree.insert(1n),
    prove: () => tree.createProof(tree.leaves.length >> 1),
    verifier: () => {
      const proof = tree.createProof(tree.leaves.length >> 1);
      return () => tree.verifyProof(proof);
    },
  };
}

function leanImt(): Subject {
  let tree: LeanIMT<bigint>;
  return {
    name: "leanIMT",
    reset: () => {
      tree = new LeanIMT((a, b) => poseidon2([a, b]));
    },
    fit: () => {},
    insert: () => tree.insert(1n),
    prove: () => tree.generateProof(tree.size >> 1),
    verifier: () => {
      const proof = tree.generateProof(tree.size >> 1);
      return () => tree.verifyProof(proof);
    },
  };
}

function skewMmr(): Subject {
  let mmr: SkewMmr<bigint>;
  return {
    name: "skew-MMR",
    reset: () => {
      mmr = new SkewMmr(poseidonHasher, 64);
    },
    fit: () => {},
    insert: () => mmr.append(1n),
    prove: () => mmr.prove(mmr.len() >> 1),
    verifier: () => {
      const proof = mmr.prove(mmr.len() >> 1);
      const [roots, ranks] = [mmr.roots(), mmr.ranks()];
      return () => verify(poseidonHasher, proof, roots, ranks, 1n);
    },
  };
}

const bench = new Bench({ time: 0, iterations: MEMBERS });
const inserts: Record<string, number[]> = {};

for (const s of [skewMmr(), leanImt(), binaryImt()]) {
  const times: number[] = (inserts[s.name] = []);
  const grow = () => {
    s.fit();
    s.insert();
  };
  let check: () => boolean;

  bench
    .add(
      `${s.name},Insert`,
      () => {
        const t = performance.now();
        s.insert();
        times.push(performance.now() - t);
      },
      { beforeAll: s.reset, beforeEach: s.fit },
    )
    .add(`${s.name},GenerateProof`, () => s.prove(), { beforeAll: s.reset, beforeEach: grow })
    .add(`${s.name},VerifyProof`, () => check(), {
      beforeAll: s.reset,
      beforeEach: () => {
        grow();
        check = s.verifier();
        if (!check()) throw new Error(`${s.name}: proof rejected`);
      },
    });
}

await bench.run();

const names = Object.keys(inserts);
const rows = [`members,${names.join(",")}`];
for (let i = 0; i < MEMBERS; i++) rows.push([i + 1, ...names.map((n) => inserts[n]![i]!.toFixed(5))].join(","));
rows.push("", "structure,function,mean_ms");
for (const task of bench.tasks) rows.push(`${task.name},${task.result!.mean.toFixed(5)}`);
writeFileSync(new URL("../../bench/results/perf-js.csv", import.meta.url), rows.join("\n") + "\n");
console.table(bench.tasks.map((t) => ({ task: t.name, "mean ms": t.result!.mean })));
