import test from 'node:test';
import assert from 'node:assert/strict';
import {mutationCampaignScope, fixedJsAction} from './fixed-js-scope.mjs';
import {runMutations} from './mutations.mjs';
import {inspectMutationPart} from './mutation-parts.mjs';
import {validateFixedJsReport, fixedJsScientificObservation} from './fixed-js-replay.mjs';
import {verifyFixedJsTamperRefusals, eraseFixedJsDetection} from '../ci-evidence/local-isolated-acceptance.mjs';
import {controlledFixedJsOriginal} from './fixtures/fixed-js-original.mjs';
import {readFileSync} from 'node:fs';
import {applyMutation, sites} from './sites.mjs';
import {hash} from './inventory.mjs';

const local = {profile:'local-fixed-js', mode:'fixed', partId:'L-M0', revision:'a'.repeat(40)};
test('the ordinary runner keeps all targets; the separate local scope fixes its part, minima and all phases', () => {
  for (const mode of ['fixed','explore','auto','verify'])
    assert.deepEqual(mutationCampaignScope({mode}).targets, ['js','wasm','native']);
  assert.deepEqual(mutationCampaignScope(local).targets, ['js']);
  assert.deepEqual(fixedJsAction.phases, ['mutated','pristine','post-restore']);
});
test('the current checked-handoff mutation changes only the producer binding and preserves the independent port trace', () => {
  const site = sites[0], original = readFileSync(new URL(`../../${site.path}`, import.meta.url), 'utf8');
  assert.equal(original.split(site.before).length, 2);
  const mutated = applyMutation(original, site);
  assert.equal(mutated.split(site.after).length, 2);
  assert(mutated.includes('cursor.port + 1'));
  assert(mutated.includes('cursor.step.to_string()') && mutated.includes('cursor.port.to_string()'));
  const separateProbe = '\nfn relation_chain_inputs_are_small(';
  assert.equal(mutated.slice(mutated.indexOf(separateProbe)), original.slice(original.indexOf(separateProbe)));
});
for (const [name, alter] of [
  ['other part', x => x.partId = 'L-M1'], ['missing revision', x => delete x.revision],
  ['exploration', x => x.mode = 'explore'], ['unreviewed targets', x => x.targets = ['native']],
  ['unknown profile', x => x.profile = 'another-profile'],
]) test(`scope rejects ${name} before compiler/workspace execution`, async () => {
  const changed = {...local}; alter(changed);
  assert.throws(() => mutationCampaignScope(changed));
  await assert.rejects(runMutations(changed));
});

test('controlled phase copies require all independent anchors, actual raw observations and new-owner restoration', () => {
  const {payload, context} = controlledFixedJsOriginal();
  assert(validateFixedJsReport({report:payload.report,files:payload.files,...context}));
  assert.throws(() => inspectMutationPart(payload.report), 'A local JS projection cannot satisfy the three-target part');
});
test('thirteen altered copies refuse without changing their controlled original', () => {
  const {payload, context} = controlledFixedJsOriginal(), original = structuredClone(payload);
  assert.equal(verifyFixedJsTamperRefusals(payload, context).length, 13);
  assert.deepEqual(payload, original);
});
test('a re-sealed successful observation cannot stand in for an actually anchored defect', () => {
  const {payload, context} = controlledFixedJsOriginal();
  eraseFixedJsDetection(payload);
  assert.equal(payload.report.results[0].killed, true);
  assert.throws(() => validateFixedJsReport({report:payload.report,files:payload.files,...context}), /Declared detection differs/u);
});
test('cross-phase comparison retains scientific rows, NULL, contract types, work and ordering', () => {
  const {payload} = controlledFixedJsOriginal(), altered = structuredClone(payload.report);
  for (const result of altered.results) for (const observation of [result.replay.js,result.healthy.js,result.postRestore.observations.js]) observation.id += ':another-invocation';
  assert.deepEqual(fixedJsScientificObservation(altered), fixedJsScientificObservation(payload.report));
  altered.results[1].healthy.js.wireRows.reverse();
  assert.notDeepEqual(fixedJsScientificObservation(altered), fixedJsScientificObservation(payload.report));
});

test('controlled copies bind current mutation sources and reject another source body', () => {
  const {payload, context} = controlledFixedJsOriginal();
  for (const result of payload.report.results) {
    const current = readFileSync(new URL(`../../${result.site}`, import.meta.url));
    assert.deepEqual(context.readSource(result.site), current);
    assert.equal(context.source.sources[result.site], hash(current));
    assert.equal(result.originalDigest, hash(current));
  }
  const selected = payload.report.results[0].site;
  const readSource = path => path === selected
    ? Buffer.concat([context.readSource(path), Buffer.from('\n// changed source body\n')])
    : context.readSource(path);
  assert.throws(() => validateFixedJsReport({report: payload.report,
    files: payload.files, ...context, readSource}), /Original mutation bytes differ/u);
});
