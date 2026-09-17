import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = process.env.ACTQL_LOCAL_COMPUTE_COVERAGE_MANIFEST
  ? path.resolve(process.env.ACTQL_LOCAL_COMPUTE_COVERAGE_MANIFEST)
  : path.join(
      root,
      "docs/reviews/2026-09-18-local-compute-coverage.json",
    );
const languagePath = path.join(root, "docs/spec/language.md");
const registryPath = path.join(
  root,
  "spec/dependencies/aoa-pipeline-registry.json",
);
const contractPath = path.join(root, "spec/contracts/actql-aoa.json");

function readText(file) {
  return fs.readFileSync(file, "utf8");
}

function readJson(file) {
  return JSON.parse(readText(file));
}

function tableAfter(text, marker) {
  const start = text.indexOf(marker);
  if (start < 0) {
    throw new Error(`missing normative marker: ${marker}`);
  }
  const lines = text.slice(start + marker.length).split(/\r?\n/u);
  const rows = [];
  let tableStarted = false;
  for (const line of lines) {
    if (!line.startsWith("|")) {
      if (tableStarted) break;
      continue;
    }
    tableStarted = true;
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
  if (rows.length === 0) {
    throw new Error(`normative marker has no table: ${marker}`);
  }
  return rows;
}

function codeSpans(cell) {
  return [...cell.matchAll(/`([^`]+)`/gu)].map((match) => match[1]);
}

function sourceOperation(name) {
  if (name.startsWith("assert_rows.")) return "assert_rows";
  return name;
}

function sameStrings(actual, expected) {
  return (
    actual.length === expected.length &&
    actual.every((value, index) => value === expected[index])
  );
}

function fail(errors, message) {
  errors.push(message);
}

const language = readText(languagePath);
const inventoryRows = tableAfter(
  language,
  "<!-- requirement-block: operation-inventory.family-operation-input-output -->",
);
const normativeOperations = [];
for (const row of inventoryRows) {
  if (row[0] !== "RelA") continue;
  normativeOperations.push(...codeSpans(row[1]));
}

const mappingRows = tableAfter(
  language,
  "<!-- requirement-block: algebra-lowering.actql-surface-form-canonical-aoa-registry-operation -->",
);
const canonicalBySource = new Map();
for (const row of mappingRows) {
  const sources = [...new Set(codeSpans(row[0]).map(sourceOperation))];
  const canonical = codeSpans(row[1]);
  if (sources.length > 1 && sources.length === canonical.length) {
    for (let index = 0; index < sources.length; index += 1) {
      canonicalBySource.set(sources[index], [canonical[index]]);
    }
  } else {
    for (const source of sources) {
      canonicalBySource.set(source, canonical);
    }
  }
}

const manifest = readJson(manifestPath);
const registry = readJson(registryPath);
const contract = readJson(contractPath);
const registered = new Set(Object.keys(registry));
const targetRequirements = new Set(
  Object.keys(contract.target_registry_requirements ?? {}),
);
const errors = [];

if (manifest.version !== "actql-local-compute-coverage/0.1") {
  fail(errors, `unexpected manifest version: ${manifest.version}`);
}
if (manifest.baseline !== "5a305f3ce5cdac421985fb9a71878bc22af51237") {
  fail(errors, `unexpected fixed baseline: ${manifest.baseline}`);
}
if (manifest.family !== "RelA") {
  fail(errors, `unexpected family: ${manifest.family}`);
}
if (!sameStrings(manifest.targets ?? [], ["js", "wasm", "native"])) {
  fail(errors, "targets must be exactly js, wasm, native");
}

const normativeSet = new Set(normativeOperations);
const entries = manifest.operations ?? [];
const entryNames = entries.map((entry) => entry.operation);
const entrySet = new Set(entryNames);

if (normativeOperations.length !== 29 || normativeSet.size !== 29) {
  fail(
    errors,
    `normative RelA inventory must contain 29 distinct operations; found ${normativeOperations.length}/${normativeSet.size}`,
  );
}
if (entries.length !== 29 || entrySet.size !== 29) {
  fail(
    errors,
    `manifest must contain 29 distinct operations; found ${entries.length}/${entrySet.size}`,
  );
}
for (const operation of normativeSet) {
  if (!entrySet.has(operation)) {
    fail(errors, `manifest is missing normative RelA operation: ${operation}`);
  }
}
for (const operation of entrySet) {
  if (!normativeSet.has(operation)) {
    fail(errors, `manifest contains non-normative RelA operation: ${operation}`);
  }
}

const allowedLayerStates = new Set(manifest.layer_states ?? []);
const requiredLayers = manifest.required_layers ?? [];
const evidenceForLayer = new Map([
  ["source_connection", "source_connection"],
  ["two_consumer_e2e", "two_consumer_e2e"],
  ["three_target_conformance", "conformance"],
  ["performance", "performance"],
]);

for (const entry of entries) {
  const label = entry.operation;
  if (typeof entry.input_shape !== "string" || entry.input_shape.length === 0) {
    fail(errors, `${label}: input_shape is required`);
  }
  if (
    typeof entry.normative_anchor !== "string" ||
    entry.normative_anchor.length === 0
  ) {
    fail(errors, `${label}: normative_anchor is required`);
  }
  if (!Array.isArray(entry.variant_scope) || entry.variant_scope.length === 0) {
    fail(errors, `${label}: variant_scope must not be empty`);
  }
  if (
    entry.variant_scope?.some(
      (variant) => typeof variant !== "string" || variant.length === 0,
    )
  ) {
    fail(errors, `${label}: variant_scope contains an invalid value`);
  }

  const normativeCanonical = canonicalBySource.get(label);
  if (normativeCanonical === undefined) {
    if (entry.machine_registry !== "canonical-mapping-gap") {
      fail(
        errors,
        `${label}: missing canonical mapping must be an explicit canonical-mapping-gap`,
      );
    }
    if (!sameStrings(entry.canonical_operations ?? [], [])) {
      fail(errors, `${label}: canonical mapping gap must not invent an opcode`);
    }
  } else if (
    !sameStrings(entry.canonical_operations ?? [], normativeCanonical)
  ) {
    fail(
      errors,
      `${label}: canonical operations differ from the normative table; expected ${normativeCanonical.join(", ")}`,
    );
  } else {
    const absent = normativeCanonical.filter((opcode) => !registered.has(opcode));
    const targetOnly = absent.filter((opcode) => targetRequirements.has(opcode));
    const expectedRegistryState =
      absent.length === 0
        ? "registered"
        : targetOnly.length === absent.length
          ? "target-requirement-only"
          : "missing";
    if (entry.machine_registry !== expectedRegistryState) {
      fail(
        errors,
        `${label}: machine_registry is ${entry.machine_registry}; expected ${expectedRegistryState}`,
      );
    }
  }

  if (entry.layers === null || typeof entry.layers !== "object") {
    fail(errors, `${label}: layers object is required`);
    continue;
  }
  for (const layer of requiredLayers) {
    const state = entry.layers[layer];
    if (!allowedLayerStates.has(state)) {
      fail(errors, `${label}: ${layer} has unclassified state ${state}`);
    }
  }
  for (const layer of Object.keys(entry.layers)) {
    if (!requiredLayers.includes(layer)) {
      fail(errors, `${label}: unknown layer ${layer}`);
    }
  }

  if (entry.evidence === null || typeof entry.evidence !== "object") {
    fail(errors, `${label}: evidence object is required`);
    continue;
  }
  for (const evidenceName of evidenceForLayer.values()) {
    const files = entry.evidence[evidenceName];
    if (!Array.isArray(files)) {
      fail(errors, `${label}: evidence.${evidenceName} must be an array`);
      continue;
    }
    for (const file of files) {
      const resolved = path.join(root, file);
      if (
        typeof file !== "string" ||
        path.isAbsolute(file) ||
        !fs.existsSync(resolved) ||
        !fs.statSync(resolved).isFile()
      ) {
        fail(errors, `${label}: evidence file does not exist: ${file}`);
      }
    }
  }
  for (const [layer, evidenceName] of evidenceForLayer) {
    if (
      entry.layers[layer] === "complete" &&
      (entry.evidence[evidenceName]?.length ?? 0) === 0
    ) {
      fail(errors, `${label}: complete ${layer} has no linked evidence`);
    }
  }

  const incomplete = requiredLayers.some(
    (layer) => entry.layers[layer] !== "complete",
  );
  if (incomplete && (!Array.isArray(entry.gaps) || entry.gaps.length === 0)) {
    fail(errors, `${label}: incomplete coverage requires an explicit gap`);
  }
  if (
    !incomplete &&
    (entry.gaps?.length ?? 0) !== 0
  ) {
    fail(errors, `${label}: fully complete coverage must not retain gap text`);
  }
}

if (errors.length > 0) {
  console.error("Local Compute coverage check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exitCode = 1;
} else {
  const complete = entries.filter((entry) =>
    requiredLayers.every((layer) => entry.layers[layer] === "complete"),
  ).length;
  console.log(
    `Local Compute coverage: ${entries.length} normative RelA operations, ${complete} complete, ${entries.length - complete} explicit gaps.`,
  );
}
