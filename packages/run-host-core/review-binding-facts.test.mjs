import assert from 'node:assert/strict';
import {registerHooks} from 'node:module';
import test from 'node:test';

// Explicit ABI ports test facade custody and forwarding only. Actual Common
// admission and its immutable projection are qualified separately.
const abi = `
export const calls = [];
export const clientValuesHostAdmitRunEvidenceValue = (name, wire, ...limits) => {
  const value = {name, wire};
  calls.push({name: 'admit', args: [name, wire, ...limits], value});
  return {$tag: 1, _0: value};
};
export const clientValuesHostRunEvidenceValueIdentity = () => 'fixture:review';
export const clientValuesHostRunEvidenceValueWire = value => value.wire;
export const clientValuesHostEffectReviewProjectionBindingFacts = value => {
  calls.push({name: 'facts', value});
  return value.name === 'review_projection' ?
    ['original Preview', 'original Authoring Context', 'original scope', 'effect_scope_approved'] : [];
};`;
const abiUrl = 'data:text/javascript,' + encodeURIComponent(abi);
const source = new URL('./index.mjs', import.meta.url);
const hook = registerHooks({resolve(specifier, context, next) {
  if (specifier === './dist/client_values_host_abi.js' && context.parentURL &&
      new URL(context.parentURL).pathname === source.pathname) {
    return {url: abiUrl, shortCircuit: true};
  }
  return next(specifier, context);
}});
const owner = await import(source.href);
const foreign = await import(source.href + '?foreign-review-facts');
const {calls} = await import(abiUrl);
hook.deregister();
const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 32};

test('Review facts consume the original evidence without parsing caller-visible wire or readmission', async () => {
  const review = owner.admitRunEvidenceValue('review_projection', 'opaque synthetic fixture', limits);
  const original = calls.at(-1).value;
  calls.length = 0;
  const first = owner.effectReviewProjectionBindingFacts(review);
  await Promise.resolve();
  const second = owner.effectReviewProjectionBindingFacts({...review, wire: 'foreign visible DATA', cid: 'foreign'});
  assert.deepEqual(first, {previewCid: 'original Preview', authoringContextCid: 'original Authoring Context',
    authorityScopeCid: 'original scope', approvalClaims: ['effect_scope_approved']});
  assert.deepEqual(second, first);
  assert(Object.isFrozen(first)); assert(Object.isFrozen(first.approvalClaims));
  assert.throws(() => first.approvalClaims.push('partial_application_accepted'), TypeError);
  assert(calls.every(call => call.name === 'facts'), 'Pure observation must not invoke evidence admission');
  assert(calls.every(call => call.value === original), 'Any projection consumes the same original');
});

test('Review facts refuse copied tokens foreign namespaces and a different admitted family', () => {
  const review = owner.admitRunEvidenceValue('review_projection', 'fixture', limits);
  const other = foreign.admitRunEvidenceValue('review_projection', 'fixture', limits);
  calls.length = 0;
  for (const value of [{...review, token: {...review.token}}, other, 'raw wire', undefined]) {
    assert.throws(() => owner.effectReviewProjectionBindingFacts(value), /ForeignRunHostHandle/u);
  }
  assert.equal(calls.length, 0, 'Foreign originals must refuse before the ABI');
  const authoring = owner.admitRunEvidenceValue('authoring_context', 'fixture', limits);
  assert.throws(() => owner.effectReviewProjectionBindingFacts(authoring), /InvalidRunHostReviewProjection/u);
});
