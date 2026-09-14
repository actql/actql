import assert from 'node:assert/strict';
import {test} from 'node:test';
import {validateMachineImports, loadSpecFamily} from './actql-spec-family.mjs';

const cid = 'sha256:' + '0'.repeat(64);
const marker = `<!-- machine-import: ../../spec/contracts/example.json#/schemas/value ${cid} -->`;
const doc = {
  path: 'docs/spec/example.md', source: marker,
  machine_contracts: [{path: 'spec/contracts/example.json', pointer: '/schemas/value', cid}],
};

test('machine imports require exact registration in both directions', () => {
  validateMachineImports([doc, {path: 'docs/spec/empty.md', source: ''}]);
  for (const altered of [
    {...doc, machine_contracts: []},
    {...doc, source: ''},
    {...doc, source: marker.replace('/schemas/value', '/schemas/other')},
    {...doc, source: marker.replace(cid, 'sha256:' + '1'.repeat(64))},
    {...doc, source: marker.replace('example.json', 'other.json')},
    {...doc, machine_contracts: [...doc.machine_contracts, ...doc.machine_contracts]},
  ]) assert.throws(() => validateMachineImports([altered]), /unregistered or missing machine import/);
});

test('root imports, escaped pointers and source order do not weaken matching', () => {
  const root = {path: 'spec/contracts/example.json', pointer: '', cid};
  const escaped = {...root, pointer: '/schemas/a~1b~0c'};
  const source = [escaped, root].map(r => `<!-- machine-import: ../../${r.path}#${r.pointer} ${cid} -->`).join('\n');
  validateMachineImports([{...doc, source, machine_contracts: [root, escaped]}]);
  assert.throws(() => validateMachineImports([{...doc, source: marker + '\n' + marker}]), /duplicate machine import/);
  assert.throws(() => validateMachineImports([{...doc, source: marker.replace(cid, 'not-a-cid')}]), /invalid machine import/);
  const line = `../../spec/contracts/example.json#/schemas/value ${cid}`;
  const normative = `<!-- normative-code: law -->\n\`\`\`text\n${line}\n\`\`\``;
  validateMachineImports([{...doc, source: normative}]);
  for (const section of ['stage-contract', 'lookup-identity']) {
    validateMachineImports([{...doc, source: normative.replace('normative-code: law', `${section}-pins:start`)}]);
  }
  // Legacy citations are not new ownership declarations. Cross-owner legacy
  // references remain governed by the document import graph.
  validateMachineImports([{...doc, source: normative, machine_contracts: []}]);
});

test('every explicit machine-import marker has a pinned owner registration', () => {
  const family = loadSpecFamily();
  const execution = family.documents.find(d => d.document_id === 'execution');
  const analytic = execution.machine_contracts.filter(r => r.path === 'spec/contracts/actql-analytic-numeric-slot.json');
  assert.deepEqual(analytic.map(r => r.pointer).toSorted(), ['', '/schemas/analytic_slot']);
  validateMachineImports(family.documents);
});
