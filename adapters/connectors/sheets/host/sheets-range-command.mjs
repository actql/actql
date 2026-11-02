// Provider handles own request/catalog/recovery meaning. These callbacks only
// transport values between the installed common Effect and Sheets authorities.
import {types as nodeTypes} from 'node:util';
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

// One fixed implementation descriptor from this SAME installed driver.
// The existing Host composer supplies typed capture/request/HTTP/controls;
// no operation slot, row count, grant or user capacity is invented here.
export function sheetsRangeDriverConstruction({moon, binding, site, command, bindingCid, targetWire, operation, profileName}) {
  const profile = Object.getOwnPropertyDescriptor(moon, profileName);
  const original = profile && Object.hasOwn(profile,'value') ? profile.value : undefined;
  const captureName = profileName === 'sheetsRangeConstructionProfile'
    ? 'sheetsRangeCaptureConstructionProfile' : 'sheetsClearCaptureConstructionProfile';
  const captureField = Object.getOwnPropertyDescriptor(moon,captureName);
  const captureOriginal = captureField && Object.hasOwn(captureField,'value') ? captureField.value : undefined;
  const provider = Object.freeze({installedStandardCreateConstructionProfile(inputBytes,inputNodes,inputDepth) {
    if (typeof original !== 'function' || nodeTypes.isProxy(original) || nodeTypes.isAsyncFunction(original)) {
      fail('InstalledStandardCreateRuntimeUnavailable');
    }
    return Reflect.apply(original, moon, [binding,inputBytes,inputNodes,inputDepth,
      SHEETS_LIMITS.maxResponseBytes,SHEETS_LIMITS.maxNodes,SHEETS_LIMITS.maxDepth]);
  },installedStandardDriverCaptureConstructionCapacity(captureBytes,captureNodes,captureDepth,inputBytes,inputNodes,inputDepth) {
    if (typeof captureOriginal !== 'function' || nodeTypes.isProxy(captureOriginal) || nodeTypes.isAsyncFunction(captureOriginal)) {
      fail('InstalledStandardCreateRuntimeUnavailable');
    }
    // SAME limits as recoverRequests below; the binding instead bounds
    // outgoing requests and cannot stand in for the cold input decoder.
    return Reflect.apply(captureOriginal,moon,[binding,captureBytes,captureNodes,captureDepth,inputBytes,inputNodes,inputDepth,
      SHEETS_LIMITS.maxResponseBytes,SHEETS_LIMITS.maxNodes,SHEETS_LIMITS.maxDepth]);
  }});
  const definition = Object.freeze({kind:'command',memberOperations:Object.freeze([]),
    rowOperations:Object.freeze([Object.freeze({role:'write',operation})])});
  const metadataTextUnits = [site.apiOrigin,site.spreadsheetId,command.commandCid,bindingCid,targetWire,
    operation,'sheets','sheet_range','/v4/spreadsheets/',':batchUpdate'].reduce((sum,value)=>sum+value.length,0);
  const construction = Object.freeze({write:Object.freeze({operation,
    maxRequestBytes:SHEETS_LIMITS.maxRequestBytes,maxResponseBytes:SHEETS_LIMITS.maxResponseBytes}),
    check:undefined,metadataTextUnits});
  return Object.freeze({managedPlanDefinition:definition,managedPlanConstruction:construction,managedPlanProvider:provider});
}

// Bound the exact configuration constructor without serializing proportional
// names before the Source parent reserves. Fixed templates use the same
// configuration shape; variable original UTF16 units need at most six bytes.
export function sheetsRangeConfiguration(site) {
  return {origin:site.apiOrigin,spreadsheetId:site.spreadsheetId,range:site.gridRange,columns:site.columns};
}
export function sheetsRangeConfigurationBytes(site) {
  const range={sheetId:2147483647,startRow:2147483647,endRow:2147483647,startColumn:2147483647,endColumn:2147483647};
  let bytes=Buffer.byteLength(JSON.stringify(sheetsRangeConfiguration({apiOrigin:'',spreadsheetId:'',gridRange:range,columns:[]})));
  bytes+=6*(site.apiOrigin.length+site.spreadsheetId.length);
  for(const column of site.columns)bytes+=1+Buffer.byteLength(JSON.stringify({name:'',type:column.type,nullable:column.nullable}))+6*column.name.length;
  if(!Number.isSafeInteger(bytes)||bytes<1||bytes>2147483647)fail('InstalledSheetsConstructionUnavailable');
  return bytes;
}

export function createSheetsRangeDriver({moon, site, command, bindingCid, target, isCurrent}) {
  const configurationWire = JSON.stringify(sheetsRangeConfiguration(site));
  const targetWire = wire(target);
  const binding = sheetsOwnedResult(moon, moon.sheetsRangeBinding(configurationWire,
    command.commandCid, bindingCid, targetWire, ...limits(SHEETS_LIMITS.maxRequestBytes)));
  const managed = sheetsRangeDriverConstruction({moon,binding,site,command,bindingCid,targetWire,
    operation:SHEETS_UPDATE_OPERATION,profileName:'sheetsRangeConstructionProfile'});
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
  return Object.freeze({...managed,kinds: Object.freeze(['command']), writeOperation: () => SHEETS_UPDATE_OPERATION,
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
