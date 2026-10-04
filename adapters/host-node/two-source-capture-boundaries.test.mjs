// Live installed-capture boundary tests. These are ownership/refusal checks;
// native positive resource, cancellation and cleanup proofs live in the
// DuckDB native-capture-custody suite. No runtime builds occur in this file.
import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../host-common/runtime-result.mjs';
import {acquisitionFailure} from '../host-common/acquisition-outcome.mjs';
import {nativeSourceIdentityMatches} from '../connectors/duckdb/node/host.mjs';
import {openCapturedDuckDBSource} from './captured-duckdb-source.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
import {installedSourcePaths} from './installed-source.mjs';
import {observeDuckDBCalls, twoSourceCaptureFixture} from
  './two-source-capture.fixture.mjs';

const tupleFields = ['captures', 'identities', 'requirements',
  'sourceEvidenceWires', 'inputLogicalWires'];
const sortedRows = rows => rows.map(row => ({id: row.id, amount: row.amount}))
  .sort((a, b) => a.id - b.id || (a.amount ?? -Infinity) - (b.amount ?? -Infinity));
const refused = (value, message) => assert.equal(value?.$tag, 0, message);
// Independently authored capture expectations after each Source's id >= 0
// predicate. The physical database also contains a matching negative key;
// those input rows must not appear in the captured logical relations.
const capturedRows = {
  left: [{id: 1, amount: null}, {id: 2, amount: 20},
    {id: 3, amount: 30}, {id: 3, amount: 30}],
  right: [{id: 1, amount: 100}, {id: 3, amount: 300},
    {id: 3, amount: 301}, {id: 4, amount: 400}],
};

test('plural source configuration is bounded, copied and exclusive', () => {
  const paths = ['/owned/left.json', '/owned/right.json'];
  const admitted = installedSourcePaths({sourceProfilePaths: paths});
  paths[0] = '/changed.json';
  assert.deepEqual(admitted, ['/owned/left.json', '/owned/right.json']);
  assert.equal(Object.isFrozen(admitted), true);
  assert.deepEqual(installedSourcePaths({sourceProfilePath: '/single.json'}, '/fallback.json'),
    ['/single.json']);
  for (const sourceProfilePaths of [[], ['/left'], ['/same', '/same'],
    ['relative', '/right'], ['/left', '/right', '/third'], 'not-an-array']) {
    assert.throws(() => installedSourcePaths({sourceProfilePaths}),
      {message: 'InvalidInstalledSourceProfiles'});
  }
  assert.throws(() => installedSourcePaths({sourceProfilePaths: [...admitted],
    sourceProfilePath: '/single.json'}), {message: 'InvalidInstalledSourceProfiles'});
  assert.throws(() => installedSourcePaths({sourceProfilePaths: [...admitted]}, '/env.json'),
    {message: 'InvalidInstalledSourceProfiles'});
});

