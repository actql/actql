import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = process.env.ACTQL_LOCAL_FAMILY_COVERAGE_MANIFEST
  ? path.resolve(process.env.ACTQL_LOCAL_FAMILY_COVERAGE_MANIFEST)
  : path.join(
      root,
      "docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json",
    );
const languagePath = path.join(root, "docs/spec/language.md");
const expressionContractPath = path.join(
  root,
  "spec/contracts/actql-expressions.json",
);
const gapsPath = process.env.ACTQL_LOCAL_FAMILY_COVERAGE_GAPS
  ? path.resolve(process.env.ACTQL_LOCAL_FAMILY_COVERAGE_GAPS)
  : path.join(
      root,
      "docs/reviews/2026-09-19-sga-veca-tea-local-gaps.md",
    );
const summaryStart = "<!-- local-family-coverage-summary:start -->";
const summaryEnd = "<!-- local-family-coverage-summary:end -->";

function readText(file) {
  return fs.readFileSync(file, "utf8");
}

function readJson(file) {
  return JSON.parse(readText(file));
}

function codeSpans(cell) {
  return [...cell.matchAll(/`([^`]+)`/gu)].map((match) => match[1]);
}

function tableAfter(text, marker) {
  const start = text.indexOf(marker);
  if (start < 0) throw new Error(`missing normative marker: ${marker}`);
  const rows = [];
  let started = false;
  for (const line of text.slice(start + marker.length).split(/\r?\n/u)) {
    if (!line.startsWith("|")) {
      if (started) break;
      continue;
    }
    started = true;
    const cells = line
      .slice(1, -1)
      .split("|")
      .map((cell) => cell.trim());
    if (
      cells.every((cell) => /^:?-+:?$/u.test(cell)) ||
      cells[0] === "Family" ||
      cells[0] === "ActQL surface form"
    ) {
      continue;
    }
    rows.push(cells);
  }
  if (rows.length === 0) throw new Error(`empty normative table: ${marker}`);
  return rows;
}

function normalizedSources(cell) {
  const sources = codeSpans(cell);
  if (cell.includes("fixed/sliding `window_events`")) return ["window_events"];
  return sources;
}

const language = readText(languagePath);
const inventoryRows = tableAfter(
  language,
  "<!-- requirement-block: operation-inventory.family-operation-input-output -->",
);
const mappingRows = tableAfter(
  language,
  "<!-- requirement-block: algebra-lowering.actql-surface-form-canonical-aoa-registry-operation -->",
);
const manifest = readJson(manifestPath);
const expressions = readJson(expressionContractPath);
const errors = [];

const expectedFamilies = new Map([
  ["SGA", 17],
  ["TEA", 8],
  ["VecA", 5],
  ["Bridge", 8],
  ["VecAExpression", 2],
]);
const normative = new Map();
for (const row of inventoryRows) {
  if (!expectedFamilies.has(row[0]) || row[0] === "VecAExpression") continue;
  for (const operation of codeSpans(row[1])) {
    normative.set(operation, row[0]);
  }
}
normative.set("vector_score", "VecAExpression");
normative.set("vector_concat", "VecAExpression");

const mapping = new Map();
for (const row of mappingRows) {
  const canonical = codeSpans(row[1]);
  for (const operation of normalizedSources(row[0])) {
    mapping.set(operation, canonical);
  }
}

function fail(message) {
  errors.push(message);
}

if (manifest.version !== "actql-local-family-coverage/0.1") {
  fail(`unexpected manifest version: ${manifest.version}`);
}
if (manifest.baseline !== "0886df5ab75ff77edcd68291470f487346fc1cc4") {
  fail(`unexpected baseline: ${manifest.baseline}`);
}
if (JSON.stringify(manifest.targets) !== JSON.stringify(["js", "wasm", "native"])) {
  fail("targets must be exactly js, wasm, native");
}

const entries = manifest.operations ?? [];
const entryNames = new Set();
const states = new Set(manifest.states ?? []);
const counts = new Map([...expectedFamilies].map(([family]) => [family, 0]));
for (const entry of entries) {
  if (entryNames.has(entry.operation)) {
    fail(`duplicate manifest operation: ${entry.operation}`);
  }
  entryNames.add(entry.operation);
  const expectedFamily = normative.get(entry.operation);
  if (expectedFamily === undefined) {
    fail(`non-normative manifest operation: ${entry.operation}`);
  } else if (expectedFamily !== entry.family) {
    fail(
      `wrong family for ${entry.operation}: ${entry.family}, expected ${expectedFamily}`,
    );
  }
  counts.set(entry.family, (counts.get(entry.family) ?? 0) + 1);
  if (!states.has(entry.status)) {
    fail(`invalid status for ${entry.operation}: ${entry.status}`);
  }
  if (!Array.isArray(entry.variants) || entry.variants.length === 0) {
    fail(`missing formal variant classification: ${entry.operation}`);
  }
  if (typeof entry.owner !== "string" || entry.owner.length === 0) {
    fail(`missing owner: ${entry.operation}`);
  }
  if (entry.status === "blocked" && !entry.blocker) {
    fail(`blocked entry lacks blocker: ${entry.operation}`);
  }
  if (entry.family !== "VecAExpression") {
    const expectedCanonical = mapping.get(entry.operation);
    if (expectedCanonical === undefined) {
      fail(`normative mapping missing for ${entry.operation}`);
    } else if (
      JSON.stringify(entry.canonical) !== JSON.stringify(expectedCanonical)
    ) {
      fail(
        `canonical mapping differs for ${entry.operation}: ` +
          `${JSON.stringify(entry.canonical)} != ${JSON.stringify(expectedCanonical)}`,
      );
    }
  }
}

for (const [operation, family] of normative) {
  if (!entryNames.has(operation)) {
    fail(`manifest is missing ${family} operation: ${operation}`);
  }
}
for (const [family, expected] of expectedFamilies) {
  const actual = counts.get(family) ?? 0;
  if (actual !== expected) {
    fail(`${family} must contain ${expected} entries; found ${actual}`);
  }
}

const vectorSignatures =
  expressions.profile_extensions?.["actql-veca/0.1"]?.signatures ?? {};
for (const expression of ["vector_score", "vector_concat"]) {
  if (!(expression in vectorSignatures)) {
    fail(`expression contract is missing ${expression}`);
  }
}

const complete = entries.filter((entry) => entry.status === "complete");
const summaryLayers = [
  "contract",
  "checker",
  "lowering",
  "kernel",
  "managed",
  "standard_host",
  "consumer_lifetime",
  "resources",
  "cancellation",
  "publication",
  "three_targets",
];
const layerCounts = new Map(
  summaryLayers.map(layer => [
    layer,
    entries.filter(entry => (entry.completed_layers ?? []).includes(layer))
      .length,
  ]),
);
const summary = [
  summaryStart,
  "| Coverage state | Count |",
  "|---|---:|",
  ...summaryLayers.map(
    layer => `| \`${layer}\` | ${layerCounts.get(layer)}/${entries.length} |`,
  ),
  `| complete operations | ${complete.length}/${entries.length} |`,
  `| open operations | ${entries.length - complete.length}/${entries.length} |`,
  summaryEnd,
].join("\n");
if (
  !process.env.ACTQL_LOCAL_FAMILY_COVERAGE_MANIFEST ||
  process.env.ACTQL_LOCAL_FAMILY_COVERAGE_GAPS
) {
  const gaps = readText(gapsPath);
  const start = gaps.indexOf(summaryStart);
  const end = gaps.indexOf(summaryEnd);
  if (start < 0 || end < start) {
    fail("gaps ledger lacks the generated coverage summary markers");
  } else {
    const current = gaps.slice(start, end + summaryEnd.length);
    if (process.argv.includes("--write-summary")) {
      fs.writeFileSync(
        gapsPath,
        gaps.slice(0, start) + summary + gaps.slice(end + summaryEnd.length),
      );
    } else if (current !== summary) {
      fail(
        "gaps ledger coverage summary is stale; run " +
          "node scripts/check-local-family-coverage.mjs --write-summary",
      );
    }
  }
}
const evidence = manifest.evidence ?? [];
for (const entry of complete) {
  const linked = evidence.find((item) => item.operation === entry.operation);
  if (!linked) {
    fail(`complete entry lacks suite evidence: ${entry.operation}`);
    continue;
  }
  if (typeof linked.sha !== "string" || linked.sha.length === 0) {
    fail(`suite evidence lacks a fixed SHA: ${entry.operation}`);
  }
  if (!Array.isArray(linked.suites) || linked.suites.length === 0) {
    fail(`suite evidence lacks executed suites: ${entry.operation}`);
    continue;
  }
  for (const suite of linked.suites) {
    if (suite.result !== "passed") {
      fail(`suite evidence is not passing: ${entry.operation}`);
    }
    if (
      typeof suite.path !== "string" ||
      !fs.existsSync(path.join(root, suite.path))
    ) {
      fail(`suite evidence path is missing: ${entry.operation}`);
    }
    if (!Array.isArray(suite.targets) || suite.targets.length === 0) {
      fail(`suite evidence lacks targets: ${entry.operation}`);
    }
  }
}

if (errors.length > 0) {
  for (const error of errors) console.error(`Local family coverage: ${error}`);
  process.exitCode = 1;
} else {
  console.log(
    `Local family coverage: ${entries.length} normative entries, ` +
      `${complete.length} complete, ${entries.length - complete.length} open.`,
  );
}
