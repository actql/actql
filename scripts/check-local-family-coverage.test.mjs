import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const script = path.join(root, "scripts/check-local-family-coverage.mjs");
const manifestPath = path.join(
  root,
  "docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json",
);

function run(manifest) {
  return spawnSync(process.execPath, [script], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      ACTQL_LOCAL_FAMILY_COVERAGE_MANIFEST: manifest,
    },
  });
}

async function withManifest(t, change) {
  const directory = await mkdtemp(
    path.join(tmpdir(), "actql-local-family-coverage-"),
  );
  t.after(() => rm(directory, { recursive: true, force: true }));
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  change(manifest);
  const target = path.join(directory, "coverage.json");
  await writeFile(target, `${JSON.stringify(manifest, null, 2)}\n`);
  return run(target);
}

test("local family coverage accepts the tracked normative gaps", () => {
  const result = run(manifestPath);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /39 normative entries, 12 complete, 27 open/u);
});

test("local family coverage rejects an omitted normative operation", async t => {
  const result = await withManifest(t, manifest => {
    manifest.operations = manifest.operations.filter(
      entry => entry.operation !== "sequence",
    );
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /manifest is missing TEA operation: sequence/u);
});

test("local family coverage rejects a completion without suite evidence", async t => {
  const result = await withManifest(t, manifest => {
    manifest.operations.find(
      entry => entry.operation === "window_events",
    ).status = "complete";
  });
  assert.notEqual(result.status, 0);
  assert.match(
    result.stderr,
    /complete entry lacks suite evidence: window_events/u,
  );
});

test("local family coverage rejects unexecuted suite evidence", async t => {
  const result = await withManifest(t, manifest => {
    manifest.evidence.find(
      entry => entry.operation === "components",
    ).suites[0].result = "not-run";
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /suite evidence is not passing: components/u);
});

test("local family coverage rejects an unclassified variant surface", async t => {
  const result = await withManifest(t, manifest => {
    manifest.operations.find(
      entry => entry.operation === "nearest",
    ).variants = [];
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /missing formal variant classification: nearest/u);
});
