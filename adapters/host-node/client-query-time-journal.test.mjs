import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdir, mkdtemp, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {openClientRequestJournal, installNodeClientEffectRun} from './client-effect-run.mjs';

const cid = digit => 'sha256:' + digit.repeat(64);
const root = new URL('../../', import.meta.url);

async function preparedFixture() {
  // Reuse the independently ordered original Environment and the existing
  // Effect fixture. The extra predicate demands time but does not change the
  // Mapping, authored result or target. No Source or driver is installed here.
  const original = await readFile(new URL(
    'src/run_publication_host/client_query_time_wbtest.mbt', root), 'utf8');
  const environmentWire = original.match(
    /let client_query_time_source_environment : String =\s*#\|([^\n]+)/u)?.[1];
  assert.ok(environmentWire);
  const environment = moon.clientProgramCheckEnvironment(environmentWire,
    JSON.parse(environmentWire).evidence_bundle_cid,
    false, false, true, false, false, false, false);
  assert.ok(environment);
  const source = await readFile(new URL(
    'src/run_publication_host/client_composed_effect_fixture_wbtest.mbt', root), 'utf8');
  const document = JSON.parse(source.match(/let document =\s*#\|([^\n]+)/u)[1]);
  document.stages[0].steps.push({from: 'selected',
    filter: 'current_timestamp() = current_timestamp()', as: 'timed'});
  document.stages[0].results.out.from = 'timed';
  // Raw checker input for this isolated Journal/QueryTime component. The
  // fixture's explicit execution port below is not ordinary Request admission.
  const prepare = request => {
    const outcome = moon.clientProgramPrepareEffectComputationWithParameters(
      JSON.stringify(request.input), 'json', environment, undefined, []);
    const original = moon.clientProgramEffectPreparationReady(outcome);
    assert.ok(original, moon.clientProgramEffectPreparationIssueCode(outcome));
    return original;
  };
  const prepared = prepare({kind: 'program', input: document, parameters: null});
  assert.equal(checked(moon.clientProgramEffectRequiresQueryTime(prepared, 100000, 100000)), true);
  return {prepared, prepare, document};
}

test('actual Common and request Journal retain the new invocation time across reopen', async () => {
  const {prepared, prepare, document} = await preparedFixture();
  const scratch = new URL('../../_build/client-query-time-journal/', import.meta.url);
  await mkdir(scratch, {recursive: true});
  const directory = await mkdtemp(join(scratch.pathname, 'original-'));
  const control = runtimeCore(moon).publicationControl;
  let journal = openClientRequestJournal(directory);
  const executions = [];
  const policy = {executionContextCid: cid('a'), hostPolicyCid: cid('b'),
    createdAt: '2001-01-01T00:00:00.000Z', expiresAt: '2099-01-01T00:00:00.000Z'};
  const request = owner => ({prepared: owner, authorityScopeCid: cid('c'),
    requestId: 'original-query', namespaceId: 'query-time-journal',
    lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    principalId: 'fixture-principal', connection: {mode: 'local', owner: 'local'}});
  const install = () => installNodeClientEffectRun({moon, publicationControl: control,
    journal, authorizeRequest: async () => policy, authorizeRunStart: async () => true,
    // The callback tests the original prepared Run/context boundary only. It
    // deliberately installs no physical Effect or publication implementation.
    execute: async facts => {
      assert.equal(moon.clientProgramEffectRunQueryTimeMatches(facts.owner,
        facts.queryTimePreparation, facts.identity), true);
      const createdAt = moon.clientProgramQueryTimeCreatedAt(facts.queryTimePreparation);
      assert.equal(createdAt, JSON.parse(facts.runDefinition.wire).created_at);
      const copied = moon.clientProgramEffectRequestIdentity(facts.prepared,
        cid('c'), 'original-query', moon.clientProgramSourceFreeInputIntentCid());
      assert.ok(copied);
      assert.equal(moon.clientProgramEffectRunQueryTimeMatches(facts.owner,
        facts.queryTimePreparation, copied), false);
      executions.push(facts);
      return createdAt;
    }});
  try {
    const first = install();
    first.checkSupported(prepared);
    const before = Date.now(), handle = await first.accept(request(prepared)), after = Date.now();
    const retained = journal.lookupRunDefinition(handle.ref, moon, control);
    const saved = retained.runDefinition;
    const createdAt = JSON.parse(saved.wire).created_at;
    assert.notEqual(createdAt, policy.createdAt);
    assert.ok(Date.parse(createdAt) >= before && Date.parse(createdAt) <= after);
    assert.equal(retained.physicalStartReserved, false);
    journal.close();
    journal = openClientRequestJournal(directory);
    // A fresh preparation has equal authored bytes, but a different nominal
    // Owner. Restoration binds it to the winning saved definition, not now.
    const restoredPrepared = prepare({kind: 'program', input: document, parameters: null});
    assert.notStrictEqual(restoredPrepared, prepared);
    const reopened = install(), restored = await reopened.accept(request(restoredPrepared));
    assert.deepEqual(restored.ref, handle.ref);
    assert.deepEqual(journal.lookupRunDefinition(restored.ref, moon, control).runDefinition, saved);
    const started = await reopened.start(restored);
    assert.equal(started.kind, 'started');
    assert.equal(started.value, createdAt);
    assert.equal(executions.length, 1);
    const recovered = await reopened.restoreComputation(restored);
    assert.equal(moon.clientProgramQueryTimeCreatedAt(recovered.queryTimePreparation), createdAt);
    assert.equal(moon.clientProgramEffectRunQueryTimeMatches(recovered.owner,
      recovered.queryTimePreparation, recovered.identity), true);
    assert.equal(journal.lookupRunDefinition(restored.ref, moon, control).physicalStartReserved, true);
    const again = await reopened.start(restored);
    assert.equal(again.kind, 'reconcile');
    assert.equal(executions.length, 1, 'the original physical-start claim is never reset');
  } finally { journal.close(); }
});
