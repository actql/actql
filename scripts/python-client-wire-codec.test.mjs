import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {pythonStructuralValidatorSource, pythonResponseValidatorSource} from './python-client-wire-codec.mjs';

test('Python structural codec is generated and the Remote facade delegates to it', async () => {
  const base = 'packages/python-sdk/src/actql_sdk/';
  const contract = JSON.parse(await readFile(base + '_contract.json', 'utf8'));
  assert.equal(await readFile(base + '_wire_codec.py', 'utf8'), pythonStructuralValidatorSource() + pythonResponseValidatorSource(contract.check_report_rules));
  const facade = await readFile(base + '_wire.py', 'utf8');
  assert.match(facade, /from \._wire_codec import \(CONTRACT, SCHEMAS, valid, utf16_length/u);
  assert.doesNotMatch(facade, /^def valid\(/mu);
  assert.doesNotMatch(pythonStructuralValidatorSource(), /wasmtime|_local_core|subprocess/u);
});
