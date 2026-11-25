// The portable provider retains original requests; the installed Effect owner
// retains approval, durable claims, current installation and cleanup custody.
import {randomUUID} from 'node:crypto';
import {sheetsRangeDriverConstruction,sheetsRangeConfiguration, type SheetsCommandDeclaration} from './sheets-range-command.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {prepareSheetsClear, projectSheetsClear, sendSheetsClear,
  SHEETS_CLEAR_OPERATION, SHEETS_LIMITS} from '../site/sheets-exchange.mjs';
import {sheetsOwnedResult} from '../site/sheets-owned-request.mjs';
import {projectOwnedSheetsClearRequest, ownedSheetsClearRequestCid,
  ownedSheetsClearRecoveryEntry} from '../site/sheets-clear-request.mjs';

type Site = Parameters<typeof sheetsRangeConfiguration>[0];
type Driver = Parameters<typeof sheetsRangeDriverConstruction>[0];
type CodecLimits = readonly [bytes: number, nodes: number, depth: number, cells: number];
type CommandRuntime = Parameters<typeof sheetsOwnedResult>[0] & Readonly<{
  sheetsClearCommandJson(connectorId: string, columns: string, range: string, ...limits: CodecLimits): unknown;
}>;
type Runtime = Parameters<typeof prepareSheetsClear>[0]['moon'] & Readonly<{
  sheetsClearBinding(configuration: string, commandCid: string, bindingCid: string, target: string, ...limits: CodecLimits): unknown;
  sheetsClearTargetMatches(binding: unknown, target: string): boolean;
  sheetsClearRecover(binding: unknown, effects: string, recovery: string, ...limits: CodecLimits): unknown;
}>;
type ClearRequest = ReturnType<typeof prepareSheetsClear>;
type Entry = Readonly<{request: ClearRequest}>;
type Member = Readonly<{resource: string; effectId: string}>;
type Recovery = Readonly<{body: Readonly<{effects: unknown}>; durable: Readonly<{connectorRecovery: unknown}>}>;
type DriverOptions = Readonly<{moon: Runtime; site: Site; command: Driver['command']; bindingCid: string;
  target: Readonly<{boundary_cid: string}>; isCurrent(): boolean}>;

const wire = (value: unknown) => canonicalJson(value, {dataKeys: true});
const limits = (bytes: number): CodecLimits => [bytes, SHEETS_LIMITS.maxNodes, SHEETS_LIMITS.maxDepth, SHEETS_LIMITS.maxCells];
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };

export function sheetsClearCommand(connectorId: string, site: Site, moon: CommandRuntime): SheetsCommandDeclaration {
  return Object.freeze(JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsClearCommandJson(connectorId, JSON.stringify(site.columns),
      JSON.stringify(site.gridRange), ...limits(SHEETS_LIMITS.maxResponseBytes))) as string) as SheetsCommandDeclaration);
}

export function createSheetsClearDriver({moon, site, command, bindingCid, target, isCurrent}: DriverOptions) {
  const configurationWire = JSON.stringify(sheetsRangeConfiguration(site));
  const targetWire = wire(target);
  const binding = sheetsOwnedResult(moon, moon.sheetsClearBinding(configurationWire,
    command.commandCid, bindingCid, targetWire, ...limits(SHEETS_LIMITS.maxRequestBytes)));
  const managed = sheetsRangeDriverConstruction({moon,binding,site,command,bindingCid,targetWire,
    operation:SHEETS_CLEAR_OPERATION,profileName:'sheetsClearConstructionProfile'});
  const boundaryCid = target.boundary_cid;
  const current = () => { if (!isCurrent()) fail('SheetsRangeReferenceUnavailable'); };
  const admitTarget = (target: unknown) => {
    current();
    if (!moon.sheetsClearTargetMatches(binding, wire(target))) fail('SheetsRangeReferenceUnavailable');
  };
  const admitRequest = (request: ClearRequest) => {
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
  return Object.freeze({...managed,kinds: Object.freeze(['command']), writeOperation: () => SHEETS_CLEAR_OPERATION,
    prepareRequest({member, value, selector}: Readonly<{member: Member; value: unknown; selector: unknown}>) {
      if (member.resource !== 'range_target') fail('UndeclaredSheetsResource');
      // Preserve target refusal before value encoding or marker creation.
      // Native matches the original canonical spelling without re-parsing it.
      admitTarget(selector);
      // A marker is generated exactly once for this original request. Restore
      // reads the captured original marker instead of preparing another send.
      const request = prepareSheetsClear({moon, binding, value, target: selector, marker: randomUUID()});
      return {request, requestCid: request.requestCid};
    },
    requestFacts: (request: ClearRequest) => ({value: request.value, target: request.target}),
    requestCid: admitRequest,
    recheckRequests({entries}: Readonly<{entries: readonly Entry[]}>) { for (const entry of entries) admitRequest(entry.request); },
    recoveryEntry({member, entries}: Readonly<{member: Member; entries: readonly Entry[]}>) {
      current();
      return ownedSheetsClearRecoveryEntry(moon, binding, member.effectId,
        entries.map(entry => entry.request));
    },
    recoverRequests({body, durable}: Recovery) {
      current();
      const handles = sheetsOwnedResult(moon, moon.sheetsClearRecover(binding,
        JSON.stringify(body.effects) ?? 'null', JSON.stringify(durable.connectorRecovery) ?? 'null',
        ...limits(SHEETS_LIMITS.maxResponseBytes))) as readonly (readonly unknown[])[];
      const requests = handles.map(rows => rows.map(handle => {
        current();
        return projectOwnedSheetsClearRequest(moon, binding, handle);
      }));
      return {currents: requests.map(() => undefined), requests};
    },
    async send(options: Parameters<typeof sendSheetsClear>[0]) { admitRequest(options.request); return sendSheetsClear(options); },
    project: (options: Omit<Parameters<typeof projectSheetsClear>[0], 'moon'>) => projectSheetsClear({...options, moon}),
    footprint: () => ({providerNamespace: 'sheets', resourceKind: 'sheet_range', boundaryCid})});
}
