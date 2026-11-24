// Closed public request DATA only. This projector owns no HTTP, secret,
// authorization, Source progress, reservation or physical cleanup capability.
import {types} from 'node:util';
import {exchangeLimits, reservedHttpHeader} from '../host-common/http-exchange.mjs';

type Pair = readonly [name: string, value: string];
type PageSize = Readonly<{parameter: string; limit: number}>;
type VersionHeader = Readonly<{name: string; value: string}>;
export type RestSourceRead = Readonly<{
  method: 'GET'; path: string; query?: readonly Pair[];
  pageSize?: PageSize; versionHeader?: VersionHeader; page?: undefined;
}>;
type RequestInventory = Omit<RestSourceRead, 'method'> & Readonly<{method?: 'GET'}>;
export type RestConstructionUnits = readonly [retainedNodes: bigint, retainedTextBytes: bigint,
  retainedWireBytes: bigint, workspaceNodes: bigint, workspaceTextBytes: bigint, workspaceWireBytes: bigint];

const fail: () => never = () => {throw Object.assign(new Error('InvalidRestSourceRead'), {code: 'InvalidRestSourceRead'});};
const parameter = (value: unknown): value is string => typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_]*$/u.test(value);
const positive = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0 && (value as number) <= 2147483647;
const fields = (value: unknown, required: readonly string[], optional: readonly string[] = []): Record<string, unknown> => {
  if (!value || typeof value !== 'object' || Array.isArray(value) || types.isProxy(value)) fail();
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== null && prototype !== Object.prototype) fail();
  const own = Object.getOwnPropertyDescriptors(value);
  if (required.some(key => !Object.hasOwn(own, key)) || Reflect.ownKeys(own).some(key =>
    typeof key !== 'string' || !required.includes(key) && !optional.includes(key) ||
    !Object.hasOwn(own[key], 'value'))) fail();
  return Object.fromEntries(Object.entries(own).map(([key, entry]) => [key, entry.value]));
};

