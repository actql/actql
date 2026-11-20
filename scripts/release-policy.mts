import assert from 'node:assert/strict';
import {releaseVersion} from './release-version.mjs';

export interface ReleasePolicy {
  schemaVersion: 'actql-release-policy/0.1';
  allowedLines: string[];
  publicationAuthority: 'external-owner-approval-required';
}

export type ReleaseEcosystem = 'npm' | 'pypi' | 'native';

export interface ReleaseTarget {
  id: string;
  ecosystem: ReleaseEcosystem;
  packages: string[];
  platforms: string[];
  profiles: string[];
  destination: string;
  channels: string[];
}

export interface ReleaseRequest {
  schemaVersion: 'actql-release-request/0.1';
  releaseId: string;
  version: string;
  source: {repository: string; commit: string; branch: string};
  targets: ReleaseTarget[];
  notes: {summary: string; breakingChanges: string[]; migration: string[]; knownLimitations: string[]};
}

function exact<K extends string>(value: unknown, keys: readonly K[]): asserts value is Record<K, unknown> {
  assert(value && typeof value === 'object' && !Array.isArray(value), 'Expected an object');
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort(), 'Unexpected or missing release fields');
}
function text(value: unknown): asserts value is string {
  assert(typeof value === 'string' && value.length &&
    value === value.trim() && !/[\u0000-\u001f\u007f]/u.test(value), 'Expected nonempty literal text');
}
function unique(values: unknown, label: string): asserts values is unknown[] {
  assert(Array.isArray(values) && values.length, `${label} must be explicit and nonempty`);
  assert.equal(new Set(values).size, values.length, `Duplicate ${label}`);
}

export function admitReleaseChannel(value: unknown): string {
  text(value);
  assert.match(value, /^[a-z][a-z0-9.-]*$/u, 'Select one literal release channel');
  return value;
}

// This validates candidate policy DATA for a local plan. Trust in the protected
// policy revision and owner approval belongs to the external release executor.
export function admitReleasePolicy(value: unknown): ReleasePolicy {
  exact(value, ['schemaVersion', 'allowedLines', 'publicationAuthority']);
  assert.equal(value.schemaVersion, 'actql-release-policy/0.1');
  unique(value.allowedLines, 'release lines');
  for (const line of value.allowedLines) {
    text(line);
    assert.match(line, /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/u);
  }
  assert.equal(value.publicationAuthority, 'external-owner-approval-required');
  // All fields and every array member have passed the original guards.
  return structuredClone(value) as ReleasePolicy;
}

export function admitReleaseRequest(value: unknown, policy: unknown) {
  const selectedPolicy = admitReleasePolicy(policy);
  exact(value, ['schemaVersion', 'releaseId', 'version', 'source', 'targets', 'notes']);
  assert.equal(value.schemaVersion, 'actql-release-request/0.1');
  text(value.releaseId);
  assert.match(value.releaseId, /^[a-z0-9][a-z0-9-]{0,127}$/u);
  const version = releaseVersion(value.version);
  assert(selectedPolicy.allowedLines.includes(version.line), `Release line ${version.line} is not allowed`);
  exact(value.source, ['repository', 'commit', 'branch']);
  assert.equal(value.source.repository, 'https://github.com/actql/actql');
  text(value.source.commit);
  assert.match(value.source.commit, /^[a-f0-9]{40}$/u);
  text(value.source.branch);
  assert(!value.source.branch.startsWith('-') && !/[\s~^:?*\[\\]/u.test(value.source.branch),
    'Invalid source branch');
  unique(value.targets, 'targets');
  const targetIds = new Set(), packages = new Set();
  for (const target of value.targets) {
    exact(target, ['id', 'ecosystem', 'packages', 'platforms', 'profiles', 'destination', 'channels']);
    text(target.id);
    assert.match(target.id, /^[a-z0-9][a-z0-9-]{0,127}$/u);
    assert(!targetIds.has(target.id), 'Duplicate target id'); targetIds.add(target.id);
    assert(['npm', 'pypi', 'native'].includes(target.ecosystem as string), 'Unknown release ecosystem');
    for (const field of ['packages', 'platforms', 'profiles'] as const) {
      unique(target[field], field);
      target[field].forEach(text);
    }
    for (const name of target.packages as string[]) {
      const key = `${target.ecosystem}:${name}`;
      assert(!packages.has(key), 'A package cannot be assigned to two target groups'); packages.add(key);
    }
    const destination = {npm: 'https://registry.npmjs.org/', pypi: 'https://upload.pypi.org/legacy/',
      native: 'https://github.com/actql/actql'}[target.ecosystem as ReleaseEcosystem];
    assert.equal(target.destination, destination, 'Destination needs a separately reviewed policy extension');
    assert(Array.isArray(target.channels));
    assert.equal(new Set(target.channels).size, target.channels.length, 'Duplicate channels');
    target.channels.forEach(admitReleaseChannel);
    if (target.ecosystem === 'pypi') assert.equal(target.channels.length, 0, 'PyPI has no npm-style channels');
    else assert(target.channels.length, 'Select release channels explicitly');
  }
  exact(value.notes, ['summary', 'breakingChanges', 'migration', 'knownLimitations']);
  text(value.notes.summary);
  for (const field of ['breakingChanges', 'migration', 'knownLimitations'] as const) {
    assert(Array.isArray(value.notes[field])); value.notes[field].forEach(text);
  }
  if ((value.notes.breakingChanges as string[]).length) assert((value.notes.migration as string[]).length, 'Breaking changes require migration guidance');
  // Keep the original clone rather than reconstructing or normalizing DATA.
  return {request: structuredClone(value) as ReleaseRequest, version};
}

export function releasePlan(request: unknown, policy: unknown) {
  const selected = admitReleaseRequest(request, policy);
  return {qualification: 'local release request validation only; not build, branch admission, registry availability, approval or publication',
    releaseId: selected.request.releaseId, version: selected.version,
    source: selected.request.source, targets: selected.request.targets, notes: selected.request.notes,
    effects: {versionBump: false, build: false, credentials: false, stage: false, upload: false,
      tag: false, channelChange: false},
    pending: ['Exact current cohort/dependency and platform acceptance', 'Fixed artifact and child-manifest bytes/digests',
      'Protected source/policy/executor identity and independent owner approval',
      'Registry history/ownership and exact public install acceptance']};
}
