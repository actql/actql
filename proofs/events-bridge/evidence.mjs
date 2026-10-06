import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, lstatSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {graph, validate, premises as sessionPremises} from '../bounded-session/evidence.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
export const bridgeScope = Object.freeze({operation: 'rows-events-rows', variant: 'ordered-typed-round-trip',
  profile: 'four authored cases; integer Number IDs; numeric or Timestamp clock; nullable Text payload',
  provider: 'src/local_bridge/events.mbt', entrypoint: 'start_rows_to_events -> start_events_view_to_rows'});
export const bridgePremises = Object.freeze([...sessionPremises,
  'unique admitted IDs, valid typed clocks and checked schema for the exact prepared occurrence',
  'both stage-specific semantic preservation premises and intermediate admission are required']);
export const bridgeResidual = Object.freeze([
  'finite implementation correspondence is not a proof for arbitrary values or schemas',
  'UTC parsing, numeric range and all semantic refusal correspondence remain local obligations',
  'direct bounded Session cleanup returns change; managed completion Boolean is not inherited',
  'kernel work charges, output allocation bounds and physical heap/GC remain unproved',
  'provider material/view lifetime, two-consumer custody and public Host acceptance remain separate',
]);
export const bridgeGuarantees = Object.freeze([
  'conditional Session token freshness and terminal sealing',
  'conditional Session cleanup retry without Compute',
  'model admitted ordered Rows round trip; finite real Bridge correspondence only',
]);
export const bridgeModelAction = Object.freeze({id: 'events-model', kind: 'formal-model', target: 'model',
  command: ['node', 'proofs/events-bridge/check.mjs'], package: null, minimumUnits: 16,
  profile: 'local composition and concrete Events exact claim types and audited axioms',
  premises: ['Lean kernel and permitted foundational axioms', 'semantic model is not implementation refinement'],
  dependencies: []});
export const bridgeSuite = Object.freeze({id: 'events-connection',
  fixture: 'src/query_integration/events_bridge_evidence_wbtest.mbt', package: 'src/query_integration',
  minimumTests: 1, profile: bridgeScope.profile, premises: [...bridgePremises, ...bridgeResidual],
  dependencies: ['events-model', 'session-{target}']});

export function bridgeSnapshot(root) {
  const directory = 'proofs/events-bridge';
  // Use source membership, including uncommitted additions, rather than ignored
  // local build/cache directories. Deleted tracked inputs still fail the read.
  const paths = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', directory],
    {cwd: root, encoding: 'utf8'}).split('\0').filter(Boolean).sort();
  for (const required of ['Composition.lean', 'CompositionClaims.lean', 'Events.lean', 'Claims.lean', 'lean-toolchain', 'check.mjs'])
    assert(paths.includes(`${directory}/${required}`), 'Missing Bridge proof input');
  const sources = Object.fromEntries(paths.map(path => {
      assert(path.startsWith(`${directory}/`) && !path.split('/').includes('..'), 'Unreviewed Bridge proof path');
      assert(lstatSync(join(root, path)).isFile(), 'Unreviewed Bridge proof directory entry');
      return [path, hash(readFileSync(join(root, path)))];
    }));
  return {digest: hash(JSON.stringify(sources)), sources};
}

export function checkBridgeRoute(root) {
  const source = readFileSync(join(root, bridgeScope.provider), 'utf8');
  for (const marker of ['pub fn start_rows_to_events(', 'pub fn start_events_view_to_rows(',
    '@bounded.start(', 'rows_to_events_step, cleanup_rows_to_events_state, @records.discard_completed',
    'events_to_rows_step,', 'cleanup_events_to_rows_state,',
    '@bounded.advance(value.session, token, quantum)', '@bounded.cleanup(value.session)',
    'producer_view_read_reference(input)', '@pipeline.Step(step)']) {
    assert(source.includes(marker), `Missing reviewed direct Session/Bridge connection: ${marker}`);
  }
  // These source checks preserve reviewed entrypoints. The real fixture and
  // exact-type Lean execution, not symbol existence, supply the evidence.
}

export function bridgeClaim(target) {
  assert(['js', 'wasm', 'native'].includes(target), 'Unknown Bridge target');
  return {id: 'events/ordered-typed-round-trip', kind: 'derived', scope: {...bridgeScope, target},
    dependencies: ['model', `session-${target}`, 'events-model', `events-connection-${target}`],
    evidenceKinds: ['formal-model', 'tested-refinement'],
    guarantees: [...bridgeGuarantees], premises: [...bridgePremises], residual: [...bridgeResidual]};
}

export function validateBridgeEvidence(report, current, proofSource, target) {
  // Reuse the existing common evidence validator, not another Session model or
  // protocol suite. Adapter results remain required by the existing family,
  // but no cumulative-to-delta guarantee is claimed for these direct bridges.
  validate(graph([], target), report, current, target);
  assert.deepEqual(report.bridge?.source, proofSource, 'Stale Bridge proof/registry source');
  assert.equal(proofSource.digest, hash(JSON.stringify(proofSource.sources)), 'Invalid Bridge proof identity');
  assert.deepEqual(report.bridge.claim, bridgeClaim(target), 'Unreviewed Bridge scope, premise, dependency or guarantee');
  for (const [id, command, minimum, expectedTarget] of [
    ['events-model', bridgeModelAction.command, bridgeModelAction.minimumUnits, 'model'],
    [`events-connection-${target}`, ['moon', 'test', bridgeSuite.fixture, '--target', target, '--deny-warn'],
      bridgeSuite.minimumTests, target],
  ]) {
    const run = report.runs[id];
    assert(run?.passed && run.exit === 0 && run.sourceDigest === current.digest,
      `Missing/stale executed Bridge obligation: ${id}`);
    assert.equal(run.target, expectedTarget, 'Executed Bridge target mismatch');
    assert.deepEqual(run.command, command, 'Unrelated Bridge proof or connection execution');
    assert(Number.isSafeInteger(run.count) && run.count >= minimum, 'Incomplete Bridge execution');
    if (id === 'events-model') {
      assert.equal(run.count, bridgeModelAction.minimumUnits, 'Changed Bridge theorem inventory');
      assert.equal(run.bridgeSourceDigest, proofSource.digest, 'Unrelated Bridge theorem source');
    }
    else {
      assert(Object.keys(run.artifacts ?? {}).length > 0, 'Missing real Bridge artifact');
      for (const [path, digest] of Object.entries(run.artifacts)) {
        assert(path.startsWith(`_build/${target}/debug/test/query_integration/`), 'Wrong Bridge artifact target/package');
        assert.match(digest, /^[a-f0-9]{64}$/u, 'Invalid Bridge artifact digest');
        assert.equal(current.builtArtifacts?.[path], digest, 'Stale Bridge artifact');
      }
    }
  }
  return report.bridge.claim;
}
