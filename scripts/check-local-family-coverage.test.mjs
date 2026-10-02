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

function run(manifest, gaps) {
  return spawnSync(process.execPath, [script], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      ACTQL_LOCAL_FAMILY_COVERAGE_MANIFEST: manifest,
      ...(gaps ? { ACTQL_LOCAL_FAMILY_COVERAGE_GAPS: gaps } : {}),
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

test("local family coverage accepts the tracked normative gaps", async () => {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const complete = manifest.operations.filter(
    entry => entry.status === "complete",
  ).length;
  const total = manifest.operations.length;
  const result = run(manifestPath);
  assert.equal(result.status, 0, result.stderr);
  assert.match(
    result.stdout,
    new RegExp(
      `${total} normative entries, ${complete} complete, ` +
        `${total - complete} open`,
      "u",
    ),
  );
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
    manifest.evidence = manifest.evidence.filter(
      entry => entry.operation !== "nearest",
    );
  });
  assert.notEqual(result.status, 0);
  assert.match(
    result.stderr,
    /complete entry lacks suite evidence: nearest/u,
  );
});

test("local family coverage rejects unexecuted suite evidence", async t => {
  const result = await withManifest(t, manifest => {
    manifest.evidence.find(
      entry => entry.operation === "sequence",
    ).suites[0].result = "not-run";
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /suite evidence is not passing: sequence/u);
});

test("current Graph refusal cannot reuse historical completion", async t => {
  const result = await withManifest(t, manifest => {
    manifest.operations.find(entry => entry.operation === "reach").status = "complete";
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /current Graph classification differs for reach/u);
  assert.match(result.stderr, /lacks profile-specific evidence: reach/u);
});

test("current Graph profile cannot be removed or covered by historical suites", async t => {
  const result = await withManifest(t, manifest => {
    delete manifest.current_graph_profile;
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /current Graph profile must identify its source/u);
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

test("local family coverage rejects a stale generated summary", async t => {
  const directory = await mkdtemp(
    path.join(tmpdir(), "actql-local-family-summary-"),
  );
  t.after(() => rm(directory, { recursive: true, force: true }));
  const target = path.join(directory, "coverage.json");
  const gaps = path.join(directory, "gaps.md");
  await writeFile(target, await readFile(manifestPath, "utf8"));
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const complete = manifest.operations.filter(
    entry => entry.status === "complete",
  ).length;
  const total = manifest.operations.length;
  const currentSummary = `| complete operations | ${complete}/${total} |`;
  const staleSummary = `| complete operations | ${complete - 1}/${total} |`;
  const source = await readFile(
    path.join(
      root,
      "docs/reviews/2026-09-19-sga-veca-tea-local-gaps.md",
    ),
    "utf8",
  );
  assert.match(source, new RegExp(currentSummary.replaceAll("|", "\\|"), "u"));
  await writeFile(gaps, source.replace(currentSummary, staleSummary));
  const result = run(target, gaps);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /coverage summary is stale/u);
});
