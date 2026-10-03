import assert from 'node:assert/strict';
import test from 'node:test';
import { body, boundFixture, auditFixture, executionCommand } from './fixture.mjs';
import { hash } from './inventory.mjs';
function evidence(target = 'js') {
  const boundary = { version: 'actql-pipeline-execution-boundary/0.1', workspace: 'isolated-fixture',
    root: '/fixture', role: 'normal', sourceDigest: hash('actual source'), toolchainDigest: hash('tools'),
    environmentDigest: hash('environment'), fixtureDigest: hash(body), target, command: executionCommand(target) };
  const buildIdentity = hash(JSON.stringify(boundary));
  const fixture = boundFixture(boundary);
  const run = { target, exit: 0, sourceDigest: boundary.sourceDigest, boundary,
    command: executionCommand(target), buildIdentity, fixtureDigest: hash(fixture) };
  const log = `ACTQL_PIPELINE_BUILD:${buildIdentity}\nTotal tests: 1, passed: 1, failed: 0\n`;
  return { run, fixture, log };
}
for (const target of ['js', 'wasm', 'native']) {
  test(`both audit consumers can require the actual bound ${target} fixture`, () => {
    const e = evidence(target);
    auditFixture(e.run, Buffer.from(e.fixture), e.log, target);
    assert.throws(() => auditFixture(e.run, body, e.log, target), /Archived compiled fixture differs/);
    assert.throws(() => auditFixture(e.run, e.fixture, '', target), /Executed binary boundary differs/);
    assert.throws(() => auditFixture(e.run, e.fixture, e.log.replace(e.run.buildIdentity, hash('stale binary')), target), /Executed binary boundary differs/);
    assert.throws(() => auditFixture(e.run, e.fixture, e.log + e.log, target), /Executed binary boundary differs/);
    assert.throws(() => auditFixture({ ...e.run, exit: 17 }, e.fixture, e.log, target), /Failed execution/);
  });
}
test('first-use target substitution, stale source, command and boundary identity fail closed', () => {
  const e = evidence('js');
  assert.throws(() => auditFixture(e.run, e.fixture, e.log, 'native'), /Receipt target differs/);
  for (const [key, value, expected] of [['target', 'native', /Compiled target boundary differs/],
    ['sourceDigest', hash('other source'), /Compiled source boundary differs/],
    ['command', executionCommand('native'), /Compiled command boundary differs/],
    ['workspace', 'other-workspace', /Build boundary identity differs/]]) {
    assert.throws(() => auditFixture({ ...e.run, boundary: { ...e.run.boundary, [key]: value } }, e.fixture, e.log, 'js'), expected);
  }
  assert.throws(() => auditFixture({ ...e.run, fixtureDigest: hash(body) }, e.fixture, e.log, 'js'), /Compiled fixture digest differs/);
  assert.throws(() => auditFixture(e.run, e.fixture, e.log.replace('passed: 1', 'passed: 0'), 'js'), /Observation fixture did not pass/);
});
test('target-bound audit fixtures stay byte-identical across all three builds', () => {
  assert.equal(evidence('js').fixture, evidence('wasm').fixture);
  assert.equal(evidence('js').fixture, evidence('native').fixture);
  assert.notEqual(evidence('js').run.buildIdentity, evidence('native').run.buildIdentity);
});
