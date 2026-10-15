import assert from 'node:assert/strict';
import * as runtime from './infer-trusted-runtime-view.mjs';
import {installModelProviders} from './installed-model.mjs';
import {openAIChatStaticOriginals as sdk} from
  '../../packages/provider-ai-sdk/_internal/openai-chat.mjs';

// Real early Node/SDK modules. Host, registration/Core constructor and Scope
// are explicit nominal doubles, not the installed Host or original Ledger.
const mode = process.argv[2];
assert.ok(['eager', 'static-only'].includes(mode));
const actual = {host: {}, supplier() {}, installation: {}, generation: {},
  runtime: process, moduleLifetime: import.meta, transport() {}, target: 'selected'};
const view = runtime.issueInferTrustedRuntimeView(actual);
assert.equal(runtime.associateInferTrustedStartupView(view, actual), view);
let currentCalls = 0, eagerCalls = 0, constructors = 0, bindingCalls = 0;
const current = () => {
  currentCalls++;
  runtime.requireInferTrustedStartupView(view, actual);
};
const requireOriginalEager = () => {
  eagerCalls++;
  runtime.checkInferTrustedSdkEagerModules(view, actual, sdk);
};
const bind = originals => {
  bindingCalls++;
  runtime.bindInferTrustedSdkStaticModules(view, actual, originals);
  runtime.checkInferTrustedSdkStaticModules(view, actual, originals);
  return requireOriginalEager;
};
const moon = {clientProgramInstallModelProvider() { constructors++; return {}; }};
const entry = {providerId: 'fixture', invoke() { assert.fail('No Provider call'); },
  validatePrompt() { return true; }, sdkStaticOriginals: sdk};
const installed = installModelProviders(moon, () => [entry], current, current, bind).get('fixture');
assert.equal(constructors, 1);
assert.equal(eagerCalls, 0, 'static registration does not silently require eager startup');
const requireEager = installed.requireEagerSdkStartup;
assert.equal(typeof requireEager, 'function');
entry.sdkStaticOriginals = undefined;
installed.assertTrustedRuntime();
assert.equal(installed.requireEagerSdkStartup, requireEager, 'one immutable original function');
assert.ok(bindingCalls >= 2);
if (mode === 'eager') {
  requireEager();
  requireEager();
  assert.equal(eagerCalls, 2);
} else {
  assert.throws(requireEager, {code: 'InferTrustedSdkEagerUnavailable'});
  process.execArgv.unshift('--no-lazy');
  installed.assertTrustedRuntime();
  assert.throws(requireEager, {code: 'InferTrustedSdkEagerUnavailable'});
  assert.equal(eagerCalls, 2);
}
assert.ok(currentCalls > eagerCalls);
// A public/registration field cannot manufacture the private Host connection.
assert.throws(() => installModelProviders(moon, () => [{...entry,
  requireEagerSdkStartup() { assert.fail('Registration callback is not the issuer'); }}]),
TypeError);
assert.equal(constructors, 1);
runtime.forgetInferTrustedStartupView(view, actual.host, actual.generation);
runtime.forgetInferTrustedRuntimeView(view, actual.host, actual.generation);
const prior = eagerCalls;
assert.throws(requireEager, {code: 'InferTrustedRuntimeViewRetired'});
assert.equal(eagerCalls, prior, 'retired original refuses before the retained predicate');
console.log(JSON.stringify({mode, constructors, checked: true, actualHost: false,
  actualCore: false, providerCalls: 0, normalNumericProfile: null, publicE2E: 0}));
