// The two ordinary consumer processes share only the original Run reference
// and test evidence. Product imports resolve from the same npm installation.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {realpath, readFile, writeFile} from 'node:fs/promises';
import {join, resolve, sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import {setTimeout} from 'node:timers/promises';
import {open} from '@actql/node';
import {startExplorer} from '@actql/explorer/launcher';
import {createHostObservationConnection} from '@actql/local-node/observation';

const [phase, project, evidence] = process.argv.slice(2);
assert(['before', 'produce', 'restore'].includes(phase) && project && evidence);
const require = createRequire(import.meta.url), modules = resolve('node_modules') + sep;
for (const name of ['@actql/node', '@actql/explorer/launcher',
  '@actql/local-node/observation', '@actql/local-node/_internal/explanation-narrative']) {
  assert((await realpath(require.resolve(name))).startsWith(modules));
}

process.chdir(project);
const target = 'mock/data.json';
const targetDigest = async () => createHash('sha256').update(await readFile(target)).digest('hex');
const originalPath = join(evidence, 'saved-original.json');
const markers = [];
const observation = createHostObservationConnection({
  include: ['source', 'infer', 'effect'],
  deliver(record) {
    const {operation, event} = record;
    if ((operation === 'source' || operation === 'infer') && event === 'attempt_started' ||
        operation === 'effect' && (event === 'application_observed' || event === 'write_observed')) {
      markers.push({operation, event, run: record.attributes['actql.run.definition_cid'],
        outcome: record.attributes['actql.outcome']});
    }
  },
});
const client = await open({stateDir: '.actql-node', profile: 'mock', installation: {observation}});

function drained(status) {
  return status.queued === 0 && status.queuedBytes === 0 && status.active === 0 && status.activeSegments === 0;
}

function requireLosslessDrain(status, closed) {
  assert(status, 'The installed Host must own the selected Observation connection');
  assert.equal(status.closed, closed);
  assert.equal(status.cleanupPending, false);
  assert(drained(status), 'Observation queue, delivery and segments must all be drained');
  assert.equal(status.dropped, 0);
  assert.deepEqual(status.loss, {});
  return status;
}

async function drainBeforeClose() {
  const deadline = performance.now() + observation.configuration().limits.shutdownMs;
  let status = observation.status();
  while (status && !drained(status) && performance.now() < deadline) {
    await setTimeout(5);
    status = observation.status();
  }
  return requireLosslessDrain(status, false);
}

let receipt, expectedTarget, beforeClose, primary, gateway, browser;
try {
  if (phase === 'produce') {
    expectedTarget = await targetDigest();
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
    receipt = {producerPid: process.pid, ref: original.ref, saved, targetDigest: expectedTarget};
  } else {
    expectedTarget = await targetDigest();
    const original = phase === 'restore' ? JSON.parse(await readFile(originalPath, 'utf8')) : undefined;
    if (original) {
      assert.notEqual(process.pid, original.producerPid);
      assert(original.firstClose);
      assert.equal(expectedTarget, original.targetDigest);
      const execution = await client.attach(original.ref);
      assert.equal((await execution.status()).status, 'waiting_checkpoint');
      assert.deepEqual(await execution.explainContext(), original.saved);
      assert.deepEqual((await execution.explain()).explanation.facts, original.saved.explanation.view.facts);
    }

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
      assert.equal(await page.locator('input[name="bootstrap"], textarea[name="ref"]').count(), 0);
      const connect = async name => {
        await page.getByRole('button', {name, exact: true}).click();
        await page.getByLabel('One-use bootstrap').fill(gateway.issueBootstrap().bootstrap);
        await page.getByRole('button', {name: 'Connect', exact: true}).click();
        await page.locator('.connection-menu > summary').waitFor();
      };
      await connect('Connect to Local');
      if (original === undefined) {
        await page.getByLabel('Query options').click();
        await page.getByLabel('Open query file').setInputFiles(join(project, 'deal-review.aql'));
        await page.getByLabel('Query options').click();
        const checked = page.waitForResponse(response => response.url() === gateway.origin + '/api/read/static-explanation');
        await page.getByRole('button', {name: 'Explain Effect', exact: true}).click();
        const checkedResponse = await checked;
        assert.equal(checkedResponse.status(), 200);
        const {data: beforeRun} = await checkedResponse.json();
        assert.deepEqual(beforeRun.context.filter(item => item.origin.kind === 'source').map(item =>
          [item.origin.source_view.connector, item.origin.source_view.resource]), [
          ['salesforce', 'Opportunity'], ['drive', 'files'], ['drive', 'contents']]);
        const staticSteps = page.getByRole('region', {name: 'Original story', exact: true});
        await staticSteps.waitFor();
        assert.equal(await staticSteps.locator('details.story-card[open]').count(), 1);
        assert.match(await staticSteps.innerText(), /Planned/u);
        await page.screenshot({path: join(evidence, 'installed-deal-review-before-run.png')});
        assert.deepEqual(requests, ['/api/session', '/api/read/launch', '/api/read/static-explanation']);
        receipt = {browserRequests: requests, checkedSources: 3};
      } else {
        await page.getByLabel('Query options').click();
        await page.getByLabel('Open query file').setInputFiles(join(project, 'churn-risk.aql'));
        await page.getByLabel('Query options').click();
        const {plan, facts, context} = original.saved.explanation.view;
        const openOriginal = async () => {
          await page.getByRole('button', {name: 'Open Run', exact: true}).click();
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
          await page.getByRole('dialog', {name: 'Open Run'}).waitFor({state: 'hidden'});
        };
        await openOriginal();
        const story = page.getByRole('region', {name: 'Original story', exact: true});
        await story.waitFor();
        assert.match(await story.textContent(), /model-task:churn-risk\.v1/u);
        await page.getByText('Current status unavailable', {exact: true}).waitFor();
        assert.deepEqual(requests, ['/api/session', '/api/read/launch', '/api/read/run-explanation-context']);
        await page.screenshot({path: join(evidence, 'installed-saved-context.png')});
        await page.getByRole('button', {name: /Graph/}).click();
        const graph = page.getByRole('region', {name: 'ActQL static Plan', exact: true});
        const nextNode = graph.locator('.react-flow__node:not(:has([data-selected="true"]))').first();
        const originalStep = await nextNode.getAttribute('data-id');
        assert(originalStep);
        const node = graph.locator(`.react-flow__node[data-id="${originalStep}"]`);
        await node.click();
        await node.locator('[data-selected="true"]').waitFor();
        const step = page.getByRole('region', {name: 'Selected Step', exact: true});
        await step.waitFor();
        assert((await step.textContent()).includes(originalStep));
        await page.screenshot({path: join(evidence, 'installed-saved-graph.png')});
        await page.getByRole('button', {name: 'Steps', exact: true}).click();
        assert((await story.locator('details.story-card[data-selected="true"]').textContent()).includes(originalStep));
        await page.getByRole('button', {name: 'Open Run', exact: true}).click();
        await page.locator('textarea[name="ref"]').fill('{');
        await page.getByRole('button', {name: 'Open Saved explanation', exact: true}).click();
        await page.getByRole('alert').filter({hasText: 'Enter the complete original Run reference as JSON.'}).waitFor();
        await page.getByRole('button', {name: 'Close dialog', exact: true}).click();
        await story.waitFor();
        assert.equal(requests.length, 3);
        gateway.invalidateScope();
        await page.getByRole('button', {name: 'Inspect status', exact: true}).click();
        await page.getByRole('button', {name: 'Reconnect', exact: true}).waitFor();
        await story.waitFor({state: 'hidden'});
        assert.equal(await page.locator('input[name="bootstrap"], textarea[name="ref"]').count(), 0);
        await page.screenshot({path: join(evidence, 'installed-reconnect.png')});
        await connect('Reconnect');
        await openOriginal();
        await page.setViewportSize({width: 390, height: 844});
        await page.getByRole('button', {name: /Hide query/}).click();
        assert.equal(await page.locator('#query-pane').count(), 0);
        await page.getByRole('button', {name: /Show query/}).click();
        assert(await page.evaluate(() => document.documentElement.scrollWidth === window.innerWidth));
        await page.screenshot({path: join(evidence, 'installed-narrow.png')});
        assert.deepEqual(requests, ['/api/session', '/api/read/launch', '/api/read/run-explanation-context', '/api/read/observation', '/api/session', '/api/read/launch',
          '/api/read/run-explanation-context']);
        receipt = {producerPid: original.producerPid, consumerPid: process.pid, sameOriginal: true,
          browserRequests: requests};
      }
      assert.deepEqual(errors, []);
      assert.deepEqual(foreign, []);
    } finally {await page.close();}
  }
  beforeClose = await drainBeforeClose();
} catch (error) {primary = error;}
finally {
  for (const owner of [browser, gateway, client]) {
    try {await owner?.close();}
    catch (error) {primary = primary === undefined ? error :
      new AggregateError([primary, error], 'Saved Context consumer cleanup failed');}
  }
}
if (primary !== undefined) throw primary;
const afterClose = requireLosslessDrain(observation.status(), true);
assert.equal(await targetDigest(), expectedTarget, 'The original target must stay unchanged through close');
if (phase === 'produce') {
  assert.equal(markers.filter(item => item.operation === 'source').length, 2);
  assert(markers.every(item => item.run === receipt.ref.runDefinitionCid));
  assert(markers.some(item => item.operation === 'infer'), 'Original Run must witness an Infer start');
  assert(markers.some(item => item.operation === 'effect'), 'Original Run must witness an Effect application');
  assert(markers.every(item => item.operation !== 'effect' ||
    item.event === 'application_observed' && item.outcome === 'waiting_checkpoint'));
  receipt.attempts = markers;
} else {
  assert.deepEqual(markers, [], 'Saved read must start no Source or Infer and observe no Effect application or write');
  receipt.newBusinessAttempts = markers.length;
}
await writeFile(phase === 'produce' ? originalPath : join(evidence, phase === 'before' ? 'before-run-receipt.json' : 'saved-context-receipt.json'),
  JSON.stringify({...receipt, targetUnchanged: true, firstClose: true,
    observation: {beforeClose, afterClose}}) + '\n', {flag: 'wx'});
