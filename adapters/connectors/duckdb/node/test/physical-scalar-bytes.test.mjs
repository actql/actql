import assert from 'node:assert/strict';
import test from 'node:test';
import {physicalJsonScalarBytes, PhysicalValueError} from '../physical-values.mjs';

test('physical scalar frame accounting matches encoded JSON bytes', () => {
  const values = [null, true, false, '', '0123456789abcdef', 'a/b',
    'quote"', 'back\\slash', 'line\nfeed', '\u0000', '\u007f',
    '日本語', 'é', '😀', '\ud800', '\udc00', 'a\ud83d\ude00z'];
  for (const value of values) {
    assert.equal(physicalJsonScalarBytes(value),
      Buffer.byteLength(JSON.stringify(value), 'utf8'),
      JSON.stringify(value));
  }
  assert.throws(() => physicalJsonScalarBytes(1),
    error => error instanceof PhysicalValueError && error.code === 'InvalidPhysicalValue');
});
