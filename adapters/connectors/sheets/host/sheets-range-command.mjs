// Provider handles own request/catalog/recovery meaning. These callbacks only
// transport values between the installed common Effect and Sheets authorities.
import {canonicalJson as valueJson} from '../../../../packages/sdk/host-port.mjs';
import {prepareSheetsUpdate, projectSheetsUpdate, sendSheetsUpdate, SHEETS_UPDATE_OPERATION,
  SHEETS_LIMITS} from '../site/sheets-exchange.mjs';
import {sheetsOwnedResult, projectOwnedSheetsRequest,
  ownedSheetsRequestCid} from '../site/sheets-owned-request.mjs';

const wire = value => valueJson(value, {dataKeys: true});
const limits = bytes => [bytes, SHEETS_LIMITS.maxNodes, SHEETS_LIMITS.maxDepth, SHEETS_LIMITS.maxCells];
const fail = code => { throw Object.assign(new Error(code), {code}); };

export function sheetsRangeCommand(connectorId, site, moon) {
  return Object.freeze(JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsRangeCommandJson(connectorId, JSON.stringify(site.columns),
      site.gridRange.endRow - site.gridRange.startRow, ...limits(SHEETS_LIMITS.maxResponseBytes)))));
}

export function withSheetsRangeCommand(declared, rangeCommand, moon) {
  return Object.freeze(JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsRangeCatalogJson(JSON.stringify(declared), JSON.stringify(rangeCommand),
      ...limits(SHEETS_LIMITS.maxResponseBytes)))));
}

export function sheetsRangeReference({site, catalogCid, bindingCid, moon}) {
  const range = site.gridRange;
  return Object.freeze(JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsRangeReferenceJson(site.apiOrigin, site.spreadsheetId,
      range.sheetId, range.startRow, range.endRow, range.startColumn, range.endColumn,
      catalogCid, bindingCid, ...limits(SHEETS_LIMITS.maxRequestBytes)))));
}

export function createSheetsRangeDriver({moon, site, command, bindingCid, target, isCurrent}) {
  const binding = sheetsOwnedResult(moon, moon.sheetsRangeBinding(JSON.stringify({
    origin: site.apiOrigin, spreadsheetId: site.spreadsheetId,
    range: site.gridRange, columns: site.columns,
  }), command.commandCid, bindingCid, wire(target), ...limits(SHEETS_LIMITS.maxRequestBytes)));
  const current = () => { if (!isCurrent()) fail('SheetsRangeReferenceUnavailable'); };
  const admitRequest = request => { current(); return ownedSheetsRequestCid(request, binding); };
  return Object.freeze({kinds: ['command'], writeOperation: () => SHEETS_UPDATE_OPERATION,
    prepareRequest({member, value, selector}) {
      if (member.resource !== 'range_target') fail('UndeclaredSheetsResource');
      current();
      const request = prepareSheetsUpdate({moon, binding, value, target: selector});
      return {request, requestCid: request.requestCid};
    },
    requestFacts: request => ({value: request.value, target: request.target}),
    requestCid: admitRequest,
    recheckRequests({entries}) { for (const entry of entries) admitRequest(entry.request); },
    recoveryEntry({member}) {
      return JSON.parse(sheetsOwnedResult(moon,
        moon.sheetsRangeRecoveryEntryJson(binding, member.effectId)));
    },
    recoverRequests({body, durable}) {
      current();
      const handles = sheetsOwnedResult(moon, moon.sheetsRangeRecover(binding,
        JSON.stringify(body.effects) ?? 'null', JSON.stringify(durable.connectorRecovery) ?? 'null',
        ...limits(SHEETS_LIMITS.maxResponseBytes)));
      const requests = handles.map(rows => rows.map(handle => projectOwnedSheetsRequest(moon, binding, handle)));
      return {currents: requests.map(() => undefined), requests};
    },
    async send(options) { admitRequest(options.request); return sendSheetsUpdate(options); },
    project: options => projectSheetsUpdate({...options, moon}),
    footprint: () => ({providerNamespace: 'sheets', resourceKind: 'sheet_range',
      boundaryCid: target.boundary_cid})});
}
