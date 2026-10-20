import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {realpath, readFile, writeFile} from 'node:fs/promises';
import {resolve, sep} from 'node:path';
import {open} from '@actql/node';
import {startExplorer, openLocalExplorer} from '@actql/explorer/launcher';
import {createExplorerBrowserSource} from '@actql/explorer/browser-source';

const require = createRequire(import.meta.url), modules = resolve('node_modules') + sep;
for (const name of ['@actql/node', '@actql/sdk', '@actql/explorer/launcher',
  '@actql/explorer-ui/plan-explorer', 'react', 'react-dom']) {
  assert((await realpath(require.resolve(name))).startsWith(modules), 'Installed consumer owns every entry');
}
const client = await open({stateDir: 'state'});
let gateway;
try {
  const result = await client.sql('SELECT 1 AS answer');
  assert.deepEqual(await result.all(), [{answer: 1}]);
  const execution = result.execution, ref = execution.ref;
  const original = await execution.inspect();
  const savedPlan = await execution.plan();
  assert.deepEqual(savedPlan.run_ref, ref);
  assert.equal(savedPlan.plan_view.provider_io, 0);
  assert(savedPlan.plan_view.logical_map.steps.some(step => step.operator === 'values'));
  const directPlan = await client.plan('SELECT 1 AS answer', {format: 'sql'});
  gateway = await startExplorer({client});
  const page = await fetch(gateway.origin), html = await page.text();
  assert.equal(page.status, 200); assert.match(html, /ActQL Explorer/u);
  assert.equal(page.headers.get('cache-control'), 'no-store');
  const assets = [...html.matchAll(/(?:src|href)="(\/assets\/[a-zA-Z0-9_-]+\.(?:js|css))"/gu)].map(v => v[1]);
  assert.equal(assets.length, 2);
  for (const path of assets) {
    const response = await fetch(gateway.origin + path); assert.equal(response.status, 200);
    const body = await response.text(); assert(body.length > 1000);
    assert(!body.includes('/@vite/client')); if (path.endsWith('.js')) assert.match(body, /Read Plan/u);
  }
  assert.equal((await fetch(gateway.origin + '/../../package.json')).status, 404);
  let cookie;
  const source = createExplorerBrowserSource({origin: gateway.origin, async fetch(url, options) {
    const response = await fetch(url, {...options, headers: {...options.headers,
      Origin: gateway.origin, ...(cookie ? {Cookie: cookie} : {})}});
    const installed = response.headers.get('set-cookie');
    if (installed) cookie = installed.split(';')[0];
    return response;
  }});
  try {
    const capabilities = await source.connect(gateway.issueBootstrap().bootstrap);
    assert.deepEqual(capabilities, {plan: true, run: true, resultMetadata: true,
      resultPayload: false, control: false, sample: false, cancellation: false,
      checkpointList: true, checkpointReview: true});
    const plan = await source.plan('SELECT 1 AS answer', {format: 'sql'});
    assert.equal(plan.compiledPlanCid, directPlan.compiled_plan_cid);
    assert.deepEqual(plan.nodes.map(n => [n.id, n.ports]),
      directPlan.logical_map.steps.map(s => [s.step_id, s.ports]));
    assert(plan.nodes.some(n => n.operator === 'values'));
    assert.deepEqual(plan.sourceOrigins, {state: 'unavailable', reason: 'not_in_projection'});
    const view = await source.inspect(ref);
    assert.deepEqual(view.run_ref, ref); assert.equal(view.run_state.run_id, original.run_state.run_id);
    assert.equal(view.run_state.status, 'succeeded'); assert.equal(view.consistency, 'non_atomic');
    const retained = await source.runPlan(ref);
    assert.deepEqual(retained.runRef, ref);
    assert.equal(retained.plan.compiledPlanCid, savedPlan.plan_view.compiled_plan_cid);
    assert.equal(retained.plan.logicalMapCid, savedPlan.plan_view.logical_map.self_cid);
    assert.deepEqual(retained.plan.nodes.map(n => [n.id, n.ports]),
      savedPlan.plan_view.logical_map.steps.map(s => [s.step_id, s.ports]));
    // A different new static Plan cannot replace this original Run's map.
    const changed = await source.plan('SELECT 999 AS changed', {format: 'sql'});
    assert.notEqual(changed.compiledPlanCid, retained.plan.compiledPlanCid);
    assert.equal((await source.runPlan(ref)).plan.logicalMapCid, retained.plan.logicalMapCid);
    const description = await source.describe(ref, result.ref.resultName);
    assert.deepEqual(description.columns, [{name: 'answer', contract: {type: 'number', nullable: false}}]);
    source.close(); await assert.rejects(source.inspect(ref), {code: 'ExplorerSessionExpired'});
  } finally {source.close();}
  await gateway.close(); gateway = undefined;
  assert.equal((await execution.status()).status, 'succeeded', 'Borrowed Client and Run remain live');
  assert.deepEqual(await result.all(), [{answer: 1}]);
  await writeFile('original-run.json', JSON.stringify(ref));
  await writeFile('original-plan.json', JSON.stringify(savedPlan));
  const owned = await openLocalExplorer({local: {stateDir: 'state'}});
  try {assert.equal((await fetch(owned.origin)).status, 200);}
  finally {await owned.close();}
  assert.equal((await execution.status()).status, 'succeeded', 'Existing shared Node lease remains authoritative');
  console.log(JSON.stringify({profile: 'installed-read-only-source-free', rows: [{answer: 1}],
    runRef: ref, runId: original.run_state.run_id, originalPorts: true,
    staticProviderIO: 0, unavailable: ['control', 'sample', 'resultPayload', 'sourceOrigins'],
    savedOriginalPlan: true,
    actualBuiltAssets: assets.length, borrowedClientStillUsable: true}));
} finally {await gateway?.close(); await client.close();}
const reopened = await open({stateDir: 'state'});
try {
  const execution = await reopened.attach(JSON.parse(await readFile('original-run.json', 'utf8')));
  assert.equal((await execution.status()).status, 'succeeded', 'Viewer closure never cancels retained Run');
  const expected = JSON.parse(await readFile('original-plan.json', 'utf8'));
  const restored = await execution.plan();
  assert.deepEqual(restored.run_ref, expected.run_ref);
  assert.equal(restored.plan_view.compiled_plan_cid, expected.plan_view.compiled_plan_cid);
  assert.deepEqual(restored.plan_view.logical_map, expected.plan_view.logical_map);
} finally {await reopened.close();}
