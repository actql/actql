// Language lifetime only. The existing provider owns every nominal request;
// neither an equal projection nor a saved marker is an approval or a grant.
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {sheetsOwnedResult} from './sheets-owned-request.mjs';

type Runtime = Parameters<typeof sheetsOwnedResult>[0] & Readonly<{
  sheetsClearRequestCid(binding: unknown, handle: unknown): unknown;
  sheetsClearRequestJson(binding: unknown, handle: unknown): unknown;
  sheetsClearRequestBody(binding: unknown, handle: unknown): unknown;
  sheetsClearPrepare(binding: unknown, value: string, target: string, marker: string): unknown;
  sheetsClearOutcomeJson(binding: unknown, handle: unknown, status: number, body: Buffer): unknown;
  sheetsClearRecoveryEntryJson(binding: unknown, effectId: string, handles: readonly unknown[]): unknown;
}>;
type RequestFacts = Readonly<{
  origin: string; path: string; spreadsheetId: string; sheetId: number;
  clearedRows: number; requestCid: string; marker: string; value: unknown; target: unknown;
}>;
type Original = Readonly<{moon: Runtime; binding: unknown; handle: unknown}>;

const originals = new WeakMap<object, Original>();
const wire = (value: unknown) => canonicalJson(value, {dataKeys: true});
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const freeze = <T,>(value: T): T => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};
const originalOf = (request: object, binding?: unknown, moon?: Runtime) => {
  const original = originals.get(request);
  if (original === undefined || (moon !== undefined && moon !== original.moon)) {
    fail('ForeignSheetsClearRequest');
  }
  sheetsOwnedResult(original.moon, original.moon.sheetsClearRequestCid(
    binding ?? original.binding, original.handle));
  return original;
};

export function projectOwnedSheetsClearRequest(moon: Runtime, binding: unknown, handle: unknown) {
  const facts = JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsClearRequestJson(binding, handle)) as string) as RequestFacts;
  const body = sheetsOwnedResult(moon, moon.sheetsClearRequestBody(binding, handle)) as string;
  const request = freeze({...facts, body});
  originals.set(request, Object.freeze({moon, binding, handle}));
  return request;
}

export function prepareOwnedSheetsClearRequest(moon: Runtime, binding: unknown, value: unknown, target: unknown, marker: string) {
  const handle = sheetsOwnedResult(moon,
    moon.sheetsClearPrepare(binding, wire(value), wire(target), marker));
  return projectOwnedSheetsClearRequest(moon, binding, handle);
}

export function ownedSheetsClearRequestCid(request: object, binding?: unknown) {
  const original = originalOf(request, binding);
  return sheetsOwnedResult(original.moon, original.moon.sheetsClearRequestCid(
    binding ?? original.binding, original.handle)) as string;
}

export function ownedSheetsClearOutcome(moon: Runtime, request: object, status: number, body: Buffer) {
  const original = originalOf(request, undefined, moon);
  return JSON.parse(sheetsOwnedResult(moon, moon.sheetsClearOutcomeJson(
    original.binding, original.handle, status, body)) as string) as {outcome: string};
}

export function ownedSheetsClearRecoveryEntry(moon: Runtime, binding: unknown, effectId: string, requests: readonly object[]) {
  const handles = requests.map(request => originalOf(request, binding, moon).handle);
  return JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsClearRecoveryEntryJson(binding, effectId, handles)) as string) as unknown;
}
