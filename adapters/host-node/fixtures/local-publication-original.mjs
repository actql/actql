// Explicit-port fixtures retain a genuine checked publication preparation.
// This is immutable compiler DATA, not Host funding, a Run or physical supply.
import {readFileSync} from 'node:fs';
import {checked} from '../../host-common/runtime-result.mjs';
const read = path => readFileSync(new URL('../../../'+path, import.meta.url), 'utf8');
const aoa = JSON.parse(read('spec/contracts/actql-aoa.json'));
const contracts = ['REL.values', 'ACTQL.expression_fragment/0.1', 'REL.derive.ordered']
  .map(name => JSON.stringify(aoa.execution_contracts[name]));
const registry = read('spec/dependencies/aoa-pipeline-registry.json');
export function publicationOriginalFixture(moon, prepared) {
  const original = checked(moon.clientPrepareInstalledSequenceContracts(registry, ...contracts));
  return Object.freeze({kind: 'preparation',
    value: checked(moon.clientProgramPrepareInstalledManagedSourceFreeWithContracts(
      prepared, original, ...contracts))});
}
