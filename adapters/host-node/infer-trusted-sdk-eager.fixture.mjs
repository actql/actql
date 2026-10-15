import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import * as runtime from './infer-trusted-runtime-view.mjs';
import {openAIChatStaticOriginals as sdk} from
  '../../packages/provider-ai-sdk/_internal/openai-chat.mjs';

// Real selected Node/preload/SDK namespaces, nominal Host/Scope doubles only.
// No request, Core resource admission, byte quote or cleanup ACK is issued.
const actual = {host: {}, supplier() {}, installation: {}, generation: {},
  runtime: process, moduleLifetime: import.meta, transport() {}, target: 'selected-node'};
const view = runtime.issueInferTrustedRuntimeView(actual);
const mode = process.argv[2];
const bind = (v = view, a = actual, modules = sdk) =>
  runtime.bindInferTrustedSdkStaticModules(v, a, modules);
const check = (v = view, a = actual, modules = sdk) =>
  runtime.checkInferTrustedSdkEagerModules(v, a, modules);
const rejects = (run, code) => assert.throws(run, {code});

if (mode === 'eager-absent' || mode === 'eager-late-flags') {
  if (mode === 'eager-late-flags') {
    // A fabricated current flag list cannot recreate the actual preload phase.
    process.execArgv.splice(0, process.execArgv.length, '--no-lazy', '--require',
      new URL('./infer-trusted-node-preload.cjs', import.meta.url).pathname);
  }
  assert.equal(runtime.associateInferTrustedStartupView(view, actual), undefined);
  rejects(() => check(), 'InferTrustedStartupUnavailable');
} else {
  assert.equal(runtime.associateInferTrustedStartupView(view, actual), view);
  if (mode === 'eager-unselected-sdk') {
    const require = createRequire(import.meta.url);
    assert.throws(() => require.resolve('@actql/provider-ai-sdk'), {code: 'MODULE_NOT_FOUND'});
    rejects(() => bind(), 'InferTrustedSdkStaticUnavailable');
    rejects(() => check(), 'InferTrustedSdkStaticUnavailable');
  } else if (mode === 'eager-old-recipe') {
    bind();
    runtime.checkInferTrustedSdkStaticModules(view, actual, sdk);
    rejects(() => check(), 'InferTrustedSdkEagerUnavailable');
    process.execArgv.unshift('--no-lazy');
    // The old selection stays old even after a matching-looking later list.
    runtime.checkInferTrustedSdkStaticModules(view, actual, sdk);
    rejects(() => check(), 'InferTrustedSdkEagerUnavailable');
  } else if (mode === 'eager-current') {
    rejects(() => check(), 'InferTrustedSdkStaticUnavailable');
    bind();
    check();
    for (const field of ['host', 'supplier', 'installation', 'generation',
      'runtime', 'moduleLifetime', 'transport', 'target']) {
      rejects(() => check(view, {...actual, [field]: field === 'target' ? 'foreign' : {}}),
        'InferTrustedRuntimeOriginalChanged');
    }
    rejects(() => check({...view}), 'InferTrustedRuntimeViewUnavailable');
    const require = createRequire(new URL('../../packages/provider-ai-sdk/package.json', import.meta.url));
    const independentUrl = pathToFileURL(require.resolve('@ai-sdk/openai'));
    independentUrl.search = '?independent-eager-instance';
    const independent = await import(independentUrl.href);
    assert.notEqual(independent, sdk.openai);
    rejects(() => check(view, actual, Object.freeze({...sdk, openai: independent,
      createOpenAI: independent.createOpenAI})), 'InferTrustedSdkStaticChanged');
    const scoped = {...actual, installation: {}, transport() {}};
    const borrow = runtime.issueInferTrustedRuntimeView(scoped);
    runtime.borrowInferTrustedStartupView(view, borrow, actual, scoped);
    check(borrow, scoped);
    rejects(() => bind(borrow, scoped), 'InferTrustedSdkStaticUnavailable');
    const next = {...actual, host: {}, installation: {}, generation: {}};
    const nextView = runtime.issueInferTrustedRuntimeView(next);
    runtime.associateInferTrustedStartupView(nextView, next);
    bind(nextView, next);
    runtime.forgetInferTrustedStartupView(view, actual.host, actual.generation);
    runtime.forgetInferTrustedRuntimeView(view, actual.host, actual.generation);
    rejects(() => check(borrow, scoped), 'InferTrustedStartupUnavailable');
    // Closing an association does not retire actual process/module storage.
    check(nextView, next);
    runtime.forgetInferTrustedStartupView(borrow, actual.host, actual.generation);
    runtime.forgetInferTrustedRuntimeView(borrow, actual.host, actual.generation);
    runtime.forgetInferTrustedStartupView(nextView, next.host, next.generation);
    runtime.forgetInferTrustedRuntimeView(nextView, next.host, next.generation);
    rejects(() => check(nextView, next), 'InferTrustedRuntimeViewRetired');
  } else throw new Error('Explicit eager SDK fixture mode required');
}
console.log(JSON.stringify({mode, checked: true, providerCalls: 0, physicalAcks: 0,
  actualCore: false, normalNumericProfile: null, publicE2E: 0}));