for (const equalContent of [false, true]) {
  test(`two live captures bind every tuple member (${equalContent ? 'equal' : 'distinct'} content)`, async t => {
    const f = await twoSourceCaptureFixture(t, {equalContent});
    const {moon} = f;
    const counters = observeDuckDBCalls(t);
    const pair = await f.capturePair();
    const run = f.compile();
    const issued = checked(f.issue(pair, run));
    const observation = JSON.parse(moon.strategyRunEvidenceJson(issued._0));
    const sourceEvidence = pair.sourceEvidenceWires.map(wire => JSON.parse(wire));
    assert.deepEqual(observation.source_evidence_cids,
      sourceEvidence.map(body => body.source_evidence_cid));
    assert.equal(observation.source_evidence_cids.length, 2);
    assert.equal(new Set(observation.source_evidence_cids).size, 2,
      'both occurrence-specific Source Evidence entries survive equal content');
    assert.deepEqual(sourceEvidence.map(body => body.source_ref),
      ['connector://crm/main/r#v', 'connector://crm/right/r#v']);
    assert.deepEqual(sourceEvidence.map(body => body.effective_data_policy_cid),
      pair.captured.map(value => value.checkedSource.sourceDataPolicyCid));
    assert.equal(counters().creates, 2);
    assert.equal(counters().connects, 2);
    assert.ok(counters().prepares > 0 && counters().runs > 0);

    for (const [task, captured] of pair.captured.entries()) {
      assert.equal(moon.clientProgramCapturedTaskSourceMatches(f.prepared,
        captured.capture.source(), task), true);
      assert.equal(moon.clientProgramCapturedTaskSourceMatches(f.prepared,
        captured.capture.source(), 1 - task), false);
      assert.equal(nativeSourceIdentityMatches(captured.capture, captured.identity), true);
      assert.equal(nativeSourceIdentityMatches(captured.capture,
        pair.identities[1 - task]), false,
      'a matching logical CID cannot replace the exact capture identity owner');
      // Retain the real dependency bytes and compare against the authored
      // post-predicate expectation, preserving NULL and duplicate input rows.
      const retained = checked(moon.clientProgramIdentifyCapturedEffectSourceRelation(
        captured.capture.source()));
      const bodies = moon.clientProgramCapturedSourceDependencyBodies(retained,
        captured.capture.source());
      const expectedRows = task === 0 || equalContent
        ? capturedRows.left : capturedRows.right;
      assert.deepEqual(sortedRows(JSON.parse(bodies._0).value), expectedRows);
      for (const overrides of [
        {source: pair.captures[1 - task]},
        {identity: pair.identities[1 - task]},
        {requirement: pair.requirements[1 - task]},
        {task: 1 - task},
      ]) {
        const tuple = {source: pair.captures[task], identity: captured.identity,
          requirement: captured.requirement, task, ...overrides};
        refused(moon.clientProgramIssueCapturedTaskSourceLogical(f.prepared,
          tuple.source, tuple.identity, tuple.requirement, tuple.task),
        `logical issuance rejects a foreign tuple member at task ${task}`);
      }
    }
    const relationCids = pair.identities.map(moon.clientProgramCapturedSourceLogicalCid);
    assert.equal(relationCids[0] === relationCids[1], equalContent);
    const publication = f.publication(pair);
    assert.deepEqual(publication.results[0].evidenceContext.inputRelationCids,
      [...new Set(relationCids)], 'only unique logical content dependencies deduplicate');
    assert.deepEqual(publication.receiptEvidence.sourceEvidence.map(value => value.identity),
      observation.source_evidence_cids);

    const beforeMutations = counters();
    for (const field of tupleFields) {
      const original = pair[field];
      const mutations = {
        swapped: [original[1], original[0]],
        duplicateFirst: [original[0], original[0]],
        duplicateSecond: [original[1], original[1]],
        missingFirst: [original[1]], missingSecond: [original[0]],
        extra: [...original, original[0]], empty: [],
      };
      for (const [name, replacement] of Object.entries(mutations)) {
        // Serialized logical content has value equality, not JS object
        // identity. Identical bytes alone cannot distinguish a substitution.
        if (field === 'inputLogicalWires' && replacement.length === 2 &&
            replacement.every((value, index) => value === original[index])) continue;
        refused(f.issue(pair, run, {[field]: replacement}), `${field}: ${name}`);
      }
    }
    refused(f.issue(pair, run, Object.fromEntries(tupleFields.map(field =>
      [field, [pair[field][1], pair[field][0]]]))), 'swapping complete occurrences is refused');
    refused(f.issue(pair, run, Object.fromEntries(tupleFields.map(field =>
      [field, [pair[field][0], pair[field][0]]]))), 'duplicating a complete occurrence is refused');
    assert.deepEqual(counters(), beforeMutations, 'tuple refusal opens no extra session or SQL I/O');

    const foreignPrepared = f.prepare();
    assert.notEqual(foreignPrepared, f.prepared);
    assert.equal(moon.clientProgramDefinitionCid(foreignPrepared),
      moon.clientProgramDefinitionCid(f.prepared));
    const foreign = await f.capturePair(foreignPrepared,
      await f.prepareSources(foreignPrepared));
    checked(f.issue(foreign));
    for (const field of ['captures', 'identities', 'requirements']) {
      refused(f.issue(pair, run, {[field]: foreign[field]}),
        `equivalent Program has a foreign ${field} owner`);
    }
    refused(f.issue(pair, run, Object.fromEntries(tupleFields.map(field =>
      [field, foreign[field]]))), 'an equivalent Program cannot replace the entire capture tuple');
    for (const task of [0, 1]) {
      assert.equal(moon.clientProgramCapturedTaskSourceMatches(f.prepared,
        foreign.captures[task], task), false);
      refused(moon.clientProgramIssueCapturedTaskSourceLogical(f.prepared,
        foreign.captures[task], foreign.identities[task], foreign.requirements[task], task),
      'logical issuance retains the exact prepared Program owner');
      assert.equal(moon.clientProgramCapturedSourceLogicalCid(foreign.identities[task]),
        relationCids[task]);
    }
    checked(f.issue(pair, run));
  });
}

