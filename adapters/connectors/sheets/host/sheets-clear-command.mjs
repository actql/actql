// The portable provider retains original requests; the installed Effect owner
// retains approval, durable claims, current installation and cleanup custody.
import {randomUUID} from 'node:crypto';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {prepareSheetsClear, projectSheetsClear, sendSheetsClear,
  SHEETS_CLEAR_OPERATION, SHEETS_LIMITS} from '../site/sheets-exchange.mjs';
import {sheetsOwnedResult} from '../site/sheets-owned-request.mjs';
import {projectOwnedSheetsClearRequest, ownedSheetsClearRequestCid,
  ownedSheetsClearRecoveryEntry} from '../site/sheets-clear-request.mjs';

const wire = value => canonicalJson(value, {dataKeys: true});
const limits = bytes => [bytes, SHEETS_LIMITS.maxNodes, SHEETS_LIMITS.maxDepth, SHEETS_LIMITS.maxCells];
const fail = code => { throw Object.assign(new Error(code), {code}); };

export function sheetsClearCommand(connectorId, site, moon) {
  return Object.freeze(JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsClearCommandJson(connectorId, JSON.stringify(site.columns),
      JSON.stringify(site.gridRange), ...limits(SHEETS_LIMITS.maxResponseBytes)))));
}

export function createSheetsClearDriver({moon, site, command, bindingCid, target, isCurrent}) {
  const binding = sheetsOwnedResult(moon, moon.sheetsClearBinding(JSON.stringify({
    origin: site.apiOrigin, spreadsheetId: site.spreadsheetId,
    range: site.gridRange, columns: site.columns,
  }), command.commandCid, bindingCid, wire(target), ...limits(SHEETS_LIMITS.maxRequestBytes)));
  const boundaryCid = target.boundary_cid;
  const current = () => { if (!isCurrent()) fail('SheetsRangeReferenceUnavailable'); };
  const admitTarget = target => {
    current();
    if (!moon.sheetsClearTargetMatches(binding, wire(target))) fail('SheetsRangeReferenceUnavailable');
  };
  const admitRequest = request => {
    current();
    try {
      // The private projection retains the SAME native request and binding;
      // its immutable target was admitted by that original constructor. Do
      // not parse/canonicalize it again on each CID/read/send boundary.
      return ownedSheetsClearRequestCid(request, binding);
    } catch (cause) {
      // Preserve the existing target-first refusal for foreign/copied input.
      // This failed path never upgrades a projection to an original request.
      admitTarget(request.target);
      throw cause;
    }
  };
  return Object.freeze({kinds: ['command'], writeOperation: () => SHEETS_CLEAR_OPERATION,
    prepareRequest({member, value, selector}) {
      if (member.resource !== 'range_target') fail('UndeclaredSheetsResource');
      // Preserve target refusal before value encoding or marker creation.
      // Native matches the original canonical spelling without re-parsing it.
      admitTarget(selector);
      // A marker is generated exactly once for this original request. Restore
      // reads the captured original marker instead of preparing another send.
      const request = prepareSheetsClear({moon, binding, value, target: selector, marker: randomUUID()});
      return {request, requestCid: request.requestCid};
    },
    requestFacts: request => ({value: request.value, target: request.target}),
    requestCid: admitRequest,
    recheckRequests({entries}) { for (const entry of entries) admitRequest(entry.request); },
    recoveryEntry({member, entries}) {
      current();
      return ownedSheetsClearRecoveryEntry(moon, binding, member.effectId,
        entries.map(entry => entry.request));
    },
    recoverRequests({body, durable}) {
      current();
      const handles = sheetsOwnedResult(moon, moon.sheetsClearRecover(binding,
        JSON.stringify(body.effects) ?? 'null', JSON.stringify(durable.connectorRecovery) ?? 'null',
        ...limits(SHEETS_LIMITS.maxResponseBytes)));
      const requests = handles.map(rows => rows.map(handle => {
        current();
        return projectOwnedSheetsClearRequest(moon, binding, handle);
      }));
      return {currents: requests.map(() => undefined), requests};
    },
    async send(options) { admitRequest(options.request); return sendSheetsClear(options); },
    project: options => projectSheetsClear({...options, moon}),
    footprint: () => ({providerNamespace: 'sheets', resourceKind: 'sheet_range', boundaryCid})});
}
