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
import type {WireRunExplanationContextView} from '@actql/client-wire';
import type {SavedExplanationReadModel, StaticExplanationReadModel} from '@actql/explorer-ui/read-model';
import type {RunReference} from '@actql/sdk';
import type {Browser, BrowserModule} from './packed-explorer-browser.mjs';

type Gateway = Awaited<ReturnType<typeof startExplorer>>;
type Observation = ReturnType<typeof createHostObservationConnection>;
type ObservationStatus = NonNullable<ReturnType<Observation['status']>>;
type ObservationRecord = Parameters<Parameters<typeof createHostObservationConnection>[0]['deliver']>[0];
type AttributeValue = ObservationRecord['attributes'][string];
type Marker = Pick<ObservationRecord, 'event' | 'operation'> & {run: AttributeValue; outcome: AttributeValue};
type ProducedRun = {
  producerPid: number;
  ref: RunReference;
  saved: WireRunExplanationContextView;
  targetDigest: string;
};
type Capture = {locale: 'en' | 'ja'; width: 1440 | 390; file: string};
type BeforeReceipt = {browserRequests: string[]; checkedSources: number; checkedJoinSteps: number;
  originalLogicalSteps: number; groupedGraphNodes: number;
  originalStageResultLinks: NonNullable<StaticExplanationReadModel['plan']['stageResultLinks']>; queryClosed: Capture[]};
type RestoredReceipt = {producerPid: number; consumerPid: number; sameOriginal: true; browserRequests: string[];
  queryClosed?: Capture[]};

const [phase, project, evidence, scenario] = process.argv.slice(2);
assert(['before', 'produce', 'restore'].includes(phase) && project && evidence);
assert(scenario === undefined || scenario === 'deal-review');
const dealReview = scenario === 'deal-review';
const programFile = dealReview ? 'deal-review.aql' : 'churn-risk.aql';
const require = createRequire(import.meta.url), modules = resolve('node_modules') + sep;
for (const name of ['@actql/node', '@actql/explorer/launcher',
  '@actql/local-node/observation', '@actql/local-node/_internal/explanation-narrative']) {
  assert((await realpath(require.resolve(name))).startsWith(modules));
}

process.chdir(project);
const target = 'mock/data.json';
const targetDigest = async () => createHash('sha256').update(await readFile(target)).digest('hex');
const originalPath = join(evidence, 'saved-original.json');
const markers: Marker[] = [];
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

function drained(status: ObservationStatus) {
  return status.queued === 0 && status.queuedBytes === 0 && status.active === 0 && status.activeSegments === 0;
}

