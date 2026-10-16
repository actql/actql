import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import {pythonStructuralValidatorSource, pythonResponseValidatorSource} from './python-client-wire-codec.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
test('Python structural codec matches generated output', async () => {
  const base = new URL('../packages/python-sdk/src/actql_sdk/', import.meta.url);
  const contract = JSON.parse(await readFile(new URL('_contract.json', base), 'utf8'));
  assert.equal(await readFile(new URL('_wire_codec.py', base), 'utf8'),
    pythonStructuralValidatorSource() + pythonResponseValidatorSource(contract.check_report_rules));
});

test('Remote facade shares the real generated objects without Local runtime dependencies', () => {
  const output = execFileSync(process.env.ACTQL_PYTHON ?? 'python3',
    ['-I', 'scripts/fixtures/python-wire-delegation.py', root],
    {cwd: root, encoding: 'utf8', timeout: 10000});
  assert.equal(output.trim(), 'Python codec delegation and Remote-only import: passed');
});
