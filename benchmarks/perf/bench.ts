/**
 * Off-chain performance of skew-MMR against zk-kit's IMT and LeanIMT, reproducing the Node.js
 * benchmarks of the LeanIMT paper (https://github.com/zk-kit/zk-kit/tree/main/papers/leanimt),
 * which come from https://github.com/vplasencia/imt-benchmarks (`server/src/insert.ts` and
 * `server/src/all-functions.ts`):
 *
 * - tinybench, `time: 0`, no warmup, the paper's iteration counts (1,000 for insert, 100 for the
 *   other functions) and the paper's hooks. Every iteration adds one member to a growing tree,
 *   and the IMT is rebuilt one level deeper, untimed, whenever it is full.
 * - `poseidon-lite`: `poseidon2` for IMT and LeanIMT, `poseidon3` for skew-MMR.
 *
 * Differences:
 * - Skew-MMR is added. Update and Remove are left out because skew-MMR is append-only.
 * - LeanIMT comes from `@zk-kit/lean-imt` (what Semaphore uses) rather than `@zk-kit/imt`, which
 *   no longer ships it.
 * - tinybench sorts `result.samples` in place, so the paper's "Insert vs Members" line is the
 *   sorted per-insert times. Here each insert is also timed in order, so `perf-js-insert.csv`
 *   really is time against the number of members.
 *
 * Writes `results/perf-js-insert.csv` and `results/perf-js-functions.csv`. Run from
 * `benchmarks/` with Node >= 23.6 (type stripping).
 */
import { writeFileSync } from "node:fs";
import { performance } from "node:perf_hooks";

import { IMT, type IMTMerkleProof } from "@zk-kit/imt";
import { LeanIMT, type LeanIMTMerkleProof } from "@zk-kit/lean-imt";
import { poseidon2 } from "poseidon-lite";
import { Bench } from "tinybench";

import { SkewMmr, poseidonHasher, verify, type Proof } from "../../packages/src/index.ts";

const INSERT_ITERATIONS = 1_000;
const FUNCTION_ITERATIONS = 100;

const imtZeroValue = 0;
const imtArity = 2;
const leanIMTHash = (a: bigint, b: bigint) => poseidon2([a, b]);
const newSkewMmr = () => new SkewMmr(poseidonHasher, 64);

/** The paper's IMT hook: grow the depth, untimed, when `incoming` more leaves would not fit. */
function fitImt(imt: IMT, depth: number, incoming: number): [IMT, number] {
  if (Math.log2(imt.leaves.length + incoming) > depth) {
    depth += 1;
    imt = new IMT(poseidon2, depth, imtZeroValue, imtArity, imt.leaves);
  }
  return [imt, depth];
}

const results = (bench: Bench) =>
  bench.tasks.map((task) => ({ name: task.name, mean: task.result!.mean, samples: task.result!.samples.length }));

/** `server/src/insert.ts`: 1,000 single inserts into one growing tree. */
async function insertBenchmark() {
  const bench = new Bench({ time: 0, iterations: INSERT_ITERATIONS });
  const ordered: Record<string, number[]> = { "binary-imt": [], leanimt: [], "skew-mmr": [] };
  const timed = (name: string, f: () => void) => async () => {
    const t = performance.now();
    f();
    ordered[name]!.push(performance.now() - t);
  };

  let imtDepth = 0;
  let imt: IMT;
  let leanIMT: LeanIMT<bigint>;
  let mmr: SkewMmr<bigint>;

  bench
    .add("IMT - Insert", timed("binary-imt", () => imt.insert(1n)), {
      beforeAll: () => {
        imt = new IMT(poseidon2, imtDepth, imtZeroValue, imtArity);
      },
      beforeEach: () => {
        [imt, imtDepth] = fitImt(imt, imtDepth, 1);
      },
    })
    .add("LeanIMT - Insert", timed("leanimt", () => leanIMT.insert(1n)), {
      beforeAll: () => {
        leanIMT = new LeanIMT(leanIMTHash);
      },
    })
    .add("SkewMMR - Insert", timed("skew-mmr", () => mmr.append(1n)), {
      beforeAll: () => {
        mmr = newSkewMmr();
      },
    });

  await bench.run();
  console.table(results(bench));

  const rows = ["members,binary-imt,leanimt,skew-mmr"];
  for (let i = 0; i < INSERT_ITERATIONS; i++) {
    rows.push([i + 1, ...Object.values(ordered).map((times) => times[i]!.toFixed(5))].join(","));
  }
  writeFileSync(new URL("../results/perf-js-insert.csv", import.meta.url), rows.join("\n") + "\n");
}

