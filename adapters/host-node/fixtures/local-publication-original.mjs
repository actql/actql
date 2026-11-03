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
  request, identity, acquisition, limits, installedContracts, contracts: bodies}) {
  const capacity = moon.clientProgramInstalledDuckDBCaptureCapacity(
    moon.clientProgramCapturedNativeConfiguration(acquisition));
  assert.ok(capacity);
  const physical = computePhysicalCapacity(limits);
  const [, values, fragment, ordered] = bodies;
  return preparation.manager.adoptCapturePreparation(prepared, request, identity,
    () => checked(moon.clientProgramInstalledManagedCapturePlanPrepare(
      prepared, identity, [capacity], [physical.transferBytes], [physical.executionBytes],
      installedContracts, values, fragment, ordered, true, undefined)));
}
