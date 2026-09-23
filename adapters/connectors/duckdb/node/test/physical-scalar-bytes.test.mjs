import assert from 'node:assert/strict';
import test from 'node:test';
import {exportPhysicalValue, physicalJsonScalarBytes,
  PhysicalValueError} from '../physical-values.mjs';

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

test('floating physical transport preserves exact special bit patterns', () => {
  assert.equal(exportPhysicalValue(-0, {id: 'DOUBLE'}), '8000000000000000');
  assert.equal(exportPhysicalValue(-0, {id: 'FLOAT'}), '80000000');
  assert.equal(exportPhysicalValue(Infinity, {id: 'DOUBLE'}), '7ff0000000000000');
  assert.equal(exportPhysicalValue(-Infinity, {id: 'FLOAT'}), 'ff800000');
  assert.equal(exportPhysicalValue(1.5, {id: 'DOUBLE'}), '3ff8000000000000');
  assert.equal(exportPhysicalValue(1.5, {id: 'FLOAT'}), '3fc00000');
  // Alternating widths must not expose stale bytes from the shared scratch.
  assert.equal(exportPhysicalValue(-0, {id: 'DOUBLE'}), '8000000000000000');
});