test('installed two-source preparations reject foreign bindings before native session or SQL I/O', async t => {
  const f = await twoSourceCaptureFixture(t, {equalContent: true});
  const counters = observeDuckDBCalls(t);
  const ledger = f.ledgerFor(f.preparedSources);
  const foreignPrepared = f.prepare();
  for (const source of f.preparedSources) {
    const target = source.prepared.physicalBinding;
    const other = f.preparedSources[1 - source.occurrence.task];
    const options = {moon: f.moon, preparedProgram: f.prepared, ...f.common,
      database: target.database, schema: target.schema, table: target.table,
      sourceAccess: source.sourceAccess, preparedSource: source.prepared,
      occurrence: source.occurrence, ledger};
    for (const [name, changed] of [
      ['copied prepared handle', {preparedSource: {...source.prepared}}],
      ['other occurrence preparation', {preparedSource: other.prepared}],
      ['equivalent Program owner', {preparedProgram: foreignPrepared}],
      ['other occurrence', {occurrence: other.occurrence}],
      ['physical database', {database: other.prepared.physicalBinding.database}],
      ['physical schema', {schema: 'other'}],
      ['physical table', {table: 'other'}],
      ['equivalent access handle', {sourceAccess: {...source.sourceAccess}}],
      ['other access handle', {sourceAccess: other.sourceAccess}],
    ]) {
      const before = counters();
      let reported;
      await assert.rejects(openCapturedDuckDBSource({...options, ...changed,
        reportAcquisitionFailure: failure => { reported = failure; }}),
      {message: 'InstalledSourcePreparationMismatch'}, name);
      assert.equal(reported.outcome, 'not_started', name);
      assert.equal(reported.recovery, undefined, name);
      assert.deepEqual(counters(), before, `${name}: refused before native I/O`);
    }
  }
  assert.deepEqual(counters(), {creates: 0, connects: 0, prepares: 0, runs: 0});
  await f.openOne(f.preparedSources[0], ledger);
  assert.equal(counters().creates, 1, 'instrumentation observes a valid native acquisition');
  assert.equal(counters().connects, 1);
  assert.ok(counters().prepares > 0 && counters().runs > 0);
});

