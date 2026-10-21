import assert from 'node:assert/strict';
import {registerHooks} from 'node:module';
import test from 'node:test';
import {readySubmissionAttempt, submissionEpoch} from './submission-fixture.mjs';

// Count the actual exported capture passes, not row validation, permission
// evaluation or cache hits. The wrapper always invokes the unchanged capture.
const captures = [];
const counterKey = Symbol.for('actql.sdk.query-read-capture.test');
globalThis[counterKey] = captures;
const original = new URL('./result-schema.mjs', import.meta.url).href;
const wrapper = `import * as original from ${JSON.stringify(original)};
export * from ${JSON.stringify(original)};
${['captureResultRead', 'captureReadOptions'].map(name => `export function ${name}(...args) {
  globalThis[Symbol.for('actql.sdk.query-read-capture.test')].push('${name}');
  return original.${name}(...args);
}`).join('\n')}`;
const wrapperUrl = `data:text/javascript,${encodeURIComponent(wrapper)}`;
const hook = registerHooks({resolve(specifier, context, nextResolve) {
  const resolved = nextResolve(specifier, context);
  return context.parentURL?.includes('/packages/sdk/') && resolved.url === original
    ? {url: wrapperUrl, shortCircuit: true} : resolved;
}});
const {connectInProcess} = await import('./host-port.mjs');
hook.deregister();

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'capture-once', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'capture-once', capabilities: [], submissionEpoch,
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};

for (const typed of [false, true]) {
  test(`unselected query all captures ${typed ? 'schema and options' : 'options'} once before its wait`, async t => {
    let release, optionReads = 0, schemaReads = 0, rowValidations = 0;
    const pending = new Promise(resolve => {release = resolve;});
    const calls = [];
    const client = await connectInProcess({mode: 'local', owner: 'local'}, {
      async perform(operation, body) {
        calls.push(operation);
        if (operation === 'connect') return profile;
        if (operation === 'submit-intent') return readySubmissionAttempt(body, {ref, durability: 'volatile', revision: 1});
        if (operation === 'wait') {
          await pending;
          return {version: 'actql-run-state/0.1', run_id: 'capture-once', revision: 1,
            status: 'succeeded', updated_at: '2026-10-21T00:00:00.000Z',
            next_action: {kind: 'read_result', results: ['answer']}, result_available: true,
            result_availability: {answer: {state: 'available', reason: 'confirmed_present',
              observed_at: '2026-10-21T00:00:00.000Z'}}};
        }
        assert.equal(operation, 'read');
        return {kind: 'rows', frames: (async function* () {yield {value: {n: 1}, byteLength: 8};})()};
      },
    });
    t.after(() => client.close());
    const options = {get maxRows() {optionReads++; return 1;}};
    const standard = {version: 1, vendor: 'capture-once', validate(row) {
      assert.strictEqual(this, standard); rowValidations++; return {value: {n: row.n + 1}};
    }};
    const schema = {get '~standard'() {schemaReads++; return standard;}};
    const query = client.sql('SELECT 1 AS n');
    captures.length = 0;
    const values = typed ? query.all(schema, options) : query.all(options);
    assert.deepEqual(captures, ['captureResultRead']);
    assert.equal(optionReads, 1);
    assert.equal(schemaReads, typed ? 1 : 0);
    assert.equal(calls.includes('read'), false);
    release();
    assert.deepEqual(await values, [{n: typed ? 2 : 1}]);
    assert.deepEqual(captures, ['captureResultRead'], 'the admitted capture is consumed without a second capture pass');
    assert.equal(rowValidations, typed ? 1 : 0);
    assert.equal(optionReads, 1);
    assert.deepEqual(calls, ['connect', 'submit-intent', 'wait', 'read']);
  });
}
