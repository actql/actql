import test from 'node:test';
import assert from 'node:assert/strict';
import {createOpenAIChatProvider} from './_internal/normal-openai-chat.mjs';

const options = () => ({providerId: 'fixture', modelId: 'fixture', apiKeyFile: 'unread',
  observeEgress() {}, generation: {temperature: 0, topP: 1, maxOutputTokens: 4},
  budget: {maxCalls: 1n, maxRows: 1, maxTokens: 4n, maxCostUnits: 1n, maxDurationMs: 2000n}});
const settings = {connectMs: 1000, headersMs: 1000, bodyMs: 1000, callMs: 100};
const stop = Error('StopBeforeRuntimeIdentityAndIO');
// Explicit context/quote doubles isolate configuration selection. The actual
// initial Resource, Common tariff and normal distribution have separate checks.
function context(captured) {
  const forbidden = () => assert.fail('No semantic/reader/Task operation expected');
  return {async prepareConfiguration(project) {const value = project(); captured.push(value); return value;},
    runtimeIdentity() {throw stop;}, artifactIdentity: forbidden, readText: forbidden,
    prepareBindingOriginals: forbidden, prepareTasks: forbidden, prepareRawPolicies: forbidden};
}

test('normal deadline adds only the actual Common R/E quote and preserves unselected profile', async () => {
  for (const enabled of [false, true]) {
    let quotes = 0;
    const captured = [], config = options();
    if (enabled) config.transportTimeouts = settings;
    const moon = {clientProgramInstalledNodeModelDeadlineCapacity() {quotes++; return [456n, 456n];}};
    await assert.rejects(createOpenAIChatProvider(config)(moon, context(captured)), error => error === stop);
    assert.equal(quotes, enabled ? 1 : 0);
    if (enabled) {
      assert.equal(captured[0].physicalLimits.adapter_holding_bytes, 8388608 + 456);
      assert.equal(captured[0].physicalLimits.adapter_workspace_bytes, 16777216 + 456);
      assert.equal(captured[0].budget.maxDurationMs, 2000n);
    } else assert.equal(Object.hasOwn(captured[0], 'physicalLimits'), false);
  }
});

test('normal deadline missing invalid overflow or over-budget quote refuses before IO', async () => {
  for (const quote of [undefined, [], [1n, 0n], [2147483647n, 2147483647n], [1, 1]]) {
    const moon = quote === undefined ? {} : {clientProgramInstalledNodeModelDeadlineCapacity() {return quote;}};
    const captured = [];
    await assert.rejects(createOpenAIChatProvider({...options(), transportTimeouts: settings})(moon, context(captured)),
      {code: 'OpenAIProviderDeadlineCapacityUnavailable'});
    assert.equal(captured.length, 0);
  }
  await assert.rejects(createOpenAIChatProvider({...options(), transportTimeouts: {...settings, callMs: 2001}})({}, context([])),
    {code: 'OpenAIProviderTimeoutBudgetExceeded'});
});
