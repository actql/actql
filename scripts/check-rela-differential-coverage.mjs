import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const manifestPath = process.env.ACTQL_RELA_DIFFERENTIAL_MANIFEST
  ? path.resolve(process.env.ACTQL_RELA_DIFFERENTIAL_MANIFEST)
  : path.join(root, 'docs/reviews/2026-09-23-rela-differential-coverage.json');
const normativePath = path.join(
  root,
  'docs/reviews/2026-09-18-local-compute-coverage.json',
);

const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const manifest = readJson(manifestPath);
const normative = readJson(normativePath);
const errors = [];
const fail = message => errors.push(message);
const allowedSupport = new Set(['overlap', 'no_registered_overlap']);
const expectedOverlap = new Set(['filter', 'select', 'sort', 'take', 'join', 'group']);
const requiredRoles = [
  role => role.includes('independent_expectation'),
  role => role.includes('canonical_comparison') || role.includes('all_placements'),
];

if (manifest.version !== 'actql-rela-differential-coverage/0.1') {
  fail(`unexpected manifest version: ${manifest.version}`);
}
if (manifest.normative_inventory !==
  'docs/reviews/2026-09-18-local-compute-coverage.json') {
  fail('manifest must bind the normative RelA inventory');
}

const normativeNames = normative.operations.map(entry => entry.operation);
const entries = manifest.operations ?? [];
const names = entries.map(entry => entry.operation);
if (new Set(names).size !== names.length) fail('operation entries must be unique');
if (names.length !== normativeNames.length ||
  normativeNames.some((name, index) => names[index] !== name)) {
  fail('operation entries must exactly preserve the normative RelA order');
}

const observed = new Set();
for (const entry of entries) {
  const label = entry.operation;
  if (!allowedSupport.has(entry.support)) {
    fail(`${label}: invalid support classification`);
    continue;
  }
  const expected = expectedOverlap.has(label) ? 'overlap' : 'no_registered_overlap';
  if (entry.support !== expected) {
    fail(`${label}: expected ${expected}, found ${entry.support}`);
  }
  if (entry.support === 'no_registered_overlap') {
    if (typeof entry.reason !== 'string' || entry.reason.length < 20) {
      fail(`${label}: non-overlap requires a specific reason`);
    }
    if (entry.evidence !== undefined || entry.observations !== undefined) {
      fail(`${label}: non-overlap must not claim differential evidence`);
    }
    continue;
  }
  if (typeof entry.scope !== 'string' || entry.scope.length < 20) {
    fail(`${label}: overlapping scope must be explicit`);
  }
  const observations = entry.observations ?? [];
  if (observations.length === 0 || new Set(observations).size !== observations.length) {
    fail(`${label}: observations must be nonempty and unique`);
  }
  for (const observation of observations) observed.add(observation);
  const evidence = entry.evidence ?? [];
  if (evidence.length < 2) fail(`${label}: at least two implementations are required`);
  const roles = evidence.map(item => item.role ?? '');
  for (const required of requiredRoles) {
    if (!roles.some(required)) fail(`${label}: required differential role is missing`);
  }
  for (const item of evidence) {
    const file = path.join(root, item.path ?? '');
    if (!item.path || !fs.existsSync(file)) {
      fail(`${label}: missing evidence file ${item.path}`);
      continue;
    }
    if (typeof item.fixture !== 'string' || item.fixture.length === 0 ||
      !fs.readFileSync(file, 'utf8').includes(item.fixture)) {
      fail(`${label}: missing fixture ${item.fixture} in ${item.path}`);
    }
    if (typeof item.role !== 'string' || item.role.length === 0) {
      fail(`${label}: evidence role is required`);
    }
  }
}

const publication = manifest.publication_evidence ?? {};
const publicationPath = path.join(root, publication.path ?? '');
if (!publication.path || !fs.existsSync(publicationPath) ||
  typeof publication.fixture !== 'string' ||
  !fs.readFileSync(publicationPath, 'utf8').includes(publication.fixture)) {
  fail('publication evidence must name an executed standard Host fixture');
}
for (const observation of publication.observations ?? []) observed.add(observation);

const requiredObservations = manifest.required_observations ?? [];
if (new Set(requiredObservations).size !== requiredObservations.length) {
  fail('required observations must be unique');
}
for (const observation of requiredObservations) {
  if (!observed.has(observation)) fail(`missing observation coverage: ${observation}`);
}

if (errors.length > 0) {
  for (const error of errors) console.error(error);
  process.exitCode = 1;
} else {
  console.log(
    `RelA differential coverage: ${entries.length} classified, ` +
    `${expectedOverlap.size} overlapping operations gated.`,
  );
}
