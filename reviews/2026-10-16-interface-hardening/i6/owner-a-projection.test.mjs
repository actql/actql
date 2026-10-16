import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {test} from 'node:test';
import {projectOwnerSources} from '../../../scripts/interface-owner-source-projection.mjs';

test('A fixed owner product blobs are projected by the existing I6 syntax API', () => {
  const result = projectOwnerSources(process.cwd(), {
    source: '09e3c064a405b1b505a759c12b74e090ec233a0d',
    base: '02f9e53f29b4913d5c6e8276d2ac248800fe8173'});
  assert.equal(result.modules.filter(value => value.module.endsWith('/compiler-binding.generated.mjs')).length, 6);
  assert(result.modules.every(value => value.sha256.length === 64 && Array.isArray(value.operations)));
  writeFileSync('/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/a-09e3-owner-source-projection.json',
    JSON.stringify({...result, readerSource: '5f4a2cbe9b78f5d16ba5c1b9f075f78b167f6770'}, null, 2) + '\n');
});