for (const failingTask of [0, 1]) {
  test(`unknown acquisition ${failingTask + 1} without recovery never fabricates physical close`, async t => {
    const f = await twoSourceCaptureFixture(t);
    const counters = observeDuckDBCalls(t);
    const ref = {runDefinitionCid: `unknown-two-source-${failingTask}`};
    const stopped = [];
    const opens = [0, 0];
    let closes = 0;
    let computes = 0;
    const preparedSources = f.preparedSources.map((source, task) => ({...source,
      adapter: {...source.adapter, async open(options) {
        opens[task]++;
        if (task === failingTask) {
          // This deliberately models an adapter with no end/recovery
          // observation. It does not manufacture evidence of leaked resources.
          const error = acquisitionFailure(new Error('FixtureAcquisitionEndUnknown'), 'unknown');
          options.reportAcquisitionFailure(error);
          throw new Error('WrappedUnknownAcquisition', {cause: error});
        }
        const captured = await f.openOne(source, options.ledger,
          options.preparedProgram, options);
        return {...captured, async close() { closes++; await captured.close(); }};
      }},
    }));
    const owner = installNodeClientDispatchOwner({moon: f.moon, control: {},
      journal: {reservePhysicalStart: () => true,
        markPhysicalClose: (...args) => stopped.push(args)},
      store: {confirmCommittedIndex: async () => undefined},
      startRun: async () => ({kind: 'reserved', ref}), hostConnection: () => true,
      observed: () => {}, planFor: () => ({runDefinition: {wire: 'definition'}}),
      sourceProfile: {sources: f.adapters}, ...f.common,
      authorityScopeCid: f.authorityScopeCid, namespaceId: 'capture-boundary', now: f.now,
      runPublished: async () => { computes++; assert.fail('unknown acquisition cannot start Compute'); },
    });
    const accepted = {ref, runDefinition: {wire: 'definition'},
      dispatchReserved: false, cancellationRequested: false};
    assert.equal(await owner.start({preparedProgram: f.prepared,
      principalId: 'owner', connection: {}, requestId: `unknown-${failingTask}`},
    {}, accepted, {preparedSources}), 'started');
    const operation = owner.operation(ref);
    await operation;
    assert.deepEqual(opens, failingTask === 0 ? [1, 0] : [1, 1]);
    assert.equal(closes, failingTask, 'any earlier real capture was closed exactly once');
    assert.equal(counters().creates, failingTask);
    assert.equal(computes, 0);
    assert.deepEqual(stopped, [], 'closing earlier captures does not prove the unknown occurrence stopped');
    for (let retry = 0; retry < 2; retry++) {
      await assert.rejects(owner.drain(), {code: 'ClientDispatchCleanupPending'});
      assert.equal(owner.operation(ref), operation);
      assert.deepEqual(stopped, []);
      assert.equal(closes, failingTask);
      assert.deepEqual(opens, failingTask === 0 ? [1, 0] : [1, 1]);
    }
  });
}

// The same authored Program, physical rows, policy and capacities choose Broad
// through ordinary installed priority. This is not a synthetic capture route.
test('two Broad captures keep original identity and positive custody in the shared ledger', async t => {
  const f = await twoSourceCaptureFixture(t, {priority: ['broadQuery', 'nativeQuery']});
  for (const source of f.preparedSources) {
    assert.equal(source.prepared.selection.selectedCandidate, 'broadQuery');
    assert.equal(source.prepared.selection.nativeSupported, true);
    assert.equal(source.prepared.selection.broadSupported, true);
  }
  const pair = await f.capturePair();
  const {moon} = f;
  const usage = () => moon.clientProgramMultiCapturedLedgerUsage(pair.ledger);
  assert.ok(usage()[5] > 0n, 'completed Broad inputs still hold their admitted bytes');
  assert.ok(usage()[2] > 0n, 'the original acquisition holdings remain accounted');
  checked(f.issue(pair));
  for (const [task, capture] of pair.captured.entries()) {
    assert.equal(capture.acquisition.selection.selectedCandidate, 'broadQuery');
    assert.equal(nativeSourceIdentityMatches(capture.capture, pair.identities[task]), true);
    assert.equal(nativeSourceIdentityMatches(capture.capture, pair.identities[1 - task]), false);
    refused(f.issue(pair, f.compile(), {captures: [pair.captures[1], pair.captures[0]]}),
      'selected Broad captures cannot swap physical occurrence identity');
  }
  await pair.captured[0].close();
  assert.ok(usage()[5] > 0n, 'closing the first capture cannot release the second capture');
  const counts = usage().slice(0, 4);
  await pair.captured[0].close();
  assert.deepEqual(usage().slice(0, 4), counts, 'repeat close does not create attempts or holdings');
  await pair.captured[1].close();
  assert.ok(usage().slice(4).every(value => value === 0n),
    'the original capacity owner settles all pending retention and execution reservations');
});
