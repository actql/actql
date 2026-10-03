import assert from 'node:assert/strict';
import test from 'node:test';
import {rehearsalInputs} from '../../scripts/rehearse-foundation-supplement.mjs';

test('real-history rehearsal requires two explicit commit SHAs and a supplement file', () => {
  assert.deepEqual(rehearsalInputs(['--source', '1'.repeat(40), '--validator', '2'.repeat(40), '--supplement', 'receipt.json']),
    {source: '1'.repeat(40), validator: '2'.repeat(40), supplementFile: 'receipt.json'});
});

test('real-history rehearsal never defaults to runtime HEAD or branch names', () => {
  for (const args of [[], ['--source', '1'.repeat(40)],
    ['--source', 'HEAD', '--validator', '2'.repeat(40), '--supplement', 'receipt.json'],
    ['--source', '1'.repeat(40), '--validator', 'main', '--supplement', 'receipt.json']]) {
    assert.throws(() => rehearsalInputs(args), /Usage:/);
  }
});

test('real-history rehearsal rejects duplicate or unknown options and empty receipt paths', () => {
  for (const args of [
    ['--source', '1'.repeat(40), '--source', '2'.repeat(40), '--supplement', 'receipt.json'],
    ['--source', '1'.repeat(40), '--other', '2'.repeat(40), '--supplement', 'receipt.json'],
    ['--source', '1'.repeat(40), '--validator', '2'.repeat(40), '--supplement', '']]) {
    assert.throws(() => rehearsalInputs(args), /Usage:/);
  }
});
