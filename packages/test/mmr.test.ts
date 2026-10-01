import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { poseidonHasher } from "../src/hasher.ts";
import { SkewMmr } from "../src/mmr.ts";
import { mmr } from "./helpers.ts";

describe("SkewMmr", () => {
  test("ranks decrease except the top pair", () => {
    const accumulator = mmr();
    for (let i = 0; i < 1000; i++) {
      accumulator.append(BigInt(i));

      const ranks = accumulator.ranks();
      for (let j = 0; j + 2 < ranks.length; j++) {
        assert.ok(ranks[j]! > ranks[j + 1]!, `${ranks}`);
      }
      if (ranks.length >= 2) {
        assert.ok(ranks.at(-2)! >= ranks.at(-1)!, `${ranks}`);
      }
    }
  });

  test("tree sizes cover every element", () => {
    const accumulator = mmr();
    for (let i = 0; i < 1000; i++) {
      accumulator.append(BigInt(i));

      const covered = accumulator
        .ranks()
        .reduce((sum, rank) => sum + 2 ** (rank + 1) - 1, 0);
      assert.equal(covered, accumulator.len());
    }
  });

  test("rejects overflowing max depth", () => {
    const shallow = new SkewMmr(poseidonHasher, 3);
    assert.throws(() => {
      for (let i = 0; i < 1000; i++) {
        shallow.append(BigInt(i));
      }
    }, /stack is full/);
  });
});
