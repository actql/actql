import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {sheetsRangeCommand, sheetsRangeReference, createSheetsRangeDriver,
  withSheetsRangeCommand} from '../host/sheets-range-command.mjs';

type Provider = Parameters<typeof sheetsRangeCommand>[2] &
  Parameters<typeof createSheetsRangeDriver>[0]['moon'] &
  Parameters<typeof sheetsRangeReference>[0]['moon'] &
  Parameters<typeof withSheetsRangeCommand>[2];
type Baseline = Readonly<{
  connectorId: string; site: Parameters<typeof sheetsRangeCommand>[1]; catalogCid: string; bindingCid: string;
  commandCid: string; inputContractCid: string; outputContractCid: string; providerIdentityCid: string;
  rangeIdentityCid: string; value: unknown; requestBody: string; requestCid: string; catalogInput: unknown;
}>;
type LineageCommand = Record<string, unknown> & {contract_cid: string; minimum_approval?: string};
type Lineage = Readonly<{
  command: LineageCommand; recovery: unknown; recoveryObservationCid: string;
  catalog: unknown; catalogWithCommandCid: string;
}>;
const moon: Provider = await import(new URL(
  '../../../../_build/js/release/build/connectors/sheets/host_node/host_node.js', import.meta.url).href);

// Captured before the authority move from the fixed pre-refactor source. Never
// regenerate these expectations from the candidate implementation.
const baseline = JSON.parse(readFileSync(new URL('./fixtures/range-owned-baseline.json', import.meta.url), 'utf8')) as Baseline;
const carriage = JSON.parse(readFileSync(new URL('./fixtures/range-command-approval-carriage.json', import.meta.url), 'utf8')) as
  {predecessor: Lineage; current: Lineage};
const hash = (value: unknown) => `sha256:${createHash('sha256').update(canonicalJson(value)).digest('hex')}`;
test('Sheets authority move preserves the original request bytes and explicit Command-law identity lineage', () => {
  const command = sheetsRangeCommand(baseline.connectorId, baseline.site, moon);
  const target = sheetsRangeReference({site: baseline.site,
    catalogCid: baseline.catalogCid, bindingCid: baseline.bindingCid, moon});
  assert.equal(carriage.predecessor.command.contract_cid, baseline.commandCid);
  for (const entry of [carriage.predecessor, carriage.current]) {
    const {contract_cid, ...preimage} = entry.command;
    assert.equal(hash(preimage), contract_cid);
    assert.equal(hash(entry.recovery), entry.recoveryObservationCid);
    assert.equal(hash(entry.catalog), entry.catalogWithCommandCid);
  }
  const previous: Partial<LineageCommand> = structuredClone(carriage.predecessor.command);
  delete previous.minimum_approval;delete previous.contract_cid;
  const {contract_cid, ...current} = carriage.current.command;
  assert.deepEqual(previous, current);
  assert.deepEqual(command.command, carriage.current.command);
  assert.equal(command.command.input_schema.cid, baseline.inputContractCid);
  assert.equal(command.command.output_schema.cid, baseline.outputContractCid);
  assert.equal(target.provider_identity_cid, baseline.providerIdentityCid);
  assert.equal(target.identity_cid, baseline.rangeIdentityCid);
  const driver = createSheetsRangeDriver({moon, site: baseline.site, command: command.installed,
    bindingCid: baseline.bindingCid, target, isCurrent: () => true});
  const member = {resource: 'range_target', effectId: 'replace'};
  const request = driver.prepareRequest({member, value: baseline.value, selector: target}).request;
  assert.equal(request.body, baseline.requestBody);
  assert.equal(driver.requestCid(request), baseline.requestCid);
  assert.equal(driver.recoveryEntry({member}).observationCid, carriage.current.recoveryObservationCid);
  assert.equal(withSheetsRangeCommand(baseline.catalogInput, command, moon).catalog_cid,
    carriage.current.catalogWithCommandCid);
});
