// Provider handles own request/catalog/recovery meaning. These callbacks only
// transport values between the installed common Effect and Sheets authorities.
import {types as nodeTypes} from 'node:util';
import {canonicalJson as valueJson} from '../../../../packages/sdk/host-port.mjs';
import {canonicalJson as configurationJson} from '../../../host-node/local-account-config.mjs';
import {prepareSheetsUpdate, projectSheetsUpdate, sendSheetsUpdate, SHEETS_UPDATE_OPERATION,
  SHEETS_LIMITS} from '../site/sheets-exchange.mjs';
import {sheetsOwnedResult, projectOwnedSheetsRequest,
  ownedSheetsRequestCid} from '../site/sheets-owned-request.mjs';

type GridOptions = Parameters<typeof import('../site/sheets-grid-pages.mjs').prepareSheetsGridPages>[0];
type Site = Readonly<{apiOrigin: string; spreadsheetId: string; columns: GridOptions['columns']; gridRange: GridOptions['range']}>;
type CodecLimits = readonly [bytes: number, nodes: number, depth: number, cells: number];
type Operation = 'sheets:cells:update' | 'sheets:cells:clear';
type ProfileName = 'sheetsRangeConstructionProfile' | 'sheetsClearConstructionProfile';
type Command = Readonly<{commandCid: string}> & Readonly<Record<string, unknown>>;
export type SheetsCommandDeclaration = Readonly<{
  command: Readonly<{input_schema: Readonly<{cid: string}>; output_schema: Readonly<{cid: string}>}>;
  installed: Command;
  contracts: readonly unknown[];
}>;
type RecoveryEntry = Readonly<{kind: 'sheets-range-request'; wire: string; observationCid: string}>;
type Reference = Readonly<{boundary_cid: string}> & Readonly<Record<string, unknown>>;
type Construction = Readonly<{
  moon: object; binding: unknown; site: Site; command: Command; bindingCid: string; targetWire: string;
  operation: Operation; profileName: ProfileName;
}>;
type CommandRuntime = Parameters<typeof sheetsOwnedResult>[0] & Readonly<{
  sheetsRangeCommandJson(connectorId: string, columns: string, range: string, ...limits: CodecLimits): unknown;
}>;
type CatalogRuntime = Parameters<typeof sheetsOwnedResult>[0] & Readonly<{
  sheetsRangeCatalogJson(catalog: string, command: string, ...limits: CodecLimits): unknown;
}>;
type ReferenceRuntime = Parameters<typeof sheetsOwnedResult>[0] & Readonly<{
  sheetsRangeReferenceJson(origin: string, spreadsheetId: string, sheetId: number, startRow: number,
    endRow: number, startColumn: number, endColumn: number, catalogCid: string, bindingCid: string,
    ...limits: CodecLimits): unknown;
}>;
type Runtime = Parameters<typeof prepareSheetsUpdate>[0]['moon'] &
  Parameters<typeof projectSheetsUpdate>[0]['moon'] & Readonly<{
    sheetsRangeBinding(configuration: string, commandCid: string, bindingCid: string, target: string, ...limits: CodecLimits): unknown;
    sheetsRangeTargetMatches(binding: unknown, target: string): boolean;
    sheetsRangeRecoveryEntryJson(binding: unknown, effectId: string): unknown;
    sheetsRangeRecover(binding: unknown, effects: string, recovery: string, ...limits: CodecLimits): unknown;
  }>;
type UpdateRequest = ReturnType<typeof prepareSheetsUpdate>;
type Member = Readonly<{resource: string; effectId: string}>;
type Entry = Readonly<{request: UpdateRequest}>;
type Recovery = Readonly<{body: Readonly<{effects: unknown}>; durable: Readonly<{connectorRecovery: unknown}>}>;
type DriverOptions = Readonly<{moon: Runtime; site: Site; command: Command; bindingCid: string;
  target: Reference; isCurrent(): boolean}>;

const wire = (value: unknown) => valueJson(value, {dataKeys: true});
const limits = (bytes: number): CodecLimits => [bytes, SHEETS_LIMITS.maxNodes, SHEETS_LIMITS.maxDepth, SHEETS_LIMITS.maxCells];
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };

export function sheetsRangeCommand(connectorId: string, site: Site, moon: CommandRuntime): SheetsCommandDeclaration {
  return Object.freeze(JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsRangeCommandJson(connectorId, JSON.stringify(site.columns),
      JSON.stringify(site.gridRange), ...limits(SHEETS_LIMITS.maxResponseBytes))) as string) as SheetsCommandDeclaration);
}

export function withSheetsRangeCommand(declared: unknown, rangeCommand: SheetsCommandDeclaration, moon: CatalogRuntime) {
  return Object.freeze(JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsRangeCatalogJson(JSON.stringify(declared), JSON.stringify(rangeCommand),
      ...limits(SHEETS_LIMITS.maxResponseBytes))) as string) as Record<string, unknown>);
}

export function sheetsRangeReference({site, catalogCid, bindingCid, moon}:
  Readonly<{site: Pick<Site, 'apiOrigin' | 'spreadsheetId' | 'gridRange'>; catalogCid: string; bindingCid: string; moon: ReferenceRuntime}>): Reference {
  // Preserve the original configuration codec's refusal before the
  // scalar Int ABI can erase negative zero or another invalid JS number.
  const range = JSON.parse(configurationJson(site.gridRange)) as Site['gridRange'];
  return Object.freeze(JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsRangeReferenceJson(site.apiOrigin, site.spreadsheetId,
      range.sheetId, range.startRow, range.endRow, range.startColumn, range.endColumn,
      catalogCid, bindingCid, ...limits(SHEETS_LIMITS.maxRequestBytes))) as string) as Reference);
}

