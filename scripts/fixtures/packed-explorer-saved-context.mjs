// The two ordinary consumer processes share only the original Run reference
// and test evidence. Product imports resolve from the same npm installation.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {realpath, readFile, writeFile} from 'node:fs/promises';
import {join, resolve, sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import {setImmediate} from 'node:timers/promises';
import {open} from '@actql/node';
import {startExplorer} from '@actql/explorer/launcher';
import {createHostObservationConnection} from '@actql/local-node/observation';

const [phase, project, evidence] = process.argv.slice(2);
assert((phase === 'produce' || phase === 'restore') && project && evidence);
const require = createRequire(import.meta.url), modules = resolve('node_modules') + sep;
for (const name of ['@actql/node', '@actql/explorer/launcher',
  '@actql/local-node/observation', '@actql/local-node/_internal/explanation-narrative']) {
  assert((await realpath(require.resolve(name))).startsWith(modules));
}

process.chdir(project);
const target = 'mock/data.json';
const targetDigest = async () => createHash('sha256').update(await readFile(target)).digest('hex');
const originalPath = join(evidence, 'saved-original.json');
const operations = new Set(['source', 'model', 'effect']);
const attempts = [];
const client = await open({stateDir: '.actql-node', profile: 'mock', installation: {
  observation: createHostObservationConnection({deliver(record) {
    if (record.event === 'attempt_started' && operations.has(record.operation)) {
      attempts.push({operation: record.operation, run: record.attributes['actql.run.definition_cid']});
    }
  }}),
}});

let receipt, primary, gateway, browser;
try {
  if (phase === 'produce') {
    const digest = await targetDigest();
    const program = await readFile('churn-risk.aql', 'utf8');
    const original = await client.startSource(program, {format: 'aql', stopBefore: 'commit'});
    assert.equal((await original.wait()).status, 'waiting_checkpoint');
    const saved = await original.explainContext();
    assert.deepEqual(saved.run_ref, original.ref);
    assert.equal(saved.explanation.state, 'projected');
    const {plan, facts, context} = saved.explanation.view;
    assert.deepEqual(context.items.map(item => item.kind), ['source', 'source', 'model_task', 'result', 'effect_set']);
    assert.equal(context.binding.logical_map_cid, plan.logical_map.self_cid);
    assert.equal(facts.logical_map_cid, plan.logical_map.self_cid);
    assert.deepEqual((await original.explain()).explanation.facts, facts);
    for (let turn = 0; turn < 512 && attempts.filter(item => item.operation === 'source').length < 2;
      turn++) await setImmediate();
    assert.equal(attempts.filter(item => item.operation === 'source').length, 2);
    assert(attempts.every(item => item.operation !== 'effect' && item.run === original.ref.runDefinitionCid));
    assert.equal(await targetDigest(), digest);
    receipt = {producerPid: process.pid, ref: original.ref, saved, targetDigest: digest, attempts};
  } else {
    const original = JSON.parse(await readFile(originalPath, 'utf8'));
    assert.notEqual(process.pid, original.producerPid);
    assert(original.firstClose);
    const execution = await client.attach(original.ref);
    assert.equal((await execution.status()).status, 'waiting_checkpoint');
    assert.deepEqual(await execution.explainContext(), original.saved);
    const {plan, facts, context} = original.saved.explanation.view;
    assert.deepEqual((await execution.explain()).explanation.facts, facts);

    const browserModule = process.env.ACTQL_TEST_PLAYWRIGHT_MODULE;
    const executablePath = process.env.ACTQL_TEST_BROWSER_EXECUTABLE;
    assert(browserModule && executablePath, 'Explicit browser tooling required');
    const {chromium} = await import(pathToFileURL(browserModule));
    gateway = await startExplorer({client});
    browser = await chromium.launch({headless: true, executablePath});
    const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
    page.setDefaultTimeout(10000);
    const requests = [], errors = [];
    page.on('pageerror', error => errors.push(error.name));
    page.on('request', request => {
      const url = new URL(request.url());
      if (url.pathname.startsWith('/api/')) requests.push(url.pathname);
    });
    const foreign = [];
    await page.route('**/*', route => {
      if (new URL(route.request().url()).origin === gateway.origin) return route.continue();
      foreign.push('foreign origin refused');
      return route.abort();
    });
    try {
      await page.goto(gateway.origin, {waitUntil: 'networkidle'});
      await page.getByLabel('One-use bootstrap').fill(gateway.issueBootstrap().bootstrap);
      await page.getByRole('button', {name: 'Connect', exact: true}).click();
      await page.getByText('Gateway connected', {exact: true}).waitFor();
      await page.getByText('Open Run', {exact: true}).click();
      await page.locator('textarea[name="ref"]').fill(JSON.stringify(original.ref));
      const reply = page.waitForResponse(response =>
        response.url() === gateway.origin + '/api/read/run-explanation-context');
      await page.getByRole('button', {name: 'Open Saved explanation', exact: true}).click();
      const response = await reply;
      assert.equal(response.status(), 200);
      const {data} = await response.json();
      assert.deepEqual(data.runRef, original.ref);
      assert.equal(data.plan.compiledPlanCid, plan.compiled_plan_cid);
      assert.equal(data.plan.logicalMapCid, plan.logical_map.self_cid);
      assert.equal(data.explanation.story.factsCid, facts.self_cid);
      assert.deepEqual(data.explanation.context.map(item => item.origin), context.items);
      const story = page.getByRole('region', {name: 'Original story', exact: true});
      await story.waitFor();
      assert.match(await story.textContent(), /model-task:churn-risk\.v1/u);
      await page.getByText('Current status unavailable', {exact: true}).waitFor();
      assert.deepEqual(requests, ['/api/session', '/api/read/launch', '/api/read/run-explanation-context']);
      assert.deepEqual(errors, []);
      assert.deepEqual(foreign, []);
      await page.screenshot({path: join(evidence, 'installed-saved-context.png')});
    } finally {await page.close();}
    await setImmediate();
    assert.deepEqual(attempts, []);
    assert.equal(await targetDigest(), original.targetDigest);
    receipt = {producerPid: original.producerPid, consumerPid: process.pid, sameOriginal: true,
      newBusinessAttempts: attempts.length, targetUnchanged: true, browserRequests: requests};
  }
} catch (error) {primary = error;}
finally {
  for (const owner of [browser, gateway, client]) {
    try {await owner?.close();}
    catch (error) {primary = primary === undefined ? error :
      new AggregateError([primary, error], 'Saved Context consumer cleanup failed');}
  }
}
if (primary !== undefined) throw primary;
await writeFile(phase === 'produce' ? originalPath : join(evidence, 'saved-context-receipt.json'),
  JSON.stringify({...receipt, firstClose: true}) + '\n', {flag: 'wx'});
