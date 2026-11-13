import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'yaml';
import {releaseVersion} from './release-version.mjs';
import {admitReleaseChannel} from './release-policy.mjs';

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
  assert.deepEqual(selected[0], {name: 'Test explicit release policy and publication refusal',
    if: "${{ !startsWith(needs.select-targets.outputs.profile, 'draft') }}",
    run: 'node --test scripts/release-policy.test.mjs scripts/release-version-schema.test.mjs scripts/release-set.test.mjs scripts/release-review.test.mjs scripts/release-promotion-review.test.mjs scripts/release-registry.test.mjs scripts/release-stage.test.mjs scripts/release-native-registry.test.mjs scripts/release-native-publish.test.mjs scripts/release-native-latest.test.mjs scripts/release-public-install.test.mjs scripts/release-python-install.test.mjs scripts/release-python-publish.test.mjs scripts/release-python-cold-verifier.test.mjs scripts/release-native-install.test.mjs scripts/release-lanes.test.mjs scripts/release-fixed-source.test.mjs scripts/native-standalone-release.test.mjs scripts/native-cli-version.test.mjs'});
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
  assert.deepEqual(selected,[{name:'Test cross-host Python release preparation without runtime loading',
    if:"${{ !startsWith(needs.select-targets.outputs.profile, 'draft') }}",
    run:'python3 -m pip install --disable-pip-version-check -e ./packages/python-sdk\npython3 -B packages/python-sdk/tests/run.py --pattern test_release_packaging_target.py\n'}]);
  assert(!job.environment);assert(!job.permissions?.['id-token']);
});
