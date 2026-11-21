import assert from 'node:assert/strict';
import test from 'node:test';
import {canonicalJson} from '../../sdk/host-port.mjs';
import {staticExplanationReadModel} from '../../explorer-ui/read-model.mjs';
import {createExplorerBrowserSource} from '../browser-source.mjs';
import {harness, origin, ref} from '../gateway-test.fixture.mjs';
import {effectfulStaticExplanationFixture} from '../../../scripts/fixtures/effectful-static-plan-vectors.mjs';

// Present canonical authored DATA through the actual compiled Common renderer.
// The Gateway fixture uses the public SDK shape without a business Host.
test('Static Context renders deterministic EN and JA from one unchanged Plan', async () => {
  const {renderStaticExplanationNarrative} = await import('@actql/run-host-core/explanation-narrative');
  const original = effectfulStaticExplanationFixture();
  const wire = canonicalJson(original, {dataKeys: true});
  const render = (view, locale) => {
    assert.equal(view, original);
    return renderStaticExplanationNarrative(wire, locale);
  };
  const en = staticExplanationReadModel(original, {render});
  const ja = staticExplanationReadModel(original, {render, locale: 'ja'});
  assert.equal(JSON.stringify(staticExplanationReadModel(original, {render})), JSON.stringify(en));
  assert.deepEqual(en.story.occurrences.map(occurrence => occurrence.explanation.text),
    renderStaticExplanationNarrative(wire, 'en').steps);
  assert.deepEqual(ja.context.map(item => item.text), renderStaticExplanationNarrative(wire, 'ja').context);
  assert.deepEqual(ja.plan, en.plan);
  assert.deepEqual(en.context.map(item => item.origin), original.context.items);
  assert.deepEqual(ja.context.map(item => item.origin), original.context.items);
  assert.equal(en.context[0].text, 'Read "crm"."accounts" through view "accounts"');
  assert.equal(en.context[1].text, 'Apply model task "model-task:review" to each input row');
  assert.equal(ja.context[1].text, 'モデルタスク "model-task:review" を各入力行に適用');
  assert.equal(en.context[2].text, 'Declare Result "updates"');
  assert.equal(en.context[3].text, 'Declared write update "connector://crm/account" on fields "tag" · Contract minimum approval: required · Current decision unknown');
  assert.match(ja.context[3].text, /更新.*対象フィールド "tag".*現在の判断は不明/u);
  assert.equal(en.plan.effectful.observations.approval.state, 'unknown');
  assert.deepEqual(en.story.capabilities.sample_capture, []);
  assert(Object.isFrozen(en.context[0].origin));
  assert.throws(() => renderStaticExplanationNarrative(wire, 'fr'), {code: 'InvalidStaticExplanationNarrative'});
  assert.throws(() => renderStaticExplanationNarrative(' '.repeat(65537), 'en'),
    {code: 'StaticExplanationNarrativeLimit'});
  assert.throws(() => renderStaticExplanationNarrative('{}', 'en'), {code: 'InvalidStaticExplanationNarrative'});
});

test('Explorer static explanation uses one SDK read through the original authenticated Gateway', async () => {
  const original = effectfulStaticExplanationFixture(), calls = [];
  const h = harness({client: {explain(input, options) {
    calls.push({input, options}); return structuredClone(original);
  }, plan() {assert.fail('no separate Plan compilation');}, attach() {assert.fail('no Run');}}});
  const input = {stages: []}, options = {maxNodes: 2000};
  assert.equal((await h.send('/api/read/static-explanation', {input, options})).status, 401);
  let cookie;
  const browser = createExplorerBrowserSource({origin, fetch: async (url, init) => {
    const response = await h.gateway.fetch(new Request(url, {...init,
      headers: {...init.headers, Host: '127.0.0.1:43210', Origin: origin, ...(cookie ? {Cookie: cookie} : {})}}));
    const setCookie = response.headers.get('set-cookie');
    if (setCookie !== null) cookie = setCookie.split(';')[0];
    return response;
  }});
  const capabilities = await browser.connect(h.gateway.issueBootstrap().bootstrap);
  assert.equal(capabilities.sample, false); assert.equal(capabilities.control, false);
  const model = await browser.staticExplanation(input, options, 'ja');
  assert.equal(model.plan.logicalMapCid, original.context.binding.logical_map_cid);
  assert.equal(model.story.locale, 'ja');
  assert.equal(model.context[1].text, 'モデルタスク "model-task:review" を各入力行に適用');
  assert.deepEqual(calls, [{input, options: {maxWireBytes: 65536, maxNodes: 2000, maxDepth: 64}}]);
  const session = await h.connect();
  for (const body of [{input, locale: 'fr'}, {input, options: {start: true}}, {input, ref}]) {
    assert.equal((await h.read('static-explanation', body, session)).status, 400);
  }
  assert.equal(calls.length, 1);
  await h.gateway.close();
});

test('Explorer static explanation discards a late read after the original Gateway session changes', async () => {
  const entered = Promise.withResolvers(), pending = Promise.withResolvers();
  const h = harness({client: {explain() {entered.resolve(); return pending.promise;},
    attach() {assert.fail('no replacement Run');}}});
  const original = await h.connect();
  const read = h.read('static-explanation', {input: 'SELECT 1'}, original);
  await Promise.race([entered.promise, read.then(() => assert.fail('read did not start'))]);
  await h.connect();
  pending.resolve(effectfulStaticExplanationFixture());
  const response = await read;
  assert.notEqual(response.status, 200);
  assert.doesNotMatch(await response.text(), /model-task:review/);
  await h.gateway.close();
});
