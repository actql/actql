import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {unaliasedColumnOrigins} from './fixtures/unaliased-column-origin.mjs';
import {sourceFreeRefusals} from './fixtures/public-query-input.mjs';

test('authored origin expectations retain exact original bytes and repeated spellings', () => {
  assert.equal(unaliasedColumnOrigins.length, 8);
  for (const {text, start, end, token} of unaliasedColumnOrigins) {
    assert.equal(Buffer.from(text).subarray(start, end).toString('utf8'), token);
  }
  assert.equal(unaliasedColumnOrigins[1].text, '/*😀*/\r\nSELECT missing');
  assert.deepEqual(unaliasedColumnOrigins[7], {text: '/* missing */ SELECT missing',
    start: 21, end: 28, token: 'missing'});
});

test('the normal packed public check uses the origin fixture at both existing entrances', () => {
  const app = readFileSync(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = readFileSync(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(app.includes('await exerciseUnaliasedColumnOrigins(client, publicCheckSdk)'));
  assert.ok(driver.includes("['scripts/fixtures/unaliased-column-origin.mjs', 'unaliased-column-origin.mjs']"));
  assert.ok(app.includes('packed public check ${options.mode} passed'));
});

test('source-free star retains the existing explicit implementation-limit refusal', () => {
  assert.deepEqual(sourceFreeRefusals.find(value => value.name === 'source-free-star'),
    {name: 'source-free-star', format: 'sql', text: 'SELECT *',
      expectedCode: 'ClientProgramImplementationLimit'});
});
