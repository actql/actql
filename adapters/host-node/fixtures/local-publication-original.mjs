// Explicit-port fixtures use the existing checked preparation owners.
// Source-free material is immutable DATA; captured publication adopts its real Request.
import assert from 'node:assert/strict';
import {computePhysicalCapacity} from '../../connectors/duckdb/node/physical-capacity.mjs';
import {readFileSync} from 'node:fs';
import {checked} from '../../host-common/runtime-result.mjs';
const read = path => readFileSync(new URL('../../../'+path, import.meta.url), 'utf8');
const aoa = JSON.parse(read('spec/contracts/actql-aoa.json'));
const contracts = ['REL.values', 'ACTQL.expression_fragment/0.1', 'REL.derive.ordered']
  .map(name => JSON.stringify(aoa.execution_contracts[name]));
const registry = read('spec/dependencies/aoa-pipeline-registry.json');
export function publicationOriginalFixture(moon, prepared, retainedOutput = false) {
  assert.equal(typeof retainedOutput, 'boolean');
  const original = checked(moon.clientPrepareInstalledSequenceContracts(registry, ...contracts));
  return Object.freeze({kind: 'preparation',
    value: checked(moon.clientProgramPrepareInstalledManagedSourceFreeWithContracts(
      prepared, original, ...contracts, retainedOutput))});
}

// The same Request adopts this actual capture Plan before physical capture.
// Its original Run supplies both compilation and publication; the immutable
// Plan alone is neither an admitted Run nor a substitute publication owner.
export function adoptCapturedPublicationFixture({moon, preparation, prepared,
  request, identity, acquisition, limits, captures, installedContracts, contracts: bodies}) {
  const originals = captures ?? [{acquisition, limits}];
  assert.ok(Array.isArray(originals) && originals.length >= 1 && originals.length <= 2);
  assert.ok(captures === undefined || acquisition === undefined && limits === undefined);
  const capacities = originals.map(original => {
    const capacity = moon.clientProgramInstalledDuckDBCaptureCapacity(
      moon.clientProgramCapturedNativeConfiguration(original.acquisition));
    assert.ok(capacity);
    return capacity;
  });
  const physical = originals.map(original => computePhysicalCapacity(original.limits));
  const [, values, fragment, ordered] = bodies;
  const run = preparation.manager.adoptCapturePreparation(prepared, request, identity,
    () => checked(moon.clientProgramInstalledManagedCapturePlanPrepare(
      prepared, identity, capacities, physical.map(value => value.transferBytes),
      physical.map(value => value.executionBytes),
      installedContracts, values, fragment, ordered, true, undefined)));
  // The plural fixture must pass these SAME opaque capacities to its Ledger,
  // rather than issuing equal-shaped replacements after Plan adoption.
  return captures === undefined ? run : Object.freeze({run,
    capacities: Object.freeze(capacities), physical: Object.freeze(physical)});
}