// One fixed implementation descriptor from this SAME installed driver.
// The existing Host composer supplies typed capture/request/HTTP/controls;
// no operation slot, row count, grant or user capacity is invented here.
export function sheetsRangeDriverConstruction({moon, binding, site, command, bindingCid, targetWire, operation, profileName}: Construction) {
  const profile = Object.getOwnPropertyDescriptor(moon, profileName);
  const original = profile && Object.hasOwn(profile,'value') ? profile.value : undefined;
  const captureName = profileName === 'sheetsRangeConstructionProfile'
    ? 'sheetsRangeCaptureConstructionProfile' : 'sheetsClearCaptureConstructionProfile';
  const captureField = Object.getOwnPropertyDescriptor(moon,captureName);
  const captureOriginal = captureField && Object.hasOwn(captureField,'value') ? captureField.value : undefined;
  const provider = Object.freeze({installedStandardCreateConstructionProfile(inputBytes: number,inputNodes: number,inputDepth: number) {
    if (typeof original !== 'function' || nodeTypes.isProxy(original) || nodeTypes.isAsyncFunction(original)) {
      fail('InstalledStandardCreateRuntimeUnavailable');
    }
    return Reflect.apply(original, moon, [binding,inputBytes,inputNodes,inputDepth,
      SHEETS_LIMITS.maxResponseBytes,SHEETS_LIMITS.maxNodes,SHEETS_LIMITS.maxDepth]);
  },installedStandardDriverCaptureConstructionCapacity(captureBytes: number,captureNodes: number,captureDepth: number,
    inputBytes: number,inputNodes: number,inputDepth: number) {
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
export function sheetsRangeConfiguration(site: Site) {
  return {origin:site.apiOrigin,spreadsheetId:site.spreadsheetId,range:site.gridRange,columns:site.columns};
}
export function sheetsRangeConfigurationBytes(site: Site) {
  const range={sheetId:2147483647,startRow:2147483647,endRow:2147483647,startColumn:2147483647,endColumn:2147483647};
  let bytes=Buffer.byteLength(JSON.stringify(sheetsRangeConfiguration({apiOrigin:'',spreadsheetId:'',gridRange:range,columns:[]})));
  bytes+=6*(site.apiOrigin.length+site.spreadsheetId.length);
  for(const column of site.columns)bytes+=1+Buffer.byteLength(JSON.stringify({name:'',type:column.type,nullable:column.nullable}))+6*column.name.length;
  if(!Number.isSafeInteger(bytes)||bytes<1||bytes>2147483647)fail('InstalledSheetsConstructionUnavailable');
  return bytes;
}

export function createSheetsRangeDriver({moon, site, command, bindingCid, target, isCurrent}: DriverOptions) {
  const configurationWire = JSON.stringify(sheetsRangeConfiguration(site));
  const targetWire = wire(target);
  const binding = sheetsOwnedResult(moon, moon.sheetsRangeBinding(configurationWire,
    command.commandCid, bindingCid, targetWire, ...limits(SHEETS_LIMITS.maxRequestBytes)));
  const managed = sheetsRangeDriverConstruction({moon,binding,site,command,bindingCid,targetWire,
    operation:SHEETS_UPDATE_OPERATION,profileName:'sheetsRangeConstructionProfile'});
  const boundaryCid = target.boundary_cid;
  const current = () => { if (!isCurrent()) fail('SheetsRangeReferenceUnavailable'); };
  const admitTarget = (target: unknown) => {
    current();
    if (!moon.sheetsRangeTargetMatches(binding, wire(target))) fail('SheetsRangeReferenceUnavailable');
  };
  const admitRequest = (request: UpdateRequest) => {
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
    prepareRequest({member, value, selector}: Readonly<{member: Member; value: unknown; selector: unknown}>) {
      if (member.resource !== 'range_target') fail('UndeclaredSheetsResource');
      // Preserve target refusal before value encoding or marker creation.
      // Native matches the original canonical spelling without re-parsing it.
      admitTarget(selector);
      const request = prepareSheetsUpdate({moon, binding, value, target: selector});
      return {request, requestCid: request.requestCid};
    },
    requestFacts: (request: UpdateRequest) => ({value: request.value, target: request.target}),
    requestCid: admitRequest,
    recheckRequests({entries}: Readonly<{entries: readonly Entry[]}>) { for (const entry of entries) admitRequest(entry.request); },
    recoveryEntry({member}: Readonly<{member: Member}>) {
      return JSON.parse(sheetsOwnedResult(moon,
        moon.sheetsRangeRecoveryEntryJson(binding, member.effectId)) as string) as RecoveryEntry;
    },
    recoverRequests({body, durable}: Recovery) {
      const handles = sheetsOwnedResult(moon, moon.sheetsRangeRecover(binding,
        JSON.stringify(body.effects) ?? 'null', JSON.stringify(durable.connectorRecovery) ?? 'null',
        ...limits(SHEETS_LIMITS.maxResponseBytes))) as readonly (readonly unknown[])[];
      const requests = handles.map(rows => rows.map(handle => {
        current();
        return projectOwnedSheetsRequest(moon, binding, handle);
      }));
      return {currents: requests.map(() => undefined), requests};
    },
    async send(options: Parameters<typeof sendSheetsUpdate>[0]) { admitRequest(options.request); return sendSheetsUpdate(options); },
    project: (options: Omit<Parameters<typeof projectSheetsUpdate>[0], 'moon'>) => projectSheetsUpdate({...options, moon}),
    footprint: () => ({providerNamespace: 'sheets', resourceKind: 'sheet_range',
      boundaryCid})});
}
