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
const normativeScopePath = path.join(
  root,
  "docs/reviews/2026-09-18-local-compute-normative-scope.json",
);

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
const normativeScope = readJson(normativeScopePath);
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
if (
  manifest.normative_sources?.scope !==
  "docs/reviews/2026-09-18-local-compute-normative-scope.json"
) {
  fail(errors, "manifest must pin the independent normative scope");
}
if (
  normativeScope.version !== "actql-local-compute-normative-scope/0.1" ||
  normativeScope.baseline !== manifest.baseline ||
  normativeScope.family !== manifest.family
) {
  fail(errors, "independent normative scope does not match the fixed baseline");
}

const normativeSet = new Set(normativeOperations);
const entries = manifest.operations ?? [];
const entryNames = entries.map((entry) => entry.operation);
const entrySet = new Set(entryNames);
const scopeEntries = normativeScope.operations ?? [];
const scopeByOperation = new Map(
  scopeEntries.map((entry) => [entry.operation, entry]),
);
const typeSets = new Set(Object.keys(normativeScope.type_sets ?? {}));
const obligations = new Set(normativeScope.obligations ?? []);

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
if (scopeEntries.length !== 29 || scopeByOperation.size !== 29) {
  fail(errors, "independent normative scope must contain 29 operations");
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

function expectedSuite(file) {
  const moon = file.match(/^src\/([^/]+)\/.*_(?:wb)?test\.mbt$/u);
  if (moon !== null) return `moon:${moon[1]}`;
  if (file === "adapters/connectors/duckdb/node/test/standard-host.test.mjs") {
    return "node:standard-host";
  }
  if (/^(?:benchmarks\/|adapters\/[^/]+\/bench\/)/u.test(file)) {
    return "benchmark:local-compute";
  }
  return undefined;
}

function fixtureIds(source) {
  return new Set(
    [...source.matchAll(
      /(?:^|\n)\s*test(?:\s+|\(\s*)["']([^"']+)["']/gu,
    )]
      .map((match) => match[1]),
  );
}

function addCoverage(target, values) {
  if (!Array.isArray(values)) return;
  for (const value of values) target.add(value);
}

for (const entry of entries) {
  const label = entry.operation;
  const scope = scopeByOperation.get(label);
  if (scope === undefined) {
    fail(errors, `${label}: independent normative scope is missing`);
  } else {
    if (!sameStrings(entry.variant_scope ?? [], scope.variants ?? [])) {
      fail(errors, `${label}: variant_scope differs from the normative scope`);
    }
    if (!Array.isArray(scope.types) || scope.types.length === 0) {
      fail(errors, `${label}: normative type scope must not be empty`);
    } else {
      for (const type of scope.types) {
        if (!typeSets.has(type)) {
          fail(errors, `${label}: unknown normative type set ${type}`);
        }
      }
    }
    if (!Array.isArray(scope.obligations) || scope.obligations.length === 0) {
      fail(errors, `${label}: normative obligations must not be empty`);
    } else {
      for (const obligation of scope.obligations) {
        if (!obligations.has(obligation)) {
          fail(errors, `${label}: unknown normative obligation ${obligation}`);
        }
      }
    }
  }
  if (typeof entry.input_shape !== "string" || entry.input_shape.length === 0) {
    fail(errors, `${label}: input_shape is required`);
  }
  if (
    typeof entry.normative_anchor !== "string" ||
    entry.normative_anchor.length === 0
  ) {
    fail(errors, `${label}: normative_anchor is required`);
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
  const scopedCoverage = {
    variants: new Set(),
    types: new Set(),
    obligations: new Set(),
  };
  for (const evidenceName of evidenceForLayer.values()) {
    const records = entry.evidence[evidenceName];
    if (!Array.isArray(records)) {
      fail(errors, `${label}: evidence.${evidenceName} must be an array`);
      continue;
    }
    for (const record of records) {
      if (record === null || typeof record !== "object" || Array.isArray(record)) {
        fail(errors, `${label}: evidence.${evidenceName} must use fixture records`);
        continue;
      }
      const file = record.path;
      const resolved = typeof file === "string"
        ? path.resolve(root, file)
        : "";
      if (
        typeof file !== "string" ||
        path.isAbsolute(file) ||
        !resolved.startsWith(`${root}${path.sep}`) ||
        !fs.existsSync(resolved) ||
        !fs.statSync(resolved).isFile()
      ) {
        fail(errors, `${label}: evidence file does not exist: ${file}`);
        continue;
      }
      const suite = expectedSuite(file);
      if (suite === undefined) {
        fail(errors, `${label}: evidence is not a registered test suite: ${file}`);
      } else if (record.suite !== suite) {
        fail(errors, `${label}: ${file} must use suite ${suite}`);
      }
      if (record.operation !== label || record.layer !== evidenceName) {
        fail(errors, `${label}: evidence owner or layer mismatch for ${file}`);
      }
      if (!Array.isArray(record.targets) || record.targets.length === 0) {
        fail(errors, `${label}: ${file} must bind at least one execution target`);
      } else {
        const allowedTargets = suite?.startsWith("moon:")
          ? new Set(manifest.targets)
          : new Set(["node"]);
        for (const target of record.targets) {
          if (!allowedTargets.has(target)) {
            fail(errors, `${label}: ${file} has invalid target ${target}`);
          }
        }
      }
      if (!Array.isArray(record.fixtures) || record.fixtures.length === 0) {
        fail(errors, `${label}: ${file} must bind an explicit fixture ID`);
      } else {
        const actual = fixtureIds(readText(resolved));
        for (const fixture of record.fixtures) {
          if (typeof fixture !== "string" || !actual.has(fixture)) {
            fail(errors, `${label}: missing fixture ID in ${file}: ${fixture}`);
          }
        }
      }
      addCoverage(scopedCoverage.variants, record.covers?.variants);
      addCoverage(scopedCoverage.types, record.covers?.types);
      addCoverage(scopedCoverage.obligations, record.covers?.obligations);
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
  if (!incomplete && scope !== undefined) {
    for (const [axis, required] of [
      ["variants", scope.variants],
      ["types", scope.types],
      ["obligations", scope.obligations],
    ]) {
      const actual = scopedCoverage[axis];
      for (const value of required) {
        if (!actual.has(value)) {
          fail(errors, `${label}: complete coverage lacks ${axis} claim ${value}`);
        }
      }
      for (const value of actual) {
        if (!required.includes(value)) {
          fail(errors, `${label}: evidence invents non-normative ${axis} ${value}`);
        }
      }
    }
  }
  if (entry.layers.two_consumer_e2e === "complete") {
    const hostEvidence = entry.evidence.two_consumer_e2e.some(
      (record) => record.standard_host === true &&
        record.suite === "node:standard-host",
    );
    if (!hostEvidence) {
      fail(errors, `${label}: complete two_consumer_e2e lacks standard Host evidence`);
    }
  }
  if (entry.layers.three_target_conformance === "complete") {
    const targets = new Set(
      entry.evidence.conformance.flatMap((record) => record.targets ?? []),
    );
    for (const target of manifest.targets) {
      if (!targets.has(target)) {
        fail(errors, `${label}: conformance lacks target ${target}`);
      }
    }
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