// The same closed fields are checked by authoring and the installed consumer.
// query/versionHeader contain nonsecret public literals. Credential material
// belongs to the original Host's resolve/sign/send path, never this DATA.
export function captureRestSourceRead(value: unknown, cursorParameter?: unknown): RestSourceRead {
  const read = fields(value, ['method', 'path'], ['query', 'pageSize', 'versionHeader']);
  if (read.method !== 'GET' || typeof read.path !== 'string' || !read.path.isWellFormed() || !read.path.startsWith('/') ||
      read.path.startsWith('//') || /[\\?#\u0000-\u0020\u007f]/u.test(read.path) ||
      /%(?:2f|5c|2e)/iu.test(read.path) ||
      cursorParameter !== undefined && !parameter(cursorParameter)) fail();
  let query: readonly Pair[] | undefined;
  const names = new Set(cursorParameter === undefined ? [] : [cursorParameter]);
  if (read.query !== undefined) {
    if (!Array.isArray(read.query) || types.isProxy(read.query) || read.query.length > exchangeLimits.maxQueryPairs) fail();
    const entries = Object.getOwnPropertyDescriptors(read.query) as Record<string, PropertyDescriptor>, length = entries.length.value as number;
    if (Reflect.ownKeys(entries).length !== length + 1 || Array.from({length}, (_, index) => index)
      .some(index => !Object.hasOwn(entries[index] ?? {}, 'value'))) fail();
    query = Object.freeze(Array.from({length}, (_, index) => {
      const pair = entries[index].value;
      if (!Array.isArray(pair) || types.isProxy(pair) || pair.length !== 2) fail();
      const own = Object.getOwnPropertyDescriptors(pair) as Record<string, PropertyDescriptor>;
      if (Reflect.ownKeys(own).length !== 3 || !Object.hasOwn(own['0'] ?? {}, 'value') ||
          !Object.hasOwn(own['1'] ?? {}, 'value')) fail();
      const name = own['0'].value, value = own['1'].value;
      if (!parameter(name) || names.has(name) || typeof value !== 'string' || !value.isWellFormed() ||
          value.length > exchangeLimits.maxQueryBytes || /[\u0000-\u001f\u007f]/u.test(value)) fail();
      names.add(name);return Object.freeze([name, value] as const);
    }));
  }
  let pageSize: PageSize | undefined, versionHeader: VersionHeader | undefined;
  if (read.pageSize !== undefined) {
    const size = fields(read.pageSize, ['parameter', 'limit']);
    if (!parameter(size.parameter) || names.has(size.parameter) || !positive(size.limit)) fail();
    pageSize = Object.freeze(size as PageSize);
  }
  if (read.versionHeader !== undefined) {
    const header = fields(read.versionHeader, ['name', 'value']);
    // This purpose-specific field cannot replace Authorization, Host, Cookie
    // or transport framing. Header names are already canonical lowercase.
    if (typeof header.name !== 'string' || !/^(?:[a-z0-9]+-)*version$/u.test(header.name) ||
        header.name.length > exchangeLimits.maxHeaderNameBytes || reservedHttpHeader(header.name) ||
        typeof header.value !== 'string' || !/^[\x21-\x7e][\x20-\x7e]*$/u.test(header.value) ||
        header.value.endsWith(' ') || header.value.length > exchangeLimits.maxHeaderValueBytes) fail();
    versionHeader = Object.freeze(header as VersionHeader);
  }
  if ((query?.length ?? 0) + (pageSize === undefined ? 0 : 1) +
      (cursorParameter === undefined ? 0 : 1) > exchangeLimits.maxQueryPairs) fail();
  return Object.freeze({method: read.method, path: read.path,
    ...(query === undefined ? {} : {query}), ...(pageSize === undefined ? {} : {pageSize}),
    ...(versionHeader === undefined ? {} : {versionHeader})});
}

// Cursor/remainingRows come from the SAME existing progress owner. This does
// not advance it or reinterpret empty cursor as EOF. Provider envelopes still
// require their own checked full-page projector before reaching this point.
export function restSourcePageRequest(read: RestSourceRead, cursorParameter: unknown, remainingRows: unknown, cursor?: unknown) {
  if (!positive(remainingRows) || cursor !== undefined &&
      (typeof cursor !== 'string' || !cursor.isWellFormed()) ||
      read.pageSize !== undefined && remainingRows > read.pageSize.limit) fail();
  const query = read.query === undefined ? [] : [...read.query];
  if (read.pageSize !== undefined) query.push([
    read.pageSize.parameter, String(remainingRows)]);
  if (cursor !== undefined) {
    if (!parameter(cursorParameter)) fail();
    query.push([cursorParameter, cursor]);
  }
  return {method: read.method, path: read.path, query,
    headers: [['accept', 'application/json'] as const, ...(read.versionHeader === undefined ? []
      : [[read.versionHeader.name, read.versionHeader.value]] as const)], responseHeaders: [] as string[]};
}

// Domain inventories for the existing Source constructor/Reader quantities.
// These scan the trusted closed declaration, never serialize it, copy it or
// accept a caller budget. Shared Core owns all slot/text tariffs and overflow.
// The snapshot keeps its strings once; each page borrows those SAME originals.
export function restSourceReadConstructionUnits(read: RequestInventory, cursorParameter?: string): RestConstructionUnits {
  const pairs = BigInt(read.query?.length ?? 0);
  const size = read.pageSize === undefined ? 0n : 1n;
  const version = read.versionHeader === undefined ? 0n : 1n;
  const fields = 2n + (read.query === undefined ? 0n : 1n) + size + version;
  let text = BigInt((read.method ?? 'GET').length + read.path.length + (cursorParameter?.length ?? 0));
  for (const [name, value] of read.query ?? []) text += BigInt(name.length + value.length);
  if (size) text += BigInt(read.pageSize!.parameter.length);
  if (version) text += BigInt(read.versionHeader!.name.length + read.versionHeader!.value.length);
  const retained = 1n + fields + (read.query === undefined ? 0n : 1n + 4n * pairs) + 3n * (size + version);
  // fields(): descriptor table+4-field descriptors, own-key array, entries,
  // mapped entries and returned record =5+16n slots. Keep all three calls
  // simultaneously, plus query descriptors/key/index arrays and pair captures,
  // name Set backing and both output vectors. Do not rely on early GC/reuse.
  const captures = 5n + 16n * fields + (size + version) * (5n + 16n * 2n);
  const queryCapture = read.query === undefined ? 0n : 10n + 40n * pairs;
  const nameSet = 5n + 4n * (pairs + size + (cursorParameter === undefined ? 0n : 1n));
  // Descriptor/index enumerations can materialize bounded decimal index keys.
  // Eight complete index-key vectors of at most10 UTF16 units are held here.
  return Object.freeze([retained, 2n * text, 0n,
    retained + captures + queryCapture + nameSet + 1n + fields, 160n * (pairs + 1n), 0n]);
}

export function restSourceRequestConstructionUnits(read: RequestInventory, cursorParameter?: string): RestConstructionUnits {
  const fixed = BigInt(read.query?.length ?? 0);
  const dynamic = (read.pageSize === undefined ? 0n : 1n) + (cursorParameter === undefined ? 0n : 1n);
  const pairs = fixed + dynamic, headers = read.versionHeader === undefined ? 1n : 2n;
  const query = BigInt(exchangeLimits.maxQueryBytes), path = BigInt(read.path.length);
  // Returned five-field request, query+dynamic pairs, header pairs/vectors,
  // response-header vector, then ownHttpRequest's object+owned header copies.
  // Fixed query pairs and header/String DATA are borrowed from the funded
  // Source snapshot; cursor is borrowed from its existing progress owner.
  const retained = 6n + 1n + pairs + 3n * dynamic + 2n * (1n + 4n * headers) + 1n + 4n;
  const retainedText = 2n * (10n + path + 1n + query);
  // requestTarget: both RFC3986 encoding passes, pair strings, joined query
  // and final target overlap with the request. Header validation's names Set,
  // request copies, per-code-point iterators and refusal controls stay live.
  // The query ceiling is the UNCHANGED HTTP owner limit, not a new grant.
  const workspace = retained + (1n + 4n * pairs) + (5n + 4n * headers) + 12n;
  const workspaceText = 2n * (4n * query + 2n * (path + 1n + query) + 10n);
  return Object.freeze([retained, retainedText, 0n, workspace, workspaceText, 0n]);
}