/** `server/src/all-functions.ts`, minus Update and Remove: 100 iterations of each function. */
async function functionsBenchmark() {
  const bench = new Bench({ time: 0, iterations: FUNCTION_ITERATIONS });

  let imtDepth: number;
  let imt: IMT;
  let leanIMT: LeanIMT<bigint>;
  let mmr: SkewMmr<bigint>;
  let index: number;
  let members: bigint[];
  let imtProof: IMTMerkleProof;
  let leanProof: LeanIMTMerkleProof<bigint>;
  let skewProof: Proof<bigint>;
  let roots: bigint[];
  let ranks: number[];

  const freshImt = () => {
    imtDepth = 1;
    imt = new IMT(poseidon2, imtDepth, imtZeroValue, imtArity);
  };
  const growImt = () => {
    [imt, imtDepth] = fitImt(imt, imtDepth, 1);
    imt.insert(1n);
    index = Math.floor(imt.leaves.length / 2);
  };
  const growLean = () => {
    leanIMT.insert(1n);
    index = Math.floor(leanIMT.size / 2);
  };
  const growSkew = () => {
    mmr.append(1n);
    index = Math.floor(mmr.len() / 2);
  };

  bench
    // Insert
    .add("IMT - Insert", async () => imt.insert(1n), {
      beforeAll: freshImt,
      beforeEach: () => {
        [imt, imtDepth] = fitImt(imt, imtDepth, 1);
      },
    })
    .add("LeanIMT - Insert", async () => leanIMT.insert(1n), {
      beforeAll: () => {
        leanIMT = new LeanIMT(leanIMTHash);
      },
    })
    .add("SkewMMR - Insert", async () => mmr.append(1n), {
      beforeAll: () => {
        mmr = newSkewMmr();
      },
    })
    // InsertMany: the batch grows by one member each iteration. Only LeanIMT has a batch insert.
    .add(
      "IMT - InsertMany",
      async () => {
        for (const member of members) imt.insert(member);
      },
      {
        beforeAll: () => {
          freshImt();
          members = [];
        },
        beforeEach: () => {
          members.push(1n);
          [imt, imtDepth] = fitImt(imt, imtDepth, members.length);
        },
      },
    )
    .add("LeanIMT - InsertMany", async () => leanIMT.insertMany(members), {
      beforeAll: () => {
        leanIMT = new LeanIMT(leanIMTHash);
        members = [];
      },
      beforeEach: () => {
        members.push(1n);
      },
    })
    .add(
      "SkewMMR - InsertMany",
      async () => {
        for (const member of members) mmr.append(member);
      },
      {
        beforeAll: () => {
          mmr = newSkewMmr();
          members = [];
        },
        beforeEach: () => {
          members.push(1n);
        },
      },
    )
    // GenerateProof
    .add("IMT - GenerateProof", async () => imt.createProof(index), { beforeAll: freshImt, beforeEach: growImt })
    .add("LeanIMT - GenerateProof", async () => leanIMT.generateProof(index), {
      beforeAll: () => {
        leanIMT = new LeanIMT(leanIMTHash);
      },
      beforeEach: growLean,
    })
    .add("SkewMMR - GenerateProof", async () => mmr.prove(index), {
      beforeAll: () => {
        mmr = newSkewMmr();
      },
      beforeEach: growSkew,
    })
    // VerifyProof
    .add("IMT - VerifyProof", async () => imt.verifyProof(imtProof), {
      beforeAll: freshImt,
      beforeEach: () => {
        growImt();
        imtProof = imt.createProof(index);
      },
    })
    .add("LeanIMT - VerifyProof", async () => leanIMT.verifyProof(leanProof), {
      beforeAll: () => {
        leanIMT = new LeanIMT(leanIMTHash);
      },
      beforeEach: () => {
        growLean();
        leanProof = leanIMT.generateProof(index);
      },
    })
    .add("SkewMMR - VerifyProof", async () => verify(poseidonHasher, skewProof, roots, ranks, 1n), {
      beforeAll: () => {
        mmr = newSkewMmr();
      },
      beforeEach: () => {
        growSkew();
        skewProof = mmr.prove(index);
        // The verifier is handed the frontier; reading it is not part of verification.
        roots = mmr.roots();
        ranks = mmr.ranks();
      },
    });

  await bench.run();
  const rows = results(bench);
  console.table(rows);

  const csv = ["function,structure,mean_ms,samples"];
  for (const { name, mean, samples } of rows) {
    const [structure, fn] = name.split(" - ");
    csv.push(`${fn},${structure},${mean.toFixed(5)},${samples}`);
  }
  writeFileSync(new URL("../results/perf-js-functions.csv", import.meta.url), csv.join("\n") + "\n");
}

await insertBenchmark();
await functionsBenchmark();
