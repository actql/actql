import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/sheets/host_node/host_node.js';
import {sheetsRangeCommand, sheetsRangeReference, createSheetsRangeDriver,
  withSheetsRangeCommand} from '../host/sheets-range-command.mjs';

// Captured before the authority move from the fixed pre-refactor source. Never
// regenerate these expectations from the candidate implementation.
const baseline = JSON.parse(readFileSync(new URL('./fixtures/range-owned-baseline.json', import.meta.url)));
test('Sheets authority move preserves the original request bytes and all identity domains', () => {
  const command = sheetsRangeCommand(baseline.connectorId, baseline.site, moon);
  const target = sheetsRangeReference({site: baseline.site,
    catalogCid: baseline.catalogCid, bindingCid: baseline.bindingCid, moon});
  assert.equal(command.command.contract_cid, baseline.commandCid);
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
  assert.equal(driver.recoveryEntry({member}).observationCid, baseline.recoveryObservationCid);
  assert.equal(withSheetsRangeCommand(baseline.catalogInput, command, moon).catalog_cid,
    baseline.catalogWithCommandCid);
});
