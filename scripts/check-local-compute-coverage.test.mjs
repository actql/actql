import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const script = path.join(root, "scripts/check-local-compute-coverage.mjs");
const sourceManifest = path.join(
  root,
  "docs/reviews/2026-09-18-local-compute-coverage.json",
);

function run(manifest) {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), "actql-local-coverage-"),
  );
  const file = path.join(directory, "coverage.json");
  fs.writeFileSync(file, `${JSON.stringify(manifest, null, 2)}\n`);
  const result = spawnSync(process.execPath, [script], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      ACTQL_LOCAL_COMPUTE_COVERAGE_MANIFEST: file,
    },
  });
  fs.rmSync(directory, { recursive: true, force: true });
  return result;
}

function manifest() {
  return JSON.parse(fs.readFileSync(sourceManifest, "utf8"));
}

test("current Local Compute manifest covers the normative RelA mother set", () => {
  const result = run(manifest());
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /29 normative RelA operations/u);
});

test("missing operation cannot silently shrink the mother set", () => {
  const value = manifest();
  value.operations = value.operations.filter(
    (entry) => entry.operation !== "analytic",
  );
  const result = run(value);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /missing normative RelA operation: analytic/u);
});

test("a completed layer requires linked evidence", () => {
  const value = manifest();
  const filter = value.operations.find((entry) => entry.operation === "filter");
  filter.layers.performance = "complete";
  filter.evidence.performance = [];
  const result = run(value);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /complete performance has no linked evidence/u);
});

test("canonical opcodes come from the normative mapping", () => {
  const value = manifest();
  const select = value.operations.find((entry) => entry.operation === "select");
  select.canonical_operations = ["REL.where"];
  const result = run(value);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /canonical operations differ/u);
});

test("invented variants cannot replace the independent normative scope", () => {
  const value = manifest();
  const select = value.operations.find((entry) => entry.operation === "select");
  select.variant_scope = ["imaginary projection"];
  const result = run(value);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /variant_scope differs from the normative scope/u);
});

test("product code cannot stand in for executed fixture evidence", () => {
  const value = manifest();
  const select = value.operations.find((entry) => entry.operation === "select");
  for (const layer of Object.keys(select.layers)) {
    select.layers[layer] = "complete";
  }
  select.gaps = [];
  for (const evidenceName of Object.keys(select.evidence)) {
    select.evidence[evidenceName] = [{
      operation: "select",
      layer: evidenceName,
      path: "src/connectors/local/compute.mbt",
      fixtures: ["product implementation"],
      suite: "moon:connectors",
      targets: ["js", "wasm", "native"],
    }];
  }
  const result = run(value);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /evidence is not a registered test suite/u);
});

test("evidence binds an exact fixture ID suite and execution target", () => {
  for (const [field, replacement, pattern] of [
    ["fixtures", ["not an actual fixture"], /missing fixture ID/u],
    ["suite", "moon:not-the-owning-package", /must use suite/u],
    ["targets", ["unknown-target"], /has invalid target/u],
  ]) {
    const value = manifest();
    const filter = value.operations.find(
      (entry) => entry.operation === "filter",
    );
    filter.evidence.source_connection[0][field] = replacement;
    const result = run(value);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, pattern);
  }
});