function requireLosslessDrain(status: ObservationStatus | undefined, closed: boolean) {
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

let receipt: ProducedRun | BeforeReceipt | RestoredReceipt | undefined;
let expectedTarget: string | undefined, beforeClose: ObservationStatus | undefined, primary: unknown;
let gateway: Gateway | undefined, browser: Browser | undefined;
try {
  if (phase === 'produce') {
    expectedTarget = await targetDigest();
    const program = await readFile(programFile, 'utf8');
    const original = await client.startSource(program, {format: 'aql', stopBefore: 'commit'});
    assert.equal((await original.wait()).status, 'waiting_checkpoint');
    const saved = await original.explainContext();
    assert.deepEqual(saved.run_ref, original.ref);
    assert.equal(saved.explanation.state, 'projected');
    const {plan, facts, context} = saved.explanation.view;
    assert.deepEqual(context.items.map(item => item.kind), dealReview
      ? ['source', 'source', 'source', 'model_task', 'result', 'effect_set']
      : ['source', 'source', 'model_task', 'result', 'effect_set']);
    assert.equal(context.binding.logical_map_cid, plan.logical_map.self_cid);
    assert.equal(facts.logical_map_cid, plan.logical_map.self_cid);
    const explanation = (await original.explain()).explanation;
    assert.equal(explanation.state, 'projected');
    assert.deepEqual(explanation.facts, facts);
    receipt = {producerPid: process.pid, ref: original.ref, saved, targetDigest: expectedTarget};
  } else {
    expectedTarget = await targetDigest();
    const original: (ProducedRun & {firstClose: true}) | undefined =
      phase === 'restore' ? JSON.parse(await readFile(originalPath, 'utf8')) : undefined;
    if (original) {
      assert.notEqual(process.pid, original.producerPid);
      assert(original.firstClose);
      assert.equal(expectedTarget, original.targetDigest);
      const execution = await client.attach(original.ref);
      assert.equal((await execution.status()).status, 'waiting_checkpoint');
      assert.deepEqual(await execution.explainContext(), original.saved);
      const explanation = (await execution.explain()).explanation;
      assert.equal(explanation.state, 'projected');
      assert.equal(original.saved.explanation.state, 'projected');
      assert.deepEqual(explanation.facts, original.saved.explanation.view.facts);
    }

    const browserModule = process.env.ACTQL_TEST_PLAYWRIGHT_MODULE;
    const executablePath = process.env.ACTQL_TEST_BROWSER_EXECUTABLE;
    assert(browserModule && executablePath, 'Explicit browser tooling required');
    const {chromium}: BrowserModule = await import(pathToFileURL(browserModule).href);
    const launchInput = phase === 'before' ? {kind: 'program', format: 'sql', text: 'SELECT 7 AS launcher_plan'} as const : undefined;
    const connected = gateway = await startExplorer({client, launchInput});
    browser = await chromium.launch({headless: true, executablePath});
    const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
    page.setDefaultTimeout(10000);
    const requests: string[] = [], errors: string[] = [];
    page.on('pageerror', error => errors.push(error.name));
    page.on('request', request => {
      const url = new URL(request.url());
      if (url.pathname.startsWith('/api/')) requests.push(url.pathname);
    });
    const foreign: string[] = [], explanations = new Map<string, unknown>();
    await page.route('**/*', async route => {
      const {origin, pathname} = new URL(route.request().url());
      if (origin !== connected.origin) {
        foreign.push('foreign origin refused');
        return route.abort();
      }
      if (pathname === '/api/read/static-explanation' || pathname === '/api/read/run-explanation-context') {
        // Chromium may dispose the network body after adopting the view.
        // Capture the one original loopback response before delivering it.
        const response = await route.fetch({maxRetries: 0, maxRedirects: 0});
        explanations.set(pathname, await response.json());
        return route.fulfill({response});
      }
      return route.continue();
    });
    try {
      await page.goto(gateway.origin, {waitUntil: 'networkidle'});
      assert.equal(await page.locator('input[name="bootstrap"], textarea[name="ref"]').count(), 0);
      const connect = async (name: string) => {
        await page.getByRole('button', {name, exact: true}).click();
        await page.getByLabel('One-use bootstrap').fill(connected.issueBootstrap().bootstrap);
        await page.getByRole('button', {name: 'Connect', exact: true}).click();
        await page.locator('.connection-menu > summary').waitFor();
      };
      await connect('Connect to Local');
      const captureClosedSteps = async (locale: Capture['locale'], width: Capture['width'], file: string) => {
        await page.setViewportSize({width, height: width === 390 ? 844 : 1000});
        const pane = page.locator('#query-pane');
        if (await pane.count()) await page.getByRole('button', {name: /Hide query|クエリを隠す/u}).click();
        await pane.waitFor({state: 'hidden'});
        await page.evaluate(() => window.scrollTo(0, 0));
        assert(await page.evaluate(() => document.documentElement.scrollWidth === window.innerWidth));
        assert.equal(await page.locator('html').getAttribute('lang'), locale);
        await page.screenshot({path: join(evidence, file)});
        return {locale, width, file};
      };
      if (original === undefined) {
        await page.getByText('The launcher supplied the Plan. Edits here apply to a future Run.', {exact: true}).waitFor();
        assert.match(await page.getByRole('list', {name: 'Query text'}).innerText(), /SELECT 1 AS answer/u);
        await page.getByLabel('Query options').click();
        await page.getByLabel('Open query file').setInputFiles(join(project, 'deal-review.aql'));
        await page.getByLabel('Query options').click();
        const checked = page.waitForResponse(response => response.url() === connected.origin + '/api/read/static-explanation');
        await page.getByRole('button', {name: 'Explain', exact: true}).click();
        const checkedResponse = await checked;
        assert.equal(checkedResponse.status(), 200);
        const packet = explanations.get('/api/read/static-explanation');
        assert(packet && typeof packet === 'object' && 'data' in packet);
        const beforeRun = packet.data as StaticExplanationReadModel;
        assert.deepEqual(beforeRun.context.map(item => item.origin).filter(origin => origin.kind === 'source').map(origin =>
          [origin.source_view.connector, origin.source_view.resource]), [
          ['salesforce', 'Opportunity'], ['drive', 'files'], ['drive', 'contents']]);
        const staticSteps = page.getByRole('region', {name: 'Original story', exact: true});
        await staticSteps.waitFor();
        assert.equal(await page.locator('.query-scope-note').count(), 0);
        assert.equal(await staticSteps.locator('details.story-card').count(), 8);
        const originalIds = staticSteps.locator('.occurrence-origin details > code');
        assert.deepEqual((await originalIds.allTextContents()).sort(),
          beforeRun.story.occurrences.map(step => step.stepId).sort());
        const originalPorts = staticSteps.locator('.occurrence-origin details > code + ul > li > code');
        assert.deepEqual((await originalPorts.allTextContents()).sort(), beforeRun.story.occurrences
          .flatMap(step => step.ports.map(port => port.port_id)).sort());
        assert.equal(await staticSteps.locator('details.story-card[open]').count(), 1);
        assert.match(await staticSteps.innerText(), /Planned/u);
        const heading = page.getByRole('heading', {level: 1});
        const checkedJoins = beforeRun.story.occurrences.filter(step => step.explanation.meaning.kind === 'join');
        assert(checkedJoins.some(({explanation: {meaning}}) =>
          meaning.kind === 'join' && meaning.keys.some(key => key.left === 'name' && key.right === 'name')));
        assert.deepEqual(beforeRun.story.narrative.clauses.find(clause => clause.kind === 'join')?.step_ids,
          checkedJoins.map(step => step.stepId));
        const readOpportunity = staticSteps.locator('details.story-card').filter({
          has: page.locator('summary > strong').filter({hasText: /Read Opportunity|Opportunity を読む/u}),
        });
        const opportunity = beforeRun.context.find(({origin}) =>
          origin.kind === 'source' && origin.source_view.resource === 'Opportunity')?.origin;
        assert(opportunity?.kind === 'source');
        const links = beforeRun.plan.stageResultLinks;
        assert(links);
        assert.equal(links.length, 2);
        const originalLink = links.find(link =>
          opportunity.consuming_ports.some(port => port.step_id === link.producer.step_id));
        assert(originalLink);
        for (const proof of ['Opportunity', 'files', 'contents', 'deal-review.v1', 'updates', 'review.value.changed']) {
          assert((await heading.innerText()).includes(proof), proof);
        }
        assert.doesNotMatch(await heading.innerText(), /connector:\/\/|\baql_/u);
        if ((await heading.innerText()).includes('review.outcome')) {
          assert.match(await heading.innerText(), /\[redacted string\]/u);
        }
        const filter = staticSteps.locator('details.story-card').filter({hasText: /review\.outcome/u});
        await filter.locator('summary').first().click();
        assert.match(await filter.locator('.occurrence-origin').filter({hasText: /review\.outcome/u}).innerText(), /review\.value\.changed/u);
        assert.match(await filter.locator('.occurrence-origin').filter({hasText: /review\.outcome/u}).innerText(), /\[redacted string\]/u);
        await filter.locator('summary').first().click();
        const write = staticSteps.locator('details.story-card').filter({has: page.locator('summary')
          .filter({hasText: /(?:Update .* on|Write to) Opportunity/u})});
        await write.locator('summary').first().click();
        await write.getByText('Original Effect declarations', {exact: true}).click();
        assert.match(await write.innerText(), /Fields: StageName, NextStep|Fields: NextStep, StageName/u);
        await write.locator('summary').first().click();
        const expectedColumns = readOpportunity.getByRole('table', {name: 'Expected columns'});
        assert.deepEqual(await expectedColumns.getByRole('columnheader').allTextContents(),
          ['NextStep', 'StageName', 'id', 'name']);
        const origin = readOpportunity.locator('.occurrence-origin details');
        await origin.getByText('Original step and ports', {exact: true}).click();
        assert((await origin.innerText()).includes(originalLink.producer.step_id));
        await origin.getByText('Original step and ports', {exact: true}).click();
        await page.evaluate(() => window.scrollTo(0, 0));
        await page.screenshot({path: join(evidence, 'installed-deal-review-before-run.png')});
        const queryClosed = [await captureClosedSteps('en', 1440, 'installed-deal-review-before-en-1440.png')];
        const graph = page.locator('section.actql-explorer[data-workspace="true"]');
        const readGraph = async (narrow: boolean, japanese = false) => {
          await readOpportunity.locator('summary').first().click();
          await page.getByRole('button', {name: japanese ? /グラフ/u : /Graph/u}).click();
          assert.equal(await graph.getByRole('navigation', {name: 'Plan presentation'}).count(), 0);
          await graph.locator('.react-flow__node').first().waitFor({state: 'attached'});
          const nodes = graph.locator('.react-flow__node');
          assert.equal(await nodes.count(), 8);
          await graph.getByText(japanese ? 'データの流れを表示します。実行順序は示しません。'
            : 'Data flow, not execution order', {exact: true}).waitFor();
          assert((await nodes.locator('.actql-explorer-node > p').allTextContents())
            .includes(japanese ? '予定' : 'Planned'));
          if (japanese) assert.doesNotMatch(await graph.innerText(), /\b(?:Planned|operation|Declared inputs|Result projection|input [0-9]+)\b/u);
          assert.equal(await graph.locator('.actql-explorer-flow-metadata').count(), 0);
          const declaredWrite = nodes.filter({has: page.locator('[data-effect-declaration="true"]')});
          assert.equal(await declaredWrite.count(), 1);
          assert.equal(await declaredWrite.locator('.react-flow__handle').count(), 0);
          assert.match(await declaredWrite.innerText(), /Opportunity/u);
          const fields = declaredWrite.locator('.actql-explorer-declared-fields');
          assert.match(await fields.innerText(), /StageName/u);
          assert.match(await fields.innerText(), /NextStep/u);
          assert(await fields.evaluate(node => node.scrollHeight <= node.clientHeight && node.scrollWidth <= node.clientWidth));
          assert(await declaredWrite.evaluate(node => {
            const y = node.getBoundingClientRect().top;
            return [...node.parentElement!.children].every(other => other === node || other.getBoundingClientRect().bottom < y);
          }));
          assert.match(await declaredWrite.innerText(), japanese ? /入力元のリンクは未投影/u : /Producer link not projected/u);
          for (const link of links) {
            const path = graph.getByTestId('rf__edge-' + link.consumer.port_id).locator('.react-flow__edge-path');
            await path.waitFor({state: 'attached'});
            assert(await path.evaluate(line => line instanceof SVGPathElement && line.getTotalLength() > 0));
          }
          const selected = graph.locator('.react-flow__node.selected[data-id="' + originalLink.producer.step_id + '"]');
          await selected.waitFor({state: 'attached'});
          await page.evaluate(() => window.scrollTo(0, 0));
          if (narrow) {
            await page.waitForFunction(({stepId, targetPort}) => {
              const node = document.querySelector('.react-flow__node[data-id="' + stepId + '"]');
              const path = document.querySelector('.react-flow__edge[data-id="' + targetPort + '"] .react-flow__edge-path');
              if (!node || !path) return false;
              const card = node.getBoundingClientRect(), edge = path.getBoundingClientRect();
              return card.x >= 0 && card.right <= innerWidth && card.y >= 0 && card.bottom <= innerHeight &&
                edge.x < innerWidth && edge.right >= 0 && edge.y >= 0 && edge.y + 14 < innerHeight;
            }, {stepId: originalLink.producer.step_id, targetPort: originalLink.consumer.port_id});
          }
          const selectedCard = page.getByRole('region', {name: japanese ? '選択した工程' : 'Selected Step', exact: true});
          assert.match(await selectedCard.innerText(), /Opportunity/u);
          const advanced = selectedCard.locator('details.original-plan-advanced');
          assert.equal(await advanced.count(), 1);
          await advanced.locator('summary').click();
          assert.match(await advanced.innerText(), new RegExp(beforeRun.plan.compiledPlanCid, 'u'));
          assert.match(await advanced.innerText(), new RegExp(beforeRun.plan.logicalMapCid, 'u'));
          assert.doesNotMatch(await advanced.innerText(), /Controls, Samples and physical observations are unavailable/u);
          await advanced.locator('summary').click();
        };
        await readGraph(false);
        await page.screenshot({path: join(evidence, 'installed-deal-review-graph.png')});
        await page.getByRole('button', {name: 'Steps', exact: true}).click();
        queryClosed.push(await captureClosedSteps('en', 390, 'installed-deal-review-narrow.png'));
        const headingBounds = await heading.boundingBox();
        assert(headingBounds && headingBounds.height < 192);
        await readGraph(true);
        await page.screenshot({path: join(evidence, 'installed-deal-review-graph-en-390.png')});
        await page.getByRole('button', {name: 'Steps', exact: true}).click();
        await page.getByRole('button', {name: /Show query/}).click();
        await page.getByLabel('Query options').click();
        await page.locator('.query-options label').filter({hasText: /^Language/u}).locator('select').selectOption('ja');
        await page.getByLabel('クエリオプション').click();
        await page.getByRole('button', {name: '説明', exact: true}).click();
        await heading.filter({hasText: /review\.value\.changed などの条件で絞り込む/u}).waitFor();
        await page.getByText('実行前 · 確認済みプラン', {exact: true}).waitFor();
        const japaneseStory = page.getByRole('region', {name: '元のストーリー', exact: true});
        const japaneseOrigin = japaneseStory.locator('details.story-card[open] .occurrence-origin summary').first();
        assert((await japaneseOrigin.textContent())?.startsWith('元の工程とポート'));
        await page.getByRole('button', {name: 'Run を開く', exact: true}).waitFor();
        const kinds = await japaneseStory.locator('.step-label').allTextContents();
        assert(kinds.some(label => label.includes('書き込み')));
        assert(kinds.some(label => label.includes('モデル')));
        assert(kinds.every(label => !/\b(?:Read|Combine|Compute|Ask model|Result|Write)\b/u.test(label)));
        const states = await japaneseStory.locator('.step-state[data-state="Planned"]').allTextContents();
        assert(states.length > 0 && states.every(state => state === '予定'));
        queryClosed.push(await captureClosedSteps('ja', 1440, 'installed-deal-review-before-ja-1440.png'));
        await readGraph(false, true);
        await page.screenshot({path: join(evidence, 'installed-deal-review-graph-ja.png')});
        await page.getByRole('button', {name: '工程', exact: true}).click();
        queryClosed.push(await captureClosedSteps('ja', 390, 'installed-deal-review-narrow-ja.png'));
        await readGraph(true, true);
        await page.screenshot({path: join(evidence, 'installed-deal-review-graph-ja-390.png')});
        assert.deepEqual(requests, ['/api/session', '/api/read/launch', '/api/read/static-explanation',
          '/api/read/static-explanation']);
        receipt = {browserRequests: requests, checkedSources: 3, checkedJoinSteps: checkedJoins.length,
          originalLogicalSteps: beforeRun.plan.nodes.length, groupedGraphNodes: 8, originalStageResultLinks: links, queryClosed};
      } else {
        await page.getByLabel('Query options').click();
        await page.getByLabel('Open query file').setInputFiles(join(project, programFile));
        await page.getByLabel('Query options').click();
        assert.equal(original.saved.explanation.state, 'projected');
        const {plan, facts, context} = original.saved.explanation.view;
        const openOriginal = async (verifyOriginalBody: boolean, locale: Capture['locale'] = 'en') => {
          await page.getByRole('button', {name: 'Open Run', exact: true}).click();
          await page.locator('textarea[name="ref"]').fill(JSON.stringify(original.ref));
          if (locale === 'ja') {
            await page.getByText('Other original reads', {exact: true}).click();
            await page.locator('.run-options select').selectOption(locale);
          }
          const reply = page.waitForResponse(response =>
            response.url() === connected.origin + '/api/read/run-explanation-context');
          const status = page.waitForResponse(response => response.url() === connected.origin + '/api/read/run');
          await page.getByRole('button', {name: locale === 'ja' ? '保存済みの説明を開く' : 'Open Saved explanation', exact: true}).click();
          const response = await reply;
          await status;
          assert.equal(response.status(), 200);
          if (verifyOriginalBody) {
            const packet = explanations.get('/api/read/run-explanation-context');
            assert(packet && typeof packet === 'object' && 'data' in packet);
            const data = packet.data as SavedExplanationReadModel;
            assert(data.plan && data.explanation.state === 'projected');
            assert.deepEqual(data.runRef, original.ref);
            assert.equal(data.plan.compiledPlanCid, plan.compiled_plan_cid);
            assert.equal(data.plan.logicalMapCid, plan.logical_map.self_cid);
            assert.equal(data.explanation.story.factsCid, facts.self_cid);
            assert.equal(data.explanation.story.locale, locale);
            assert.deepEqual(data.explanation.context.map(item => item.origin), context.items);
          }
          await page.getByRole('dialog', {name: locale === 'ja' ? 'Run を開く' : 'Open Run'}).waitFor({state: 'hidden'});
          const heading = page.locator('.story-heading .eyebrow');
          assert((await heading.textContent())?.includes(original.ref.runDefinitionCid.slice(7, 19)));
        };
        await openOriginal(true);
        const story = page.getByRole('region', {name: 'Original story', exact: true});
        await story.waitFor();
        const task = dealReview ? /model-task:deal-review\.v1/u : /model-task:churn-risk\.v1/u;
        assert.match((await story.textContent()) ?? '', task);
        await page.getByText('Original query not retained in this read', {exact: true}).waitFor();
        assert.equal(await page.getByRole('list', {name: 'Query text'}).count(), 0);
        await page.getByText('Current status unavailable', {exact: true}).waitFor();
        assert.deepEqual(requests, ['/api/session', '/api/read/launch', '/api/read/run-explanation-context', '/api/read/run']);
        await page.screenshot({path: join(evidence, 'installed-saved-context.png')});
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
        assert(firstBounds && firstBounds.width >= 230 && firstBounds.x >= 0 && firstBounds.x + firstBounds.width <= 1440);
        await page.screenshot({path: join(evidence, 'installed-saved-graph.png')});
        await graph.getByRole('button', {name: /fit view/iu}).click();
        const nextNode = graph.locator('.react-flow__node[data-id^="sha256:"]:not(:has([data-selected="true"]))').first();
        const originalStep = await nextNode.getAttribute('data-id');
        assert(originalStep && originalStep !== defaultStep);
        const node = graph.locator(`.react-flow__node[data-id="${originalStep}"]`);
        await node.click();
        await node.locator('[data-selected="true"]').waitFor();
        const step = page.getByRole('region', {name: 'Selected Step', exact: true});
        await step.waitFor();
        assert((await step.textContent())?.includes(originalStep));
        await page.getByRole('button', {name: 'Steps', exact: true}).click();
        assert((await story.locator('details.story-card[data-selected="true"]').textContent())?.includes(originalStep));
        await page.getByRole('button', {name: 'Open Run', exact: true}).click();
        await page.locator('textarea[name="ref"]').fill('{');
        await page.getByRole('button', {name: 'Open Saved explanation', exact: true}).click();
        await page.getByRole('alert').filter({hasText: 'Enter the complete original Run reference as JSON.'}).waitFor();
        await page.getByRole('button', {name: 'Close dialog', exact: true}).click();
        await story.waitFor();
        assert.equal(requests.length, 4);
        connected.invalidateScope();
        await page.getByRole('button', {name: 'Inspect status', exact: true}).click();
        await page.getByRole('button', {name: 'Reconnect', exact: true}).waitFor();
        await story.waitFor({state: 'hidden'});
        assert.equal(await page.locator('input[name="bootstrap"], textarea[name="ref"]').count(), 0);
        await page.screenshot({path: join(evidence, 'installed-reconnect.png')});
        await connect('Reconnect');
        await openOriginal(false);
        await story.waitFor();
        assert.match((await story.textContent()) ?? '', task);
        await page.getByText('Original query not retained in this read', {exact: true}).waitFor();
        assert.equal(await page.getByRole('list', {name: 'Query text'}).count(), 0);
        await page.setViewportSize({width: 390, height: 844});
        await page.getByRole('button', {name: /Hide query/}).click();
        assert.equal(await page.locator('#query-pane').count(), 0);
        await page.getByRole('button', {name: /Show query/}).click();
        assert(await page.evaluate(() => document.documentElement.scrollWidth === window.innerWidth));
        await page.screenshot({path: join(evidence, 'installed-narrow.png')});
        assert.deepEqual(requests, ['/api/session', '/api/read/launch', '/api/read/run-explanation-context', '/api/read/run',
          '/api/read/observation', '/api/session', '/api/read/launch', '/api/read/run-explanation-context', '/api/read/run']);
        let queryClosed: Capture[] | undefined;
        if (dealReview) {
          const heading = page.getByRole('heading', {level: 1});
          assert.match(await heading.innerText(), /^Read .*Opportunity.*files.*contents/u);
          assert.equal(await story.locator('details.story-card').count(), 8);
          queryClosed = [
            await captureClosedSteps('en', 1440, 'installed-deal-review-saved-en-1440.png'),
            await captureClosedSteps('en', 390, 'installed-deal-review-saved-en-390.png'),
          ];
          const beforeLocaleChange = requests.length;
          await openOriginal(true, 'ja');
          assert.deepEqual(requests.slice(beforeLocaleChange), ['/api/read/run-explanation-context', '/api/read/run']);
          await heading.filter({hasText: /Opportunity.*files.*contents.*を読む/u}).waitFor();
          const japaneseStory = page.getByRole('region', {name: '元のストーリー', exact: true});
          assert.equal(await japaneseStory.locator('details.story-card').count(), 8);
          await page.getByRole('button', {name: '状態を確認', exact: true}).waitFor();
          await page.getByText('ターミナル', {exact: true}).waitFor();
          const review = page.locator('.workspace-tools').filter({has: page.locator('.actql-checkpoint-review')});
          if (await review.count()) {
            assert.equal(await review.locator('summary').textContent(), 'チェックポイントのレビュー');
            await review.locator('summary').click();
            await review.getByRole('heading', {name: 'チェックポイントのレビュー', exact: true}).waitFor();
            await review.locator('summary').click();
          }
          queryClosed.push(
            await captureClosedSteps('ja', 1440, 'installed-deal-review-saved-ja-1440.png'),
            await captureClosedSteps('ja', 390, 'installed-deal-review-saved-ja-390.png'),
          );
        }
        receipt = {producerPid: original.producerPid, consumerPid: process.pid, sameOriginal: true,
          browserRequests: requests, queryClosed};
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
assert(receipt);
const afterClose = requireLosslessDrain(observation.status(), true);
assert.equal(await targetDigest(), expectedTarget, 'The original target must stay unchanged through close');
let workReceipt: {attempts: Marker[]} | {newBusinessAttempts: number};
if (phase === 'produce') {
  assert('ref' in receipt);
  const {runDefinitionCid} = receipt.ref;
  const sourceAttempts = markers.filter(item => item.operation === 'source').length;
  if (dealReview) assert(sourceAttempts > 0, 'Original deal-review must witness Source work');
  else assert.equal(sourceAttempts, 2);
  assert(markers.every(item => item.run === runDefinitionCid));
  assert(markers.some(item => item.operation === 'infer'), 'Original Run must witness an Infer start');
  assert(markers.some(item => item.operation === 'effect'), 'Original Run must witness an Effect application');
  assert(markers.every(item => item.operation !== 'effect' ||
    item.event === 'application_observed' && item.outcome === 'waiting_checkpoint'));
  workReceipt = {attempts: markers};
} else {
  assert.deepEqual(markers, [], 'Saved read must start no Source or Infer and observe no Effect application or write');
  workReceipt = {newBusinessAttempts: markers.length};
}
await writeFile(phase === 'produce' ? originalPath : join(evidence, phase === 'before' ? 'before-run-receipt.json' : 'saved-context-receipt.json'),
  JSON.stringify({...receipt, ...workReceipt, targetUnchanged: true, firstClose: true,
    observation: {beforeClose, afterClose}}) + '\n', {flag: 'wx'});
