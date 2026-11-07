// Fixture contract tests only. These doubles prove oracle/phase ordering and
// failure preservation, not provider authentication or ordinary Run acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {salesforceUpdateCase, hubspotUpdateCase} from './fixtures/record-approval/cases.mjs';
import {runRecordUpdateApprovalPhase} from './fixtures/record-approval/workflow.mjs';
import {mockProjectFiles as salesforceMock} from './fixtures/salesforce-approval/mock-project.mjs';
import {mockProjectFiles as hubspotMock} from './fixtures/hubspot-approval/mock-project.mjs';

const cid = mark => 'sha256:' + mark.repeat(64);
const selection = {recordId: 'record-1', previousName: 'before', nextName: 'after'};
async function definition(connector) {
  const files = await Promise.all(['update.aql', 'read.aql'].map(name =>
    readFile(new URL(`./fixtures/${connector}-approval/${name}`, import.meta.url), 'utf8')));
  return (connector === 'salesforce' ? salesforceUpdateCase : hubspotUpdateCase)(
    {update: files[0], read: files[1]}, selection);
}
function publicDouble(value) {
  const events = [], saved = new Map(), ref = {authorityScopeCid: cid('a'), original: 'effect'};
  const summary = {reviewProjectionCid: cid('b'), requiredArtifact: {cid: cid('c')},
    requirements: [{original: 'claim'}], checkpointCid: cid('d')};
  const checkpoint = {id: 'checkpoint', checkpoint_cid: cid('d')};
  const body = {version: 'actql-review-projection/0.1',
    review_projection_cid: cid('b'), effect_preview_cid: cid('c'), authority_scope_cid: cid('a'),
    approval_claims: [{original: 'claim'}], displayed_scope: {
      effects: [{kind: 'update', target: value.review.target, count: 1}]},
    displayed_rows: [{target_row_identity: value.review.identity, preview_strength: 'full_diff',
      row_preview_cid: cid('e'), target_guard: {state: 'version', version_cid: cid('f')},
      before: {state: 'present', value: {...value.review.before, independent_extra_field: 'retained'}},
      intended_changes: {state: 'present', value: {...value.review.changes}},
      after: {state: 'present', value: {...value.review.changes}}}]};
  let approved = false, number = 0;
  const effect = {ref, async wait() {
    events.push('effect:wait');return approved ? {status: 'succeeded', run_id: 'same-run'}
      : {status: 'waiting_checkpoint', run_id: 'same-run', checkpoint};
  }, async status() {
    events.push('effect:status');return approved ? {status: 'succeeded', run_id: 'same-run'}
      : {status: 'waiting_checkpoint', run_id: 'same-run', checkpoint};
  }, result(name) {assert.equal(name, value.effect.resultName);events.push('effect:result');
    return {async all() {events.push('effect:rows');return structuredClone(value.effect.expectedRows);}};}};
  const client = {async startSource(document, options) {
    if (document === value.effect.document) {
      events.push('submit:effect');assert.equal(options.stopBefore, 'commit');
      assert.deepEqual(options.parameters, value.effect.parameters);return effect;
    }
    assert.equal(document, value.read.document);events.push('submit:read');number++;
    assert.deepEqual(options.parameters, value.read.parameters);
    return {ref: {original: 'read-' + number}, async wait() {events.push('read:wait');return {status: 'succeeded'};},
      result(name) {assert.equal(name, value.read.resultName);return {async all() {
        events.push('read:rows');return structuredClone(approved ? value.read.afterRows : value.read.beforeRows);
      }};}};
  }, async checkpoints(actual) {assert.deepEqual(actual, {checkpointId: 'checkpoint'});return {items: [summary]};},
  async reviewCheckpoint(actual) {assert.deepEqual(actual, summary);events.push('review');return {bytes: Buffer.from(JSON.stringify(body))};},
  async attach(actual) {assert.deepEqual(actual, ref);events.push('attach');return effect;},
  async close() {events.push('close');}};
  return {client, events, saved, body, effect,
    async load(name) {events.push('load:' + name);assert(saved.has(name));return structuredClone(saved.get(name));},
    async save(name, data) {events.push('save:' + name);assert(!saved.has(name));saved.set(name, structuredClone(data));},
    async approve(actual, captured) {assert.strictEqual(actual, client);assert.deepEqual(captured.ref, ref);
      events.push('approve');approved = true;return {results: [{status: 'committed'}]};}};
}
async function phase(which, value, f, changes = {}) {
  return runRecordUpdateApprovalPhase({phase: which, definition: value, ...f, ...changes});
}

