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
    const launchInput = phase === 'before' ? {kind: 'program', format: 'sql', text: 'SELECT 7 AS launcher_plan'} : undefined;
    gateway = await startExplorer({client, launchInput});
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
        await page.getByText('The launcher supplied the Plan. Edits here apply to a future Run.', {exact: true}).waitFor();
        assert.match(await page.getByRole('list', {name: 'Query text'}).innerText(), /SELECT 1 AS answer/u);
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
        assert.equal(await page.locator('.query-scope-note').count(), 0);
        assert.equal(await staticSteps.locator('details.story-card[open]').count(), 1);
        assert.match(await staticSteps.innerText(), /Planned/u);
        const heading = page.getByRole('heading', {level: 1});
        const summary = await heading.innerText();
        for (const proof of ['Opportunity', 'files', 'contents', 'deal-review.v1', 'updates', 'StageName', 'NextStep']) {
          assert(summary.includes(proof), proof);
        }
        assert.match(summary, /StageName and NextStep on Opportunity in salesforce/u);
        assert.doesNotMatch(summary, /connector:\/\/|\baql_|Predicate form not projected/u);
        const computation = await page.locator('.story-computation').innerText();
        const checkedJoins = beforeRun.story.occurrences.flatMap(({explanation})=>
          explanation.meaning.kind === 'join' ? [explanation.meaning] : []);
        assert.equal(checkedJoins.length, 3);
        assert(checkedJoins.some(join=>join.keys.some(key=>key.left === 'name' && key.right === 'name')));
        assert.match(computation, /3 checked joins, including a join on name/u);
        assert.match(computation, /Filter rows|Keep rows where/u);
        assert.doesNotMatch(computation, /\baql_|Predicate form not projected/u);
        const titles = await staticSteps.locator('summary > strong').allTextContents();
        assert(titles.includes('Input · Opportunity') && titles.includes('Input · files'));
        assert(titles.every(title=>!title.includes('aql_capture_0')));
        const inputTitle = page.locator('summary > strong').filter({hasText: /^Input · Opportunity$/u});
        await inputTitle.click();
        const original = staticSteps.locator('details.story-card[open]').filter({has: inputTitle});
        await original.getByText('Original step and ports', {exact: true}).click();
        await original.getByText('aql_capture_0', {exact: true}).waitFor();
        await inputTitle.click();
        await page.screenshot({path: join(evidence, 'installed-deal-review-before-run.png')});
        await page.getByRole('button', {name: /Graph/}).click();
        const graph = page.getByRole('region', {name: 'ActQL static Plan', exact: true});
        const cards = graph.locator('.react-flow__node');
        const rendered = ids => cards.evaluateAll((nodes, selected) => {
          const panel = nodes[0]?.closest('.actql-explorer-flow')?.getBoundingClientRect();
          if (!panel) return [];
          return nodes.filter(node=>{
            const box = node.getBoundingClientRect();
            return selected.includes(node.getAttribute('data-id')) && box.width >= 230 &&
              box.left >= panel.left && box.right <= panel.right &&
              box.top >= panel.top && box.bottom <= Math.min(panel.bottom, window.innerHeight);
          }).map(node=>node.getAttribute('data-id'));
        }, ids);
        await graph.locator('.react-flow__node:has([data-selected="true"])').waitFor();
        await page.waitForFunction(() => {
          const viewport = document.querySelector('.react-flow__viewport');
          return viewport && new DOMMatrixReadOnly(getComputedStyle(viewport).transform).a >= 0.89;
        });
        const {nodes, edges} = beforeRun.plan;
        assert.deepEqual((await cards.evaluateAll(items=>items.map(item=>item.getAttribute('data-id')))).sort(),
          nodes.map(node=>node.id).sort());
        assert.deepEqual((await graph.locator('.react-flow__edge').evaluateAll(items=>
          items.map(item=>item.getAttribute('data-testid')))).sort(), edges.map(edge=>`rf__edge-${edge.id}`).sort());
        const visible = new Set(await rendered(nodes.map(node=>node.id)));
        await page.screenshot({path: join(evidence, 'installed-deal-review-graph.png')});
        const visibleInputs = beforeRun.context.flatMap(({origin})=>origin.kind === 'source'
          ? origin.consuming_ports.filter(port=>visible.has(port.step_id)).map(port=>({...port,
            resource: origin.source_view.resource, connector: origin.source_view.connector, locator: origin.stage_input}))
          : []);
        const visibleInputNames = [...new Set(visibleInputs.map(input=>input.resource))];
        assert(visibleInputNames.length >= 2, `Visible checked inputs: ${visibleInputNames.join(', ')}`);
        const visibleJoins = nodes.filter(node=>node.operator === 'join' && visible.has(node.id));
        assert(visibleJoins.length > 0, 'A checked Join should be readable in the opening Graph');
        await graph.getByText('Declared inputs', {exact: true}).waitFor();
        const groupedInputs = await graph.locator('.actql-explorer-node[data-unlinked-input=true]').evaluateAll(items=>
          items.map(node=>({id: node.closest('.react-flow__node').getAttribute('data-id'),
            text: node.textContent, top: node.getBoundingClientRect().top,
            bottom: node.getBoundingClientRect().bottom})));
        assert.equal(groupedInputs.length, 2);
        assert(groupedInputs.some(node=>node.text.includes('Opportunity')));
        assert(groupedInputs.some(node=>node.text.includes('files')));
        assert(groupedInputs.every(node=>visible.has(node.id) && node.text.includes('Downstream link not projected') &&
          !edges.some(edge=>edge.sourceStepId === node.id || edge.targetStepId === node.id)));
        assert(Math.abs(groupedInputs[0].top - groupedInputs[1].top) < 2);
        for (const join of visibleJoins) {
          const rect = await graph.locator(`.react-flow__node[data-id="${join.id}"]`).boundingBox();
          assert(groupedInputs.every(input=>input.bottom < rect.y));
        }
        for (const input of visibleInputs) {
          const port = nodes.find(node=>node.id === input.step_id).ports.find(port=>port.port_id === input.port_id);
          assert.equal(port.role, 'input');
          assert.deepEqual(port.source, input.locator);
          const card = graph.locator(`.react-flow__node[data-id="${input.step_id}"]`);
          assert((await card.textContent()).includes(input.resource), `Missing label on ${input.resource}'s original node`);
        }
        const connections = edges.filter(edge=>visible.has(edge.sourceStepId) && visible.has(edge.targetStepId));
        function visibleRoute(start, finish) {
          const queue = [{step: start, route: []}], visited = new Set([start]);
          for (const {step, route} of queue) {
            if (step === finish) return route;
            for (const edge of connections.filter(edge=>edge.sourceStepId === step)) {
              if (visited.has(edge.targetStepId)) continue;
              visited.add(edge.targetStepId);
              queue.push({step: edge.targetStepId, route: [...route, edge]});
            }
          }
        }
        const visibleConvergence = visibleJoins.map(join=>visibleInputs.flatMap(input=>{
          const route = visibleRoute(input.step_id, join.id);
          return route?.length ? [{resource: input.resource, connector: input.connector,
            originalInputPort: input.port_id, route}] : [];
        })).find(routes=>new Set(routes.map(route=>route.resource)).size >= 2);
        // An original Stage input can bind a Join directly, without a
        // projected producer Step. Do not require or draw a synthetic edge.
        const shownDirectInputs = visibleInputs.filter(input=>visibleJoins.some(join=>join.id === input.step_id));
        const drawnJoinEdges = visibleConvergence ? visibleConvergence.flatMap(origin=>origin.route) :
          connections.filter(edge=>visibleJoins.some(join=>join.id === edge.targetStepId) &&
            shownDirectInputs.some(input=>input.step_id === edge.sourceStepId || input.step_id === edge.targetStepId));
        assert(visibleConvergence || shownDirectInputs.length > 0 && drawnJoinEdges.length > 0,
          'Check two connected Source paths, or a direct original Join input beside a drawn Join dependency');
        for (const edge of drawnJoinEdges) {
          const path = graph.getByTestId(`rf__edge-${edge.id}`).locator('.react-flow__edge-path');
          assert(await path.evaluate(path=>path.getTotalLength() > 0));
          const from = nodes.find(node=>node.id === edge.sourceStepId).ports.find(port=>port.port_id === edge.sourcePortId);
          const to = nodes.find(node=>node.id === edge.targetStepId).ports.find(port=>port.port_id === edge.targetPortId);
          assert.equal(from.role, 'output');
          assert.equal(to.role, 'input');
          assert.deepEqual(to.source, {kind: 'logical_output', step_id: edge.sourceStepId, output_port_id: edge.sourcePortId});
        }
        const graphText = (await cards.allTextContents()).join('\n');
        assert.match(graphText, /Join · /u);
        assert.doesNotMatch(graphText, /\baql_|connector:\/\//u);
        await page.getByRole('button', {name: 'Steps', exact: true}).click();
        await page.setViewportSize({width: 390, height: 844});
        assert.equal(await heading.innerText(), summary);
        assert.equal(await page.locator('.story-computation').innerText(), computation);
        assert((await heading.boundingBox()).height < 230);
        assert(await page.evaluate(() => document.documentElement.scrollWidth === window.innerWidth));
        await page.screenshot({path: join(evidence, 'installed-deal-review-narrow.png')});
        await page.getByLabel('Query options').click();
        await page.getByLabel('Language', {exact: true}).selectOption('ja');
        await page.getByLabel('Query options').click();
        await page.getByRole('button', {name: 'Explain Effect', exact: true}).click();
        await page.locator('.story-computation').filter({hasText: /3回の結合（name で結合する箇所を含む）/u}).waitFor();
        assert(await page.evaluate(() => document.documentElement.scrollWidth === window.innerWidth));
        await page.screenshot({path: join(evidence, 'installed-deal-review-narrow-ja.png')});
        assert.deepEqual(requests, ['/api/session', '/api/read/launch', '/api/read/static-explanation',
          '/api/read/static-explanation']);
        receipt = {browserRequests: requests, checkedSources: 3, visibleInputNames, visibleJoins: visibleJoins.length,
          originalGraphNodes: nodes.length, originalGraphEdges: edges.length, visibleConvergence,
          shownDirectInputs, drawnJoinEdges, groupedInputs, computation};
      } else {
        await page.getByLabel('Query options').click();
        await page.getByLabel('Open query file').setInputFiles(join(project, 'churn-risk.aql'));
        await page.getByLabel('Query options').click();
        const {plan, facts, context} = original.saved.explanation.view;
        const openOriginal = async verifyOriginalBody => {
          await page.getByRole('button', {name: 'Open Run', exact: true}).click();
          await page.locator('textarea[name="ref"]').fill(JSON.stringify(original.ref));
          const reply = page.waitForResponse(response =>
            response.url() === gateway.origin + '/api/read/run-explanation-context');
          await page.getByRole('button', {name: 'Open Saved explanation', exact: true}).click();
          const response = await reply;
          assert.equal(response.status(), 200);
          if (verifyOriginalBody) {
            const {data} = await response.json();
            assert.deepEqual(data.runRef, original.ref);
            assert.equal(data.plan.compiledPlanCid, plan.compiled_plan_cid);
            assert.equal(data.plan.logicalMapCid, plan.logical_map.self_cid);
            assert.equal(data.explanation.story.factsCid, facts.self_cid);
            assert.deepEqual(data.explanation.context.map(item => item.origin), context.items);
          }
          await page.getByRole('dialog', {name: 'Open Run'}).waitFor({state: 'hidden'});
          const heading = page.locator('.story-heading .eyebrow');
          assert((await heading.textContent()).includes(original.ref.runDefinitionCid.slice(7, 19)));
        };
        await openOriginal(true);
        const story = page.getByRole('region', {name: 'Original story', exact: true});
        await story.waitFor();
        assert.match(await story.textContent(), /model-task:churn-risk\.v1/u);
        await page.getByText('This Run keeps its original query. Edits here apply to a future Run.', {exact: true}).waitFor();
        await page.getByText('Current status unavailable', {exact: true}).waitFor();
        assert.deepEqual(requests, ['/api/session', '/api/read/launch', '/api/read/run-explanation-context']);
        await page.screenshot({path: join(evidence, 'installed-saved-context.png')});
        const narrative = await page.getByRole('heading', {level: 1}).textContent();
        await page.getByRole('button', {name: 'Edit', exact: true}).click();
        const separateDraft = 'SELECT 2 AS draft_only';
        await page.getByRole('textbox', {name: 'Program', exact: true}).fill(separateDraft);
        await page.getByRole('button', {name: 'Done', exact: true}).click();
        assert.equal(await page.getByRole('list', {name: 'Query text'}).innerText(), separateDraft);
        assert.equal(await page.getByRole('heading', {level: 1}).textContent(), narrative);
        await page.getByRole('button', {name: /Graph/}).click();
        const graph = page.getByRole('region', {name: 'ActQL static Plan', exact: true});
        const initial = graph.locator('.react-flow__node:has([data-selected="true"])');
        await initial.waitFor();
        await page.waitForFunction(() => {
          const viewport = document.querySelector('.react-flow__viewport');
          return viewport && new DOMMatrixReadOnly(getComputedStyle(viewport).transform).a >= 0.89;
        });
        const defaultStep = await initial.getAttribute('data-id');
        const firstBounds = await initial.boundingBox();
        assert(firstBounds.width >= 230 && firstBounds.x >= 0 && firstBounds.x + firstBounds.width <= 1440);
        await page.screenshot({path: join(evidence, 'installed-saved-graph.png')});
        await graph.getByRole('button', {name: /fit view/iu}).click();
        const nextNode = graph.locator('.react-flow__node:not(:has([data-selected="true"]))').first();
        const originalStep = await nextNode.getAttribute('data-id');
        assert(originalStep && originalStep !== defaultStep);
        const node = graph.locator(`.react-flow__node[data-id="${originalStep}"]`);
        await node.click();
        await node.locator('[data-selected="true"]').waitFor();
        const step = page.getByRole('region', {name: 'Selected Step', exact: true});
        await step.waitFor();
        assert((await step.textContent()).includes(originalStep));
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
        await openOriginal(false);
        await story.waitFor();
        assert.match(await story.textContent(), /model-task:churn-risk\.v1/u);
        assert.equal(await page.getByRole('list', {name: 'Query text'}).innerText(), separateDraft);
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
