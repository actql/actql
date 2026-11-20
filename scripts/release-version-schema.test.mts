import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';
import {releaseVersion} from './release-version.mjs';
import {admitReleaseChannel} from './release-policy.mjs';

function assertReadyLintProfiles(step) {
  const condition = (step.if ?? 'true').replace(/^\$\{\{\s*|\s*\}\}$/gu, '')
    .replace(/needs\.([a-z][a-z0-9-]*)/gu, (_, name) => `needs[${JSON.stringify(name)}]`);
  assert(!/\b(?:always|failure|cancelled)\s*\(/u.test(condition), 'Keep the implicit success prerequisite');
  assert.equal(step['continue-on-error'], undefined);
  for (const profile of ['full', 'maintenance', 'focused-tests', 'draft', 'draft-focused', 'documentation'])
    assert.equal(runInNewContext(condition, {needs: {'select-targets': {outputs: {profile}}},
      startsWith: (value, prefix) => value.startsWith(prefix)}, {timeout: 100}),
    ['full', 'maintenance', 'focused-tests'].includes(profile), profile);
}

test('actual schema version regex and shared parser match independent literal version oracles', () => {
  const schema = JSON.parse(readFileSync(new URL('../release/release-request.schema.json', import.meta.url)));
  const pattern = new RegExp(schema.properties.version.pattern, 'u');
  // Syntax acceptance is independent of the separately enforced allowed line.
  const supported = ['0.0.0', '0.0.7', '0.0.19-alpha.0', '0.0.19-alpha.12',
    '0.0.19-beta.1', '0.0.19-rc.3', '0.1.0', '0.1.0-alpha.1', '1.2.3'];
  const invalid = ['patch', 'v0.0.7', '0.0', '0x0x7', '00.0.7', '0.00.7', '0.0.07',
    '0.0.7-alpha', '0.0.7-alpha.01', '0.0.7-rc.-1', '0.0.7-preview.1', '0.0.7+build.1',
    '0.0.7a1', ' 0.0.7', '0.0.7 ', '0.0.7\n', '0.0.7\r\n', '0.0.7\u0000'];
  for (const version of supported) {
    assert.equal(pattern.test(version), true, `schema ${JSON.stringify(version)}`);
    assert.equal(releaseVersion(version).version, version);
  }
  for (const version of invalid) {
    assert.equal(pattern.test(version), false, `schema ${JSON.stringify(version)}`);
    assert.throws(() => releaseVersion(version), undefined, `shared ${JSON.stringify(version)}`);
  }
  assert.equal(supported.length + invalid.length, 27);
});

test('existing public lint selects the release files without new publication authority', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const job = workflow.jobs.lint;
  assert.deepEqual(workflow.jobs['native-workloads'].steps.find(step => step.name === 'Test immutable Native package-version C mechanism'),
    {name: 'Test immutable Native package-version C mechanism', run: 'node --test scripts/native-cli-version-native.test.mjs'});
  assert.deepEqual(job.needs, ['select-targets']);
  assert.equal(job.if, "${{ github.event.repository.visibility == 'public' && toJSON(github.event.repository.private) == 'false' && !inputs.performance_matrix && !inputs.packed_query_evidence_probe }}");
  const selected = job.steps.filter(step => step.name === 'Test explicit release policy and publication refusal');
  assert.equal(selected.length, 1);
  const [step] = selected;
  assertReadyLintProfiles(step);
  assert.equal(step['continue-on-error'], undefined);
  const args = step.run.trim().split(/\s+/u);
  assert.deepEqual(args.slice(0, 2), ['node', '--test']);
  for (const file of ['release-policy', 'release-version-schema', 'release-review',
    'release-registry', 'release-native-publish', 'release-python-publish', 'release-public-install']) {
    assert.equal(args.filter(value => value === `scripts/${file}.test.mjs`).length, 1,
      `normal lint must execute the ${file} control once`);
  }
  assert.equal(job.environment, undefined);
  assert.equal(job.permissions?.['id-token'], undefined);
});

test('dotted channel schema and shared owner match independent literal channel oracles', () => {
  const schema = JSON.parse(readFileSync(new URL('../release/release-request.schema.json', import.meta.url)));
  const pattern = new RegExp(schema.properties.targets.items.properties.channels.items.pattern, 'u');
  for (const channel of ['latest', 'next', 'candidate-fixed', 'release-0.0', 'release-0.1']) {
    assert.equal(pattern.test(channel), true); assert.equal(admitReleaseChannel(channel), channel);
  }
  for (const channel of ['', '0.1', ' release-0.1', 'x/y', 'release-0.1' + String.fromCharCode(10),
    'release-0.1' + String.fromCharCode(0)]) {
    assert.equal(pattern.test(channel), false); assert.throws(() => admitReleaseChannel(channel));
  }
});

test('existing public lint gate selects cross-host packaging controls without runtime or publisher setup', () => {
  const workflow=parse(readFileSync(new URL('../.github/workflows/ci.yml',import.meta.url),'utf8'));
  const job=workflow.jobs.lint;
  assert.equal(job.steps.find(step=>step.uses==='./.github/actions/setup-toolchain').with.python,'true');
  const selected=job.steps.filter(step=>step.name==='Test cross-host Python release preparation without runtime loading');
  assert.equal(selected.length, 1);
  assertReadyLintProfiles(selected[0]);
  const command = selected[0].run.trim().split(/\s+/u);
  for (const required of ['pip', 'install', '-e', './packages/python-sdk',
    'packages/python-sdk/tests/run.py', '--pattern', 'test_release_packaging_target.py'])
    assert(command.includes(required), required);
  assert(!job.environment);assert(!job.permissions?.['id-token']);
});
