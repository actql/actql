import assert from 'node:assert/strict';
import {build} from 'esbuild';
import test from 'node:test';
import {buildFiniteRuntime} from './build.mjs';
import {checkWorkersArtifact} from './artifact.mjs';
import {createTestRuntime} from './runtime.mjs';
import {finiteOriginalMaterials} from './finite-runtime-fixture.mjs';
import {finiteExpressionConfiguration, finiteExpressionInput, finiteCountDocument,
  finiteNumericProfileCid} from '../../packages/run-host-core/fixtures/finite-expression.mjs';

const limits = {
  maxResultFields: 10, maxResultMappingWork: 10000, maxResultOrderWork: 10000,
  maxResultWorkspaceEntries: 1000, maxRows: 100, maxValueNodes: 10000,
  maxValueTextBytes: 100000, maxValueDepth: 100, maxValueWork: 100000,
  maxWireBytes: 100000, maxWireNodes: 10000, maxWireDepth: 100, maxColumns: 100,
  maxOrderWork: 10000, maxLogicalWireBytes: 100000, maxLogicalWireNodes: 10000,
  maxLogicalWireDepth: 100, maxSchemaFields: 100, maxSchemaBytes: 10000,
  maxSchemaNodes: 1000, maxSchemaDepth: 100, maxBatchBytes: 32,
};

// This test crosses a serialized boundary from a separate original request
// Owner into the production artifact; no fixture handle enters the installation.
async function consumeOriginal(createRuntime, input, limits) {
  const {host, core, createAuthorizationGate} = createRuntime(19, input.configuration);
  if (host.core !== core) throw new Error('SplitRuntimeCore');
  const gate = createAuthorizationGate({configuration: JSON.stringify({
    version: 'actql-execution-account-config/0.1', account_id: 'production-test',
    entries: [{entry_id: 'finite', outcome: 'allow', principal: {any_of: ['tester']},
      connection: {any_of: ['in-process-default']}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []}],
  }), context: {principal: 'tester', contextCid: 'sha256:' + 'a'.repeat(64)},
  protectedSites: ['in-process-default']});
  try {
    const restored = host.admitMaterials(input.wire, input.runDefinitionCid);
    const setup = host.open(restored.preparation,
      {...restored, ledger: host.createLedger()}, gate);
    return await host.withExecution(setup, gate, async () => {
      const exported = await core.outputExportControl.beginResult(setup, 0, limits);
      try {
        let wire = '';
        while (true) {
          const next = core.outputExportControl.advance(exported, 8);
          if (next.issue !== undefined) throw new Error(next.issue);
          if (next.batch !== undefined) wire += next.batch;
          if (next.complete) break;
        }
        wire += core.outputExportControl.finish(exported);
        return {rows: JSON.parse(wire), identity: core.outputExportControl.identity(exported),
          measurement: core.outputExportControl.measurement(exported)};
      } finally { core.outputExportControl.cancel(exported); }
    });
  } finally { gate.close(); }
}

test('production finite artifact admits original materials from a separate link unit on Node and workerd', async () => {
  const artifact = await buildFiniteRuntime();
  const url = new URL('../../_build/workers/finite-runtime.mjs', import.meta.url);
  const {createWorkersFiniteRuntime} = await import(url.href);
  const input = finiteOriginalMaterials({rows: [{id: 8}, {id: null}, {id: 3}], nullable: true});
  const node = await consumeOriginal(createWorkersFiniteRuntime, input, limits);
  assert.deepEqual(node.rows, [{id: 8}, {id: null}, {id: 3}]);
  assert.equal(node.measurement.rowCount, 3);
  assert.deepEqual(node.measurement.columnNullRows, [1]);
  const root = new URL('../../', import.meta.url).pathname;
  const wrapper = await build({stdin: {contents:
    `import {createWorkersFiniteRuntime} from './_build/workers/finite-runtime.mjs';\n` +
    `const consume = ${consumeOriginal.toString()};\n` +
    `export default {async fetch(request) {\n` +
    ` const input = JSON.parse(await request.text(), (_, value) => value && typeof value === 'object' && Object.keys(value).length === 1 && typeof value.bigint === 'string' ? BigInt(value.bigint) : value);\n` +
    ` return Response.json(await consume(createWorkersFiniteRuntime, input, ${JSON.stringify(limits)}));\n` +
    `}};`, resolveDir: root, sourcefile: 'production-roundtrip.mjs'},
    absWorkingDir: root, bundle: true, platform: 'browser', format: 'esm',
    target: 'es2022', write: false, metafile: true});
  const source = wrapper.outputFiles[0].text;
  checkWorkersArtifact(wrapper.metafile, source,
    ['_build/workers/finite-runtime.mjs', 'production-roundtrip.mjs']);
  const runtime = createTestRuntime(source);
  try {
    const response = await runtime.dispatchFetch('http://worker.test/', {method: 'POST',
      body: JSON.stringify(input, (_, value) => typeof value === 'bigint' ? {bigint: String(value)} : value)});
    assert.equal(response.status, 200, await response.clone().text());
    assert.deepEqual(await response.json(), node);
  } finally { await runtime.dispose(); }
  assert.ok(artifact.bytes > 0);
});


test('production finite artifact executes the explicitly selected numeric expression pipeline on workerd', async () => {
  await buildFiniteRuntime();
  const configuration = finiteExpressionConfiguration();
  configuration.environment.numeric_profile_cid = finiteNumericProfileCid;
  const document = JSON.parse(finiteCountDocument());
  document.stages[0].steps[3].group.aggregates.total = {fn: 'sum', field: 'net'};
  document.stages[0].results.rows.fields.push('total');
  const input = finiteExpressionInput(JSON.stringify(document), configuration);
  const root = new URL('../../', import.meta.url).pathname;
  const selectedLimits = {...limits, maxBatchBytes: 128};
  const wrapper = await build({stdin: {contents:
    `import {createWorkersFiniteRuntime} from './_build/workers/finite-runtime.mjs';\n` +
    `const consume = ${consumeOriginal.toString()};\n` +
    `export default {async fetch(request) {\n` +
    ` const input = JSON.parse(await request.text(), (_, value) => value && typeof value === 'object' && Object.keys(value).length === 1 && typeof value.bigint === 'string' ? BigInt(value.bigint) : value);\n` +
    ` return Response.json(await consume(createWorkersFiniteRuntime, input, ${JSON.stringify(selectedLimits)}));\n` +
    `}};`, resolveDir: root, sourcefile: 'production-expression.mjs'},
    absWorkingDir: root, bundle: true, platform: 'browser', format: 'esm',
    target: 'es2022', write: false, metafile: true});
  const source = wrapper.outputFiles[0].text;
  checkWorkersArtifact(wrapper.metafile, source,
    ['_build/workers/finite-runtime.mjs', 'production-expression.mjs']);
  const runtime = createTestRuntime(source);
  try {
    const response = await runtime.dispatchFetch('http://worker.test/', {method: 'POST',
      body: JSON.stringify(input, (_, value) => typeof value === 'bigint' ? {bigint: String(value)} : value)});
    assert.equal(response.status, 200, await response.clone().text());
    const result = await response.json();
    assert.deepEqual(result.rows, [{region: 'east', order_count: 2, total: 100},
      {region: 'west', order_count: 1, total: 60}]);
    assert.equal(result.measurement.rowCount, 2);
    assert.equal(runtime.outboundAttempts, 0);
  } finally { await runtime.dispose(); }
});
