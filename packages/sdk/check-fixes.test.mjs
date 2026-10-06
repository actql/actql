import test from 'node:test';
import assert from 'node:assert/strict';
import {checkReasonSchemaCid, checkOutcomeSchemaCid} from '@actql/client-wire';
import {connect, createCheckDocumentSession, getCheckInput, getCheckFixes} from './index.mjs';

const original = '\ufeffSELECT 1 AS n /* e\u0301😀\r\n';
const changed = '\ufeffSELECT 1 AS n /* e\u0301😀\r\n*/';
const revision = 'rev:' + '4'.repeat(64), editedRevision = 'rev:' + '5'.repeat(64);
const profile = {version: 'actql-client-host/0.1', mode: 'remote', owner: 'remote',
  durability: 'volatile', scopeRef: 'scope-a', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const reply = text => {
  assert.ok(text === original || text === changed);
  const edited = text === changed, rev = edited ? editedRevision : revision;
  return {version: 'actql-check-outcome/0.1', reason_schema_cid: checkReasonSchemaCid,
    outcome_schema_cid: checkOutcomeSchemaCid, outcome: 'completed', report: {
      context_ref: edited ? 'ctx:edited' : 'ctx:original', scope: {kind: 'bound_input'},
      verdict: edited ? 'verified' : 'invalid', inputs: [{document_id: 'source',
        kind: 'text', revision: rev, byte_length: edited ? 31 : 29}],
      reasons: edited ? [] : [{code: 'query_lexical_invalid', facts: {issue: 'unterminated_comment'},
        location: {kind: 'text', document_id: 'source', revision,
          start_byte: 17, end_byte: 17, precision: 'exact'},
        fixes: [{code: 'close_block_comment', applicability: 'requires_review',
          risk: 'syntax_structure', target: {document_id: 'source', revision},
          edits: [{start_byte: 29, end_byte: 29, replacement: '*/'}]}]}],
      requirements: [], coverage: {limits: [], unresolved: []}}};
};
async function fixture(t, respond = body => reply(body.input.text)) {
  const requests = [];
  t.mock.method(globalThis, 'fetch', async (url, request) => {
    if (url.pathname.endsWith('/connect')) return Response.json(profile);
    const body = JSON.parse(request.body); requests.push(body);
    const outcome = await respond(body, requests.length);
    for (const [document_id, value] of [
      ['parameter_declarations', body.input.parameterDeclarations], ['parameters', body.parameters],
    ]) if (value !== undefined && value !== null) outcome.report.inputs.push({document_id,
      kind: 'structured', revision: 'rev:' + '6'.repeat(64),
      byte_length: new TextEncoder().encode(JSON.stringify(value)).length});
    return Response.json(outcome);
  });
  const client = await connect({mode: 'remote', endpoint: 'https://host.example/', token: 'token'});
  return {session: createCheckDocumentSession(client, {text: original, version: 1}), requests};
}
const refusal = async work => {try {await work();} catch (error) {return error.code;}};
const apply = (session, observation, fixes = getCheckFixes(observation.outcome)) =>
  session.applyFixes(observation, fixes, {version: 2, reviewed: true});

test('fix application preserves exact input and rechecks before one atomic commit', async t => {
  const {session, requests} = await fixture(t);
  const parameters = {unused: 'private-e\u0301\r\n'}, declarations = {unused: {type: 'string'}};
  const observation = await session.check({format: 'sql', parameters, parameterDeclarations: declarations});
  parameters.unused = 'edited'; declarations.unused.type = 'number';
  const updated = await apply(session, observation);
  assert.equal(getCheckInput(updated.outcome, 'source').text, changed, '[check-mutation:fix-atomic-text]');
  assert.equal(updated.version, 2);
  assert.equal(updated.outcome.report.verdict, 'verified');
  assert.deepEqual(requests.map(body => body.input.text), [original, original, changed, original]);
  assert.ok(requests.every(body => body.parameters.unused === 'private-e\u0301\r\n' &&
    body.input.parameterDeclarations.unused.type === 'string'));
  assert.equal(getCheckInput(observation.outcome, 'source').text, original);
  assert.equal(session.resolveTextRange(observation, observation.outcome.report.reasons[0].location), undefined);
  assert.equal(getCheckFixes(structuredClone(observation.outcome)), undefined, '[check-mutation:fix-copy]');
  assert.equal(getCheckInput(structuredClone(observation.outcome), 'source'), undefined);
  const current = await session.check({format: 'sql'});
  assert.equal(getCheckInput(current.outcome, 'source').text, changed,
    '[check-mutation:fix-committed-buffer]');
});

test('fix application rejects copied stale unreviewed and conflicting edits without I/O', async t => {
  const {session, requests} = await fixture(t);
  const observation = await session.check({format: 'sql'}), fixes = getCheckFixes(observation.outcome);
  assert.equal(await refusal(() => session.applyFixes(observation, fixes, {version: 2, reviewed: false})),
    'CheckFixReviewRequired', '[check-mutation:fix-review]');
  assert.equal(await refusal(() => apply(session, observation, structuredClone(fixes))), 'InvalidCheckFixes');
  assert.equal(await refusal(() => apply(session, {...observation})), 'CheckFixStale');
  assert.equal(await refusal(() => apply(session, observation, [fixes[0], fixes[0]])),
    'InvalidCheckFixes', '[check-mutation:fix-conflict]');
  session.update('SELECT 2 AS n', 2);
  assert.equal(await refusal(() => apply(session, observation)), 'CheckFixStale', '[check-mutation:fix-stale]');
  session.close();
  assert.equal(await refusal(() => apply(session, observation)), 'CheckFixStale');
  assert.equal(requests.length, 1);
});

for (const phase of [2, 4]) {
  test(`fix application rejects observed permission context changes at check ${phase}`, async t => {
    const {session, requests} = await fixture(t, (body, count) => {
      const outcome = reply(body.input.text);
      if (count === phase) outcome.report.context_ref = 'ctx:changed-policy';
      return outcome;
    });
    const observation = await session.check({format: 'sql'});
    assert.equal(await refusal(() => apply(session, observation)), 'CheckFixContextChanged',
      '[check-mutation:fix-context]');
    assert.equal(requests.length, phase);
    assert.ok(session.resolveTextRange(observation, observation.outcome.report.reasons[0].location));
    assert.equal(getCheckInput((await session.check({format: 'sql'})).outcome, 'source').text, original);
  });
}

for (const phase of [2, 3, 4]) {
  test(`fix application cannot overwrite a concurrent edit during check ${phase}`, async t => {
    let session, release, arrived;
    const arrival = new Promise(resolve => {arrived = resolve;});
    const fixtureValue = await fixture(t, async (body, count) => {
      if (count === phase) {arrived(); await new Promise(resolve => {release = resolve;});}
      return reply(body.input.text);
    });
    session = fixtureValue.session;
    const observation = await session.check({format: 'sql'});
    const editing = apply(session, observation);
    await arrival; session.update('external edit', 3); release();
    assert.equal(await refusal(() => editing), 'CheckFixStale', '[check-mutation:fix-stale]');
    assert.equal(session.resolveTextRange(observation, observation.outcome.report.reasons[0].location), undefined);
  });
}

test('fix application keeps original buffer when candidate recheck fails', async t => {
  const {session} = await fixture(t, (body, count) => {
    if (count === 3) throw new Error('connection lost');
    return reply(body.input.text);
  });
  const observation = await session.check({format: 'sql'});
  assert.ok(await refusal(() => apply(session, observation)));
  assert.ok(session.resolveTextRange(observation, observation.outcome.report.reasons[0].location),
    '[check-mutation:fix-rollback]');
  const unchanged = await session.check({format: 'sql'});
  assert.equal(getCheckInput(unchanged.outcome, 'source').text, original);
});
