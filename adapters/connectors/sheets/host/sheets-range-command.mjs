// Provider handles own request/catalog/recovery meaning. These callbacks only
// transport values between the installed common Effect and Sheets authorities.
import {canonicalJson as valueJson} from '../../../../packages/sdk/host-port.mjs';
import {canonicalJson as configurationJson} from '../../../host-node/local-account-config.mjs';
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
      JSON.stringify(site.gridRange), ...limits(SHEETS_LIMITS.maxResponseBytes)))));
}

export function withSheetsRangeCommand(declared, rangeCommand, moon) {
  return Object.freeze(JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsRangeCatalogJson(JSON.stringify(declared), JSON.stringify(rangeCommand),
      ...limits(SHEETS_LIMITS.maxResponseBytes)))));
}

export function sheetsRangeReference({site, catalogCid, bindingCid, moon}) {
  // Preserve the original configuration codec's refusal before the
  // scalar Int ABI can erase negative zero or another invalid JS number.
  const range = JSON.parse(configurationJson(site.gridRange));
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
  const boundaryCid = target.boundary_cid;
  const current = () => { if (!isCurrent()) fail('SheetsRangeReferenceUnavailable'); };
  const admitTarget = target => {
    current();
    if (!moon.sheetsRangeTargetMatches(binding, wire(target))) fail('SheetsRangeReferenceUnavailable');
  };
  const admitRequest = request => {
    current();
    try {
      // The private projection retains the SAME native request and binding;
      // its immutable target was admitted by that original constructor. Do
      // not parse/canonicalize it again on each CID/read/send boundary.
      return ownedSheetsRequestCid(request, binding);
    } catch (cause) {
      // Preserve the existing target-first refusal for foreign/copied input.
      // This failed path never upgrades a projection to an original request.
      admitTarget(request.target);
      throw cause;
    }
  };
  return Object.freeze({kinds: ['command'], writeOperation: () => SHEETS_UPDATE_OPERATION,
    prepareRequest({member, value, selector}) {
      if (member.resource !== 'range_target') fail('UndeclaredSheetsResource');
      // Preserve target refusal before value encoding or marker creation.
      // Native matches the original canonical spelling without re-parsing it.
      admitTarget(selector);
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
      const handles = sheetsOwnedResult(moon, moon.sheetsRangeRecover(binding,
        JSON.stringify(body.effects) ?? 'null', JSON.stringify(durable.connectorRecovery) ?? 'null',
        ...limits(SHEETS_LIMITS.maxResponseBytes)));
      const requests = handles.map(rows => rows.map(handle => {
        current();
        return projectOwnedSheetsRequest(moon, binding, handle);
      }));
      return {currents: requests.map(() => undefined), requests};
    },
    async send(options) { admitRequest(options.request); return sendSheetsUpdate(options); },
    project: options => projectSheetsUpdate({...options, moon}),
    footprint: () => ({providerNamespace: 'sheets', resourceKind: 'sheet_range',
      boundaryCid})});
}
