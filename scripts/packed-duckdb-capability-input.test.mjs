import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';
import {machineCid} from './actql-spec-family.mjs';

test('packed DuckDB Source advertises the current native receipt contract without changing its selector', () => {
  const source = readFileSync(new URL('./test-node-client-package.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const assignments = ast.body.filter(node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'AssignmentExpression' &&
    node.expression.left.type === 'MemberExpression' &&
    node.expression.left.object.name === 'sourceEnvironment' &&
    node.expression.left.property.name === 'connector_capabilities');
  assert.equal(assignments.length, 1);
  const selector = Object.freeze({source_ref: 'connector://original/source#view',
    source_contract_cid: 'original-source', source_view_contract_cid: 'original-view', read_mode: 'snapshot'});
  const original = assignments[0];
  const actual = compileFunction('const sourceEnvironment = {};\n' +
    source.slice(original.start, original.end) + '\nreturn sourceEnvironment.connector_capabilities;',
  ['sourceSelector'])(selector);
  // Independent authored canonical contract, not the runtime's selection output.
  const contract = JSON.parse(readFileSync(new URL('../spec/contracts/actql-query-two-receipt.json', import.meta.url), 'utf8'));
  const expected = machineCid(contract);
  const core = readFileSync(new URL('../src/query_planning/two_receipt_contract.mbt', import.meta.url), 'utf8');
  assert.equal(core.match(/let query_two_receipt_cid : String = "([^"]+)"/u)?.[1], expected);
  assert.deepEqual(actual, [{...selector, capability_contract_cids: [expected]}]);
});
