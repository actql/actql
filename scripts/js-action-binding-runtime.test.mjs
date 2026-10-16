import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as owner from '../_build/js/release/build/interface_action_probe/interface_action_probe.js';
import {publicationAction} from '../adapters/host-common/publication-action.mjs';
import {strategyAction} from '../adapters/host-common/strategy-actions.mjs';
import {actionBoundaries} from './js-action-boundaries.mjs';

test('generated names agree with every actual compiled Owner action projection', () => {
  const rows = owner.bindingActionCodes();
  const kinds = new Set();
  for (const [family,kind,variant,name,rawCode] of rows) {
    const code = Number(rawCode);
    assert.equal(String(code), rawCode);
    const actual = family === 'publication' ? publicationAction(kind,code) : strategyAction[kind](code);
    assert.equal(actual,name,`${family}/${kind}/${variant}`);
    kinds.add(`${family}/${kind}`);
  }
  assert.equal(kinds.size,actionBoundaries.length);
  console.log(`ACTQL_ACTUAL_OWNER_ACTION_VARIANTS ${rows.length}`);
});

test('real Owner pending close does not become release; confirmed close does', () => {
  assert.equal(strategyAction.holding(owner.bindingHoldingPendingClose()),'RetainedSiteAwaitClose');
  assert.equal(strategyAction.holding(owner.bindingHoldingConfirmedClose()),'RetainedSiteReleaseHolding');
  assert.equal(publicationAction('commitFailure',owner.bindingPublicationCommitUnknown()),'append_unknown');
});

const swappedModule = async (path,first,second) => {
  const original = readFileSync(new URL(path,import.meta.url),'utf8');
  const a = JSON.stringify(first), b = JSON.stringify(second);
  assert.equal(original.split(a).length,2);
  assert.equal(original.split(b).length,2);
  const mutated = original.replace(a,'"__ACTQL_SWAP__"').replace(b,a).replace('"__ACTQL_SWAP__"',b);
  assert.notEqual(mutated,original);
  return import('data:text/javascript;base64,'+Buffer.from(mutated).toString('base64'));
};

test('action-number swap is caught by the real Owner close/holding boundary', async () => {
  const mutant = await swappedModule('../adapters/host-common/strategy-actions.mjs',
    'RetainedSiteAwaitClose','RetainedSiteReleaseHolding');
  // Both names and numeric codes remain valid. The intended behavioral
  // assertion, not import/startup/unknown-code refusal, rejects the mutant.
  assert.throws(() => assert.equal(mutant.strategyAction.holding(
    owner.bindingHoldingPendingClose()),'RetainedSiteAwaitClose'),{code:'ERR_ASSERTION'});
});

test('action-number swap cannot turn lost commit into adoption', async () => {
  const mutant = await swappedModule('../adapters/host-common/publication-action.mjs',
    'append_unknown','adopt_committed_index');
  assert.throws(() => assert.equal(mutant.publicationAction('commitFailure',
    owner.bindingPublicationCommitUnknown()),'append_unknown'),{code:'ERR_ASSERTION'});
});
