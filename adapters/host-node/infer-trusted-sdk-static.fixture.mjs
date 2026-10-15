import assert from 'node:assert/strict';
import * as runtime from './infer-trusted-runtime-view.mjs';
import {installModelProviders} from './installed-model.mjs';
import {openAIChatStaticOriginals as sdk} from
  '../../packages/provider-ai-sdk/_internal/openai-chat.mjs';

// Actual pinned ESM namespaces and factory, actual selected Node startup;
// nominal Host/Scope and Core registration doubles. No SDK call or byte grant.
const actual = {host: {}, supplier() {}, installation: {}, generation: {},
  runtime: process, moduleLifetime: import.meta, transport() {}, target: 'selected-node'};
const view = runtime.issueInferTrustedRuntimeView(actual);
const mode = process.argv[2];
const bind = (v = view, a = actual, original = sdk) =>
  runtime.bindInferTrustedSdkStaticModules(v, a, original);
const check = (v = view, a = actual, original = sdk) =>
  runtime.checkInferTrustedSdkStaticModules(v, a, original);
const rejects = (run, code) => assert.throws(run, {code});
if (mode === 'late') {
  assert.equal(runtime.associateInferTrustedStartupView(view, actual), undefined);
  rejects(() => bind(), 'InferTrustedStartupUnavailable');
} else {
  runtime.associateInferTrustedStartupView(view, actual);
  if (mode === 'current') {
    rejects(() => check(), 'InferTrustedSdkStaticUnavailable');
    bind();
    check();
    const scoped = {...actual, installation: {}, transport() {}};
    const borrowed = runtime.issueInferTrustedRuntimeView(scoped);
    runtime.borrowInferTrustedStartupView(view, borrowed, actual, scoped);
    check(borrowed, scoped);
    rejects(() => bind(borrowed, scoped), 'InferTrustedSdkStaticUnavailable');
    rejects(() => check(borrowed, {...scoped, installation: {}}),
      'InferTrustedRuntimeOriginalChanged');
    // Another Host borrows the SAME actual ESM graph, not another M-sized copy.
    const next = {...actual, host: {}, generation: {}, installation: {}};
    const nextView = runtime.issueInferTrustedRuntimeView(next);
    runtime.associateInferTrustedStartupView(nextView, next);
    bind(nextView, next);
    runtime.forgetInferTrustedStartupView(view, actual.host, actual.generation);
    runtime.forgetInferTrustedRuntimeView(view, actual.host, actual.generation);
    rejects(() => check(borrowed, scoped), 'InferTrustedStartupUnavailable');
    // Host retirement neither retires ESM storage nor substitutes a new graph.
    check(nextView, next);
    runtime.forgetInferTrustedStartupView(borrowed, actual.host, actual.generation);
    runtime.forgetInferTrustedRuntimeView(borrowed, actual.host, actual.generation);
    runtime.forgetInferTrustedStartupView(nextView, next.host, next.generation);
    runtime.forgetInferTrustedRuntimeView(nextView, next.host, next.generation);
  } else if (mode === 'foreign') {
    let getterCalls = 0;
    const getter = Object.freeze({openai: sdk.openai, providerUtils: sdk.providerUtils,
      get createOpenAI() { getterCalls++; return sdk.createOpenAI; }});
    for (const candidate of [getter, Object.freeze({...sdk, createOpenAI() {}}),
      Object.freeze({...sdk, openai: Object.freeze({...sdk.openai})})]) {
      rejects(() => bind(view, actual, candidate), 'InferTrustedSdkStaticUnavailable');
    }
    assert.equal(getterCalls, 0);
    bind();
    // Two genuine module namespaces/functions are not the same allocation.
    rejects(() => check(view, actual, Object.freeze({openai: sdk.providerUtils,
      providerUtils: sdk.openai, createOpenAI: sdk.createOpenAI})),
    'InferTrustedSdkStaticUnavailable');
    rejects(() => check({...view}), 'InferTrustedRuntimeViewUnavailable');
    check();
  } else if (mode === 'registration') {
    let constructorCalls = 0;
    const moon = {clientProgramInstallModelProvider() { constructorCalls++; return {}; }};
    const entry = {providerId: 'fixture', invoke() { throw new Error('UnexpectedProvider'); },
      validatePrompt() { return true; }, sdkStaticOriginals: sdk};
    const assertCurrent = () => runtime.requireInferTrustedStartupView(view, actual);
    const installed = installModelProviders(moon, () => [entry], assertCurrent,
      assertCurrent, original => bind(view, actual, original)).get('fixture');
    assert.equal(constructorCalls, 1);
    installed.assertTrustedRuntime();
    entry.sdkStaticOriginals = undefined;
    // The one-read installed snapshot, not a mutable entry, supplies rechecks.
    installed.assertTrustedRuntime();
    runtime.forgetInferTrustedStartupView(view, actual.host, actual.generation);
    rejects(() => installed.assertTrustedRuntime(), 'InferTrustedStartupUnavailable');
    constructorCalls = 0;
    rejects(() => installModelProviders(moon, () => [{...entry, sdkStaticOriginals: sdk}]),
      'InferTrustedSdkStaticUnavailable');
    assert.equal(constructorCalls, 0);
  } else throw new Error('Explicit static SDK fixture mode required');
}
console.log(JSON.stringify({mode, checked: true, providerCalls: 0, physicalAcks: 0,
  actualCore: false, normalNumericProfile: null, publicE2E: 0}));