for (const connector of ['salesforce', 'hubspot']) {
  test(`shared ${connector} fixture preserves original reference, explicit approval and Saved-first order`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);
    assert(f.events.indexOf('save:submitted') < f.events.indexOf('effect:wait'));
    assert(!f.events.includes('approve'));
    await phase('approve', value, f);
    const split = f.events.length;await phase('recover', value, f);
    const recovered = f.events.slice(split);
    assert(recovered.indexOf('effect:rows') < recovered.indexOf('effect:status'));
    assert(!recovered.some(x => x.startsWith('submit:') || x === 'approve'));
    assert.deepEqual(f.saved.get('submitted').ref, f.saved.get('recovered').ref);
    assert.equal(f.events.filter(x => x === 'close').length, 3);
    assert.equal(f.events.filter(x => x === 'approve').length, 1);
  });
  test(`shared ${connector} fixture rejects a changed sealed Review before operator approval`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);
    f.body.displayed_rows[0].intended_changes.value = {changed: 'unapproved'};
    const split = f.events.length;
    await assert.rejects(phase('approve', value, f));
    assert(!f.events.slice(split).includes('approve'));
    assert.equal(f.events.at(-1), 'close');
  });
  test(`shared ${connector} fixture refuses an uncommitted approval before wait or Result`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);const split = f.events.length;
    await assert.rejects(phase('approve', value, f, {approve: async () => ({results: [{status: 'refused'}]})}));
    assert(!f.events.slice(split).some(x => ['effect:wait', 'effect:result', 'submit:read'].includes(x)));
    assert.equal(f.events.at(-1), 'close');
  });
  test(`shared ${connector} fixture cannot retarget a saved reference to another Program`, async () => {
    const value = await definition(connector), f = publicDouble(value);
    await phase('capture', value, f);await phase('approve', value, f);
    const changed = structuredClone(value);changed.effect.document += '\n-- changed';
    const split = f.events.length;await assert.rejects(phase('recover', changed, f));
    assert(!f.events.slice(split).includes('attach'));
    assert.equal(f.events.at(-1), 'close');
  });
}

for (const primary of [undefined, null, false, 0, '']) {
  test(`shared fixture preserves original falsy rejection ${String(primary)} through cleanup`, async () => {
    const value = await definition('salesforce');let closed = 0, rejected = false;
    try {await runRecordUpdateApprovalPhase({phase: 'capture', definition: value,
      client: {async startSource() {throw primary;}, async close() {closed++;}}});}
    catch (error) {rejected = true;assert.strictEqual(error, primary);}
    assert(rejected);assert.equal(closed, 1);
  });
}
test('shared fixture keeps original and cleanup failures separately even for undefined primary', async () => {
  const cleanup = new Error('original cleanup pending'), value = await definition('hubspot');
  await assert.rejects(runRecordUpdateApprovalPhase({phase: 'capture', definition: value,
    client: {async startSource() {throw undefined;}, async close() {throw cleanup;}}}), error => {
      assert(error instanceof AggregateError);assert.deepEqual(error.errors, [undefined, cleanup]);
      assert(Object.hasOwn(error, 'cause'));assert.equal(error.cause, undefined);return true;
    });
});

for (const [connector, builder, resource, idField, valueField] of [
  ['salesforce', salesforceMock, 'Account', 'Id', 'Name'],
  ['hubspot', hubspotMock, 'companies', 'id', 'name'],
]) test(`shared ${connector} mock supplies explicit unchanged Program aliases and required approval`, () => {
  const files = builder(selection), catalog = JSON.parse(files['mock/catalog.json']).connections[connector];
  assert.equal(catalog.writes[0].approval, 'required');
  assert.deepEqual(catalog.writes[0].writable_fields, [valueField]);
  assert.equal(catalog.writes[0].primary_identity, idField);
  const rows = JSON.parse(files['mock/data.json'])[connector][resource].rows;
  assert.deepEqual(rows[0], {[idField]: selection.recordId, [valueField]: 'before'});
  assert.equal(rows.length, 2);assert.notEqual(rows[1][idField], selection.recordId);
});
