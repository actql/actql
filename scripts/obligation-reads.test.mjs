import assert from 'node:assert/strict';
import test from 'node:test';
import {validateObligationReads} from './check-obligation-reads.mjs';

const complete = [
  'pub fn pending_validations(Checked) -> Array[Obligation]',
  'pub fn pending_validation_count(Checked) -> Int',
  'pub fn pending_validation_at(Checked, Int) -> Obligation?',
].join('\n');
test('indexed obligation coverage checks count, item type and input owner', () => {
  assert.equal(validateObligationReads(complete, 'fixture'), 1);
  for (const broken of [
    complete.split('\n').filter(l => !l.includes('_count(')).join('\n'),
    complete.split('\n').filter(l => !l.includes('_at(')).join('\n'),
    complete.replace('-> Obligation?', '-> Other?'),
    complete.replace('_at(Checked, Int)', '_at(Foreign, Int)'),
  ]) assert.throws(() => validateObligationReads(broken, 'fixture'));
});
test('new obligation arrays cannot silently omit indexed reads', () => {
  assert.throws(() => validateObligationReads(`${complete}\npub fn new_pending(Other) -> Array[@owner.Obligation]`, 'fixture'));
  assert.equal(validateObligationReads('pub fn fields(Checked) -> Array[String]', 'fixture'), 0);
});
