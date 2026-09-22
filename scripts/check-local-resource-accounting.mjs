import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const defaultManifest = path.join(
  root,
  'docs/reviews/2026-09-23-local-resource-accounting-audit.json',
);
const manifestPath = process.env.ACTQL_LOCAL_RESOURCE_AUDIT
  ? path.resolve(process.env.ACTQL_LOCAL_RESOURCE_AUDIT)
  : defaultManifest;
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const manifest = readJson(manifestPath);
const errors = [];
const fail = message => errors.push(message);

if (manifest.version !== 'actql-local-resource-accounting-audit/0.1') {
  fail(`unexpected manifest version: ${manifest.version}`);
}

const inventoryPaths = manifest.inventories ?? {};
const relaPath = path.join(root, inventoryPaths.rela ?? '');
const familyPath = path.join(root, inventoryPaths.families ?? '');
if (!fs.existsSync(relaPath) || !fs.existsSync(familyPath)) {
  fail('both authoritative operation inventories must exist');
}
const rela = fs.existsSync(relaPath) ? readJson(relaPath) : {operations: []};
const families = fs.existsSync(familyPath)
  ? readJson(familyPath)
  : {operations: []};

const requiredFacets = manifest.required_facets ?? [];
const expectedFacets = [
  'admission_before_allocation',
  'charged_bounded_work',
  'finite_stop_observation',
  'temporary_retained_peak_scope',
  'cleanup_owner',
];
if (requiredFacets.length !== expectedFacets.length ||
  expectedFacets.some(facet => !requiredFacets.includes(facet))) {
  fail('required accounting facets do not match the release contract');
}
const requiredPhases = manifest.required_phases ?? [];
const expectedPhases = [
  'prepare',
  'resume',
  'order_or_hash',
  'value_construction',
  'finalize',
  'cancel',
  'cleanup',
];
if (requiredPhases.length !== expectedPhases.length ||
  expectedPhases.some(phase => !requiredPhases.includes(phase))) {
  fail('required execution phases do not match the release contract');
}

const descriptionFields = [
  'work_unit',
  'cumulative_ceiling',
  'temporary_scope',
  'retained_scope',
  'peak_scope',
  'noninterruptible_bound',
  'stop_observation',
  'cleanup_owner',
];
const profiles = manifest.profiles ?? {};
for (const [name, profile] of Object.entries(profiles)) {
  for (const field of descriptionFields) {
    if (typeof profile[field] !== 'string' || profile[field].length < 20) {
      fail(`${name}: missing specific ${field}`);
    }
  }
  const phaseInventory = profile.phase_inventory ?? {};
  for (const phase of requiredPhases) {
    if (typeof phaseInventory[phase] !== 'string' ||
      phaseInventory[phase].length < 30) {
      fail(`${name}: missing specific ${phase} phase accounting`);
    }
  }
  const extraPhases = Object.keys(phaseInventory)
    .filter(phase => !requiredPhases.includes(phase));
  if (extraPhases.length > 0) {
    fail(`${name}: unknown execution phase ${extraPhases[0]}`);
  }
  const sources = profile.sources ?? [];
  if (sources.length === 0 || new Set(sources).size !== sources.length) {
    fail(`${name}: source inventory must be nonempty and unique`);
  }
  for (const source of sources) {
    if (!fs.existsSync(path.join(root, source))) {
      fail(`${name}: missing source ${source}`);
    }
  }
  const covered = new Set();
  const evidence = profile.evidence ?? [];
  if (evidence.length === 0) fail(`${name}: evidence is required`);
  for (const item of evidence) {
    const evidencePath = path.join(root, item.path ?? '');
    if (!item.path || !fs.existsSync(evidencePath)) {
      fail(`${name}: missing evidence file ${item.path}`);
      continue;
    }
    if (typeof item.fixture !== 'string' || item.fixture.length === 0 ||
      !fs.readFileSync(evidencePath, 'utf8').includes(item.fixture)) {
      fail(`${name}: missing fixture ${item.fixture} in ${item.path}`);
    }
    const facets = item.facets ?? [];
    if (facets.length === 0 || new Set(facets).size !== facets.length) {
      fail(`${name}: evidence facets must be nonempty and unique`);
    }
    for (const facet of facets) {
      if (!requiredFacets.includes(facet)) {
        fail(`${name}: unknown accounting facet ${facet}`);
      }
      covered.add(facet);
    }
  }
  for (const facet of requiredFacets) {
    if (!covered.has(facet)) fail(`${name}: missing ${facet} evidence`);
  }
}

const expected = [
  ...rela.operations.map(entry => ({
    inventory: 'rela',
    family: 'RelA',
    operation: entry.operation,
  })),
  ...families.operations.map(entry => ({
    inventory: 'families',
    family: entry.family,
    operation: entry.operation,
  })),
];
const expectedKeys = expected.map(
  entry => `${entry.inventory}:${entry.family}:${entry.operation}`,
);
const actual = [];
for (const binding of manifest.bindings ?? []) {
  if (!profiles[binding.profile]) {
    fail(`binding uses unknown profile ${binding.profile}`);
  }
  const family = binding.inventory === 'rela' ? 'RelA' : binding.family;
  for (const operation of binding.operations ?? []) {
    actual.push({
      inventory: binding.inventory,
      family,
      operation,
      profile: binding.profile,
    });
  }
}
const actualKeys = actual.map(
  entry => `${entry.inventory}:${entry.family}:${entry.operation}`,
);
if (new Set(actualKeys).size !== actualKeys.length) {
  fail('operation bindings must be unique');
}
if (actualKeys.length !== expectedKeys.length ||
  expectedKeys.some((key, index) => actualKeys[index] !== key)) {
  fail('bindings must exactly preserve both authoritative inventories');
}

for (const entry of rela.operations) {
  if (entry.layers?.performance !== 'complete' ||
    (entry.evidence?.performance ?? []).length === 0) {
    fail(`RelA ${entry.operation}: performance evidence is incomplete`);
  }
}
for (const entry of families.operations) {
  const layers = new Set(entry.completed_layers ?? []);
  if (entry.status !== 'complete' || !layers.has('resources') ||
    !layers.has('cancellation')) {
    fail(`${entry.family} ${entry.operation}: resource layers are incomplete`);
  }
}

if (errors.length > 0) {
  for (const error of errors) console.error(error);
  process.exitCode = 1;
} else {
  console.log(
    `Local resource accounting: ${actual.length} operations, ` +
    `${Object.keys(profiles).length} implementation profiles gated.`,
  );
}
