import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientSubmission} from './client-submission.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {validSubmissionLookup} from '../../packages/client-wire/index.mjs';

const authorityScopeCid = `sha256:${'a'.repeat(64)}`;
const connection = {mode: 'local', owner: 'local', durability: 'durable', consentRefs: [], runners: []};
const principalId = 'submission-principal';
const fields = {authorityScopeCid, namespaceId: 'submission-test', currentAuthorization: true};
async function fixture(t, callbacks = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-d-submission-connection-'));
  let journal = openClientRequestJournal(root);
  t.after(async () => {journal.close(); await rm(root, {recursive: true, force: true});});
  let authorized = true;
  let prepareCount = 0, submitCount = 0;
  let service;
  const install = () => service = installNodeClientSubmission({journal, moon,
    authorizedScope: () => authorized ? fields : undefined,
    prepareSubmit: async value => {prepareCount++; return callbacks.prepare?.(value) ?? {};},
    submit: async value => {submitCount++; return await callbacks.submit(value);},
    lookupRequest: async value => callbacks.lookup?.(value) ?? {kind: 'not_found'},
  });
  install();
  const ref = {epoch: await service.issueEpoch({principalId, connection}), nonce: 'original-nonce'};
  const body = (text = 'SELECT 1 AS value') => {
    const source = {kind: 'aql', input: {format: 'aql-text', text}, parameters: null};
    const intent = moon.clientSubmittedIntent(JSON.stringify(source), 1048576, 65536, 64);
    return {principalId, connection, submissionRef: ref, intentCid: moon.clientSubmittedIntentCid(intent), ...source};
  };
  const port = () => createNodeInProcessClientHost({authenticate: () => principalId,
    authorizeConnection: () => authorized, negotiate: () => undefined,
    submitIntent: service.submitIntent, lookupSubmission: service.lookupSubmission, maxRowBytes: 65536});
  return {root, ref, body, port, get journal() {return journal;}, get service() {return service;},
    get counts() {return {prepare: prepareCount, submit: submitCount};},
    authorize: value => {authorized = value;}, restart() {journal.close(); journal = openClientRequestJournal(root); install();}};
}

test('public Local submission lookup returns a durable pre-admission refusal after restart', async t => {
  const f = await fixture(t, {prepare() {throw Object.assign(new Error('invalid fixture'), {code: 'ClientProgramInvalidInput'});}});
  const body = f.body('SELECT (');
  const {principalId: ignored, ...wireBody} = body;
  const reply = await f.port().perform('submit-intent', wireBody);
  assert.equal(reply.kind, 'not_accepted');
  assert.equal(reply.problem.classification, 'invalid_input');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  f.restart();
  const restored = await f.port().perform('lookup-submission', {connection, submissionRef: f.ref});
  assert.deepEqual(restored, reply);
  assert.equal(validSubmissionLookup(restored, connection, f.ref), true);
  assert.deepEqual(await f.port().perform('submit-intent', wireBody), reply);
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  await assert.rejects(f.service.submitIntent(f.body('SELECT 1 AS value')), {code: 'ClientSubmittedIntentConflict'});
});

test('accepted preparation failure remains accepted with no invented Run identity', async t => {
  const f = await fixture(t, {submit() {throw Object.assign(new Error('missing fixture input'), {code: 'ClientProgramNeedsInputs'});}});
  const reply = await f.service.submitIntent(f.body());
  assert.equal(reply.kind, 'preparation_failed');
  assert.equal(reply.problem.classification, 'requirements');
  assert.equal('ref' in reply, false);
  f.restart();
  assert.deepEqual(await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref}), reply);
  assert.deepEqual(await f.service.submitIntent(f.body()), reply);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1});
});

test('unclassified interruption leaves Preparing and lookup never dispatches work', async t => {
  const f = await fixture(t, {submit() {throw new Error('fixture lost transport');}});
  await assert.rejects(f.service.submitIntent(f.body()), /fixture lost transport/);
  f.restart();
  const restored = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.equal(restored.kind, 'preparing');
  assert.deepEqual(restored.submissionRef, f.ref);
  assert.equal('ref' in restored, false);
  assert.deepEqual(f.counts, {prepare: 1, submit: 1});
});

test('unknown original identity is unresolvable rather than evidence of nonexecution', async t => {
  const f = await fixture(t);
  const found = await f.service.lookupSubmission({principalId, connection, submissionRef: f.ref});
  assert.equal(found.kind, 'unresolvable');
  assert.deepEqual(f.counts, {prepare: 0, submit: 0});
});

test('intent digest mismatch is refused before preparation or admission', async t => {
  const f = await fixture(t);
  await assert.rejects(f.service.submitIntent({...f.body(), intentCid: `sha256:${'0'.repeat(64)}`}),
    {code: 'InvalidClientSubmittedIntent'});
  assert.deepEqual(f.counts, {prepare: 0, submit: 0});
  assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
});

test('Local ingress owns nested submission values before authentication awaits', async t => {
  const f = await fixture(t, {prepare(value) {
    assert.equal(value.input.text, 'SELECT 1 AS value');
    throw Object.assign(new Error('fixture preflight'), {code: 'ClientProgramUnsupported'});
  }});
  let release;
  const authentication = new Promise(resolve => {release = resolve;});
  const port = createNodeInProcessClientHost({authenticate: () => authentication,
    authorizeConnection: () => true, negotiate: () => undefined, submitIntent: f.service.submitIntent,
    lookupSubmission: f.service.lookupSubmission, maxRowBytes: 65536});
  const {principalId: ignored, ...body} = f.body();
  const pending = port.perform('submit-intent', body);
  body.input.text = 'SELECT changed AS value';
  body.submissionRef.nonce = 'changed-nonce';
  release(principalId);
  const result = await pending;
  assert.equal(result.kind, 'not_accepted');
  assert.equal(result.submissionRef.nonce, 'original-nonce');
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
});

test('current authorization is checked again after awaited preparation', async t => {
  let f;
  f = await fixture(t, {prepare: async () => {await Promise.resolve(); f.authorize(false); return {};}});
  await assert.rejects(f.service.submitIntent(f.body()), {code: 'ClientRequestLookupDenied'});
  assert.deepEqual(f.counts, {prepare: 1, submit: 0});
  f.authorize(true);
  assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon), undefined);
});
