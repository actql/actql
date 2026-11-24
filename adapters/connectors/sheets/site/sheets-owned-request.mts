// Language lifetime only: immutable physical projections retain their original
// provider handle privately. No handle is serialized or rebuilt from a DTO.
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
type ResultRuntime = Readonly<{sheetsRangeFailureJson(cause: unknown): string}>;
type Runtime = ResultRuntime & Readonly<{
  sheetsRangeRequestJson(binding: unknown, handle: unknown): unknown;
  sheetsRangeRequestBody(binding: unknown, handle: unknown): unknown;
  sheetsRangePrepare(binding: unknown, value: string, target: string): unknown;
  sheetsRangeRequestCid(binding: unknown, handle: unknown): unknown;
}>;
type RequestFacts = Readonly<{
  origin: string; path: string; spreadsheetId: string; sheetId: number;
  acknowledgedRows: number; requestCid: string; value: unknown; target: unknown;
}>;
type Original = Readonly<{moon: Runtime; binding: unknown; handle: unknown}>;

const originals = new WeakMap<object, Original>();
const wire = (value: unknown) => canonicalJson(value, {dataKeys: true});
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };

export function sheetsOwnedResult(moon: ResultRuntime, result: unknown) {
  try { return checked(result); }
  catch (failure) {
    if ((failure as {code?: unknown} | null | undefined)?.code !== 'MoonBitHostFailure') throw failure;
    const projected = JSON.parse(moon.sheetsRangeFailureJson((failure as Error).cause)) as
      {code: string; refused: unknown};
    throw Object.assign(new Error(projected.code, {cause: projected.refused}), {code: projected.code});
  }
}

const freeze = <T,>(value: T): T => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};

export function projectOwnedSheetsRequest(moon: Runtime, binding: unknown, handle: unknown) {
  const facts = JSON.parse(sheetsOwnedResult(moon,
    moon.sheetsRangeRequestJson(binding, handle)) as string) as RequestFacts;
  // Borrow the exact body separately: wrapping it in another JSON string would
  // duplicate/escape a request-sized payload and narrow the original limit.
  const body = sheetsOwnedResult(moon, moon.sheetsRangeRequestBody(binding, handle)) as string;
  const request = freeze({...facts, body});
  originals.set(request, Object.freeze({moon, binding, handle}));
  return request;
}

export function prepareOwnedSheetsRequest(moon: Runtime, binding: unknown, value: unknown, target: unknown) {
  const handle = sheetsOwnedResult(moon,
    moon.sheetsRangePrepare(binding, wire(value), wire(target)));
  return projectOwnedSheetsRequest(moon, binding, handle);
}

export function ownedSheetsRequestCid(request: object, binding?: unknown) {
  const original = originals.get(request);
  if (original === undefined) fail('ForeignSheetsRangeRequest');
  const {moon, handle} = original;
  // The connector, not JS record equality, admits the original nominal owner.
  return sheetsOwnedResult(moon,
    moon.sheetsRangeRequestCid(binding ?? original.binding, handle)) as string;
}
