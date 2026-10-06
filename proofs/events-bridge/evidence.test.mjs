import test from 'node:test';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {mkdtempSync, mkdirSync, writeFileSync, unlinkSync, symlinkSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {graph} from '../bounded-session/evidence.mjs';
import {bridgeClaim, bridgeModelAction, bridgeSnapshot, bridgeSuite, checkBridgeRoute, validateBridgeEvidence} from './evidence.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
test('Bridge source membership includes additions and rejects missing/symlink inputs, excluding ignored build outputs', () => {
  const fixtureRoot = mkdtempSync(join(tmpdir(), 'actql-bridge-source-'));
  try {
    execFileSync('git', ['init', '--quiet'], {cwd: fixtureRoot});
    const directory = join(fixtureRoot, 'proofs/events-bridge'); mkdirSync(directory, {recursive: true});
    writeFileSync(join(fixtureRoot, '.gitignore'), '_build/\n');
    for (const name of ['Composition.lean', 'CompositionClaims.lean', 'Events.lean', 'Claims.lean', 'lean-toolchain', 'check.mjs'])
      writeFileSync(join(directory, name), name);
    const initial = bridgeSnapshot(fixtureRoot);
    mkdirSync(join(directory, '_build')); writeFileSync(join(directory, '_build/cache'), 'not a source input');
    assert.deepEqual(bridgeSnapshot(fixtureRoot), initial);
    writeFileSync(join(directory, 'new-law.lean'), 'reviewed addition');
    assert.notEqual(bridgeSnapshot(fixtureRoot).digest, initial.digest);
    unlinkSync(join(directory, 'Claims.lean'));
    assert.throws(() => bridgeSnapshot(fixtureRoot), /Missing Bridge proof input/u);
    symlinkSync('Events.lean', join(directory, 'Claims.lean'));
    assert.throws(() => bridgeSnapshot(fixtureRoot), /Unreviewed Bridge proof directory entry/u);
  } finally {rmSync(fixtureRoot, {recursive: true, force: true});}
});

function fixture() {
  const path = '_build/js/debug/test/query_integration/query_integration.whitebox_test.js';
  const current = {digest: 'controlled-source', builtArtifacts: {[path]: 'a'.repeat(64)}};
  const proofSource = bridgeSnapshot(root);
  const base = {exit: 0, passed: true, sourceDigest: current.digest, count: 1, target: 'js', artifacts: {[path]: 'a'.repeat(64)}};
  const report = {target: 'js', source: current, claims: graph([], 'js'),
    bridge: {source: proofSource, claim: bridgeClaim('js')}, runs: {
      lean: {...base, target: 'model', artifacts: {}, command: ['node', 'proofs/bounded-session/check.mjs']},
      'session-js': {...base, command: ['moon', 'test', 'src/bounded_execution', '--target', 'js', '--deny-warn']},
      'adapter-js': {...base, command: ['moon', 'test', 'src/connectors/local', '--target', 'js', '--deny-warn']},
      'events-model': {...base, target: 'model', artifacts: {}, count: 16,
        command: bridgeModelAction.command, bridgeSourceDigest: proofSource.digest},
      'events-connection-js': {...base, command: ['moon', 'test', bridgeSuite.fixture, '--target', 'js', '--deny-warn']},
    }};
  return {report: structuredClone(report), current, proofSource};
}

test('reviewed real Bridge route and conditional scope retain direct Session and independent local obligations', () => {
  checkBridgeRoute(root);
  const f = fixture();
  const original = JSON.stringify(f.report);
  const claim = validateBridgeEvidence(f.report, f.current, f.proofSource, 'js');
  assert.equal(claim.kind, 'derived');
  assert(!claim.dependencies.includes('adapter-js'));
  assert(claim.residual.some(value => value.includes('physical heap/GC')));
  assert.equal(JSON.stringify(f.report), original);
});

for (const [name, change] of [
  ['missing model', f => {delete f.report.runs['events-model'];}],
  ['missing actual connection', f => {delete f.report.runs['events-connection-js'];}],
  ['zero execution', f => {f.report.runs['events-connection-js'].count = 0;}],
  ['failed execution', f => {f.report.runs['events-connection-js'].exit = 1;}],
  ['wrong target', f => {f.report.runs['events-connection-js'].target = 'native';}],
  ['stale runtime source', f => {f.report.runs['events-connection-js'].sourceDigest = 'old';}],
  ['stale theorem source', f => {f.report.runs['events-model'].bridgeSourceDigest = 'old';}],
  ['wrong proof executor', f => {f.report.runs['events-model'].command = ['rg', 'theorem'];}],
  ['partial theorem inventory', f => {f.report.runs['events-model'].count = 6;}],
  ['missing proof membership', f => {delete f.report.bridge.source.sources['proofs/events-bridge/Claims.lean'];}],
  ['unrelated passing fixture', f => {f.report.runs['events-connection-js'].command[2] = 'src/query_integration/local_managed_set_wbtest.mbt';}],
  ['missing artifact', f => {f.report.runs['events-connection-js'].artifacts = {};}],
  ['changed compiled artifact', f => {f.current.builtArtifacts[Object.keys(f.current.builtArtifacts)[0]] = 'b'.repeat(64);}],
  ['widened nullable scope', f => {f.report.bridge.claim.scope.profile = 'arbitrary schemas';}],
  ['wrong Carrier', f => {f.report.bridge.claim.scope.operation = 'rows-graph-rows';}],
  ['wrong claim target', f => {f.report.bridge.claim.scope.target = 'native';}],
  ['missing premise', f => {f.report.bridge.claim.premises.pop();}],
  ['missing common dependency', f => {f.report.bridge.claim.dependencies.splice(1, 1);}],
  ['cycle', f => {f.report.bridge.claim.dependencies.push(f.report.bridge.claim.id);}],
  ['omitted residual obligation', f => {f.report.bridge.claim.residual.pop();}],
  ['formal refinement upgrade', f => {f.report.bridge.claim.evidenceKinds.push('verified-refinement');}],
  ['unconditional capacity guarantee', f => {f.report.bridge.claim.guarantees.push('unconditional heap bound');}],
  ['managed-adapter inheritance', f => {f.report.bridge.claim.guarantees.push('cumulative-to-delta accounting');}],
]) test(`Bridge derivation rejects ${name} without changing the receipt`, () => {
  const f = fixture(); change(f);
  const before = JSON.stringify(f.report);
  assert.throws(() => validateBridgeEvidence(f.report, f.current, f.proofSource, 'js'));
  assert.equal(JSON.stringify(f.report), before);
});
