import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/sheets/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {prepareSheetsAppend} from '../site/sheets-exchange.mjs';
import {sheetsRangeReference} from '../host/sheets-range-command.mjs';
import {contentCid} from '../../../host-node/local-account-config.mjs';
const original = JSON.parse(readFileSync(new URL('./fixtures/append-owned-baseline.json', import.meta.url)));

test('append shares the portable request preimage owner and original fixed bytes', () => {
  const request = prepareSheetsAppend({...original, moon});
  assert.equal(request.body, original.body);
  assert.equal(request.path, original.path);
  assert.equal(request.requestCid, original.requestCid);
  const hash = createHash('sha256');
  for (const value of ['actql-sheets-append-request/0.1', original.origin,
    'POST', original.path, original.body]) {
    const bytes = Buffer.from(value);
    hash.update(`${bytes.length}:`); hash.update(bytes);
  }
  assert.equal(request.requestCid, `sha256:${hash.digest('hex')}`);
  for (const [origin, path, body] of [
    ['https://foreign.example.test', original.path, original.body],
    [original.origin, original.path + '?foreign=1', original.body],
    [original.origin, original.path, original.body.normalize('NFC')],
    [original.origin, original.path, original.body + '\n'],
  ]) assert.notEqual(checked(moon.sheetsAppendRequestIdentity(origin, path, body)), original.requestCid);
});

test('append retains original pre-request refusal and literal value rules', () => {
  assert.throws(() => prepareSheetsAppend({...original, moon, spreadsheetId: '../foreign'}),
    {code: 'InvalidSheetsSpreadsheetId'});
  for (const value of [{...original.value, text: ''}, {...original.value, text: null},
    {...original.value, flag: null}, {...original.value, number: []}]) {
    assert.throws(() => prepareSheetsAppend({...original, moon, value}),
      {code: 'SheetsContractRefused'});
  }
});

test('range identity rejects negative zero before scalar ABI erasure, like the original identity preimage', () => {
  const token = `sha256:${'a'.repeat(64)}`;
  const range = {sheetId: 7, startRow: 0, endRow: 2, startColumn: 0, endColumn: 3};
  for (const field of Object.keys(range)) {
    const invalid = {...range, [field]: -0};
    assert.throws(() => contentCid({version: 'actql-sheets-range/0.1', range: invalid}),
      {code: 'InvalidCanonicalNumber'});
    assert.throws(() => sheetsRangeReference({moon,
      site: {apiOrigin: original.origin, spreadsheetId: original.spreadsheetId, gridRange: invalid},
      catalogCid: token, bindingCid: token}), {code: 'InvalidCanonicalNumber'});
  }
});
