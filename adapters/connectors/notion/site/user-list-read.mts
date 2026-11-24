// Notion request and checked page meaning only. The shared Host reader owns
// authentication, accounting, current checks, cancellation and physical cleanup.
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField, runtimeIsError} from '../../../host-common/compiler-binding.generated.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';
import {captureRestSourceRead, restSourcePageRequest} from '../../../host-node/rest-source-request.mjs';
import type {RestSourceRead} from '../../../host-node/rest-source-request.mjs';
import type {RestReadOriginal} from '../../../host-node/rest-read-original.mjs';
import userListRequest from '../../../../src/connectors/notion/user-list-request.json' with {type: 'json'};

// Immutable provider-authored DATA. Production captures its request snapshot
// under the original Source initializer; importing this asset issues no grant.
Object.freeze(userListRequest.read.pageSize);
Object.freeze(userListRequest.read.versionHeader);
Object.freeze(userListRequest.read);
Object.freeze(userListRequest.pagination.items);
Object.freeze(userListRequest.pagination.next);
Object.freeze(userListRequest.pagination);
export const NOTION_USER_LIST_REQUEST = Object.freeze(userListRequest);
const cursorParameter = userListRequest.pagination.parameter;

export const NOTION_USER_LIST_OPERATION = 'notion:users:list';
// Reviewed vendor request version, not an ActQL identity/version authority.
export const NOTION_USER_LIST_API_VERSION = userListRequest.read.versionHeader.value;
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const providerExports = ['notionProjectUserList','notionUserListRowsWire','notionUserListMetadata',
  'notionUserListColumnNames','notionUserListPrepareIdentityProgress','notionUserListTrackPageIdentities'] as const;
const cursorMethods = ['clientProgramRowSourcePrepareCursorProgress', 'clientProgramRowSourceCursorRemainingRows',
  'clientProgramRowSourceCursorHasNext', 'clientProgramRowSourceCursorNext',
  'clientProgramRowSourceAdvanceProviderPageCursor', 'clientProgramRowSourceCursorIssueCode'] as const;
const cursorCodes = Object.freeze({
  RestSourcePageLimit: 'NotionUserListPageLimit',
  RestSourceRowLimit: 'NotionUserListRowLimit',
  RestSourceCursorCycle: 'NotionUserListRepeatedCursor',
});

function cursorResult(result: unknown, common: unknown, issueCode: (issue: unknown) => unknown) {
  if (runtimeIsError(result)) {
    const cause = runtimeField(result, 0);
    const selected = Reflect.apply(issueCode, common, [cause]);
    const code = Object.hasOwn(cursorCodes, selected as PropertyKey) ? cursorCodes[selected as keyof typeof cursorCodes] : selected;
    if (typeof code !== 'string' || code.length === 0) fail('NotionUserListCursorRuntimeMismatch');
    throw Object.assign(new Error(code, {cause}), {code});
  }
  return checked(result);
}

const limitFields = ['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth',
  'maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes',
  'maxTargetBytes','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'] as const;

export type NotionPageLimits = Readonly<Record<typeof limitFields[number], number>>;
export type NotionUserListBindings = Readonly<{
  notionProjectUserList(body: ArrayBufferView, maxBytes: number, maxNodes: number, maxDepth: number,
    maxRows: number, maxCursorBytes: number, maxIdentityBytes: number, maxValueNodes: number, maxValueTextBytes: number): unknown;
  notionUserListRowsWire(page: unknown, columns: readonly string[], maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  notionUserListMetadata(page: unknown, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  notionUserListColumnNames(): string[];
  notionUserListPrepareIdentityProgress(maxRows: number): unknown;
  notionUserListTrackPageIdentities(progress: unknown, page: unknown): unknown;
}>;

// The cursor and provider results remain opaque until the existing checked
// admission. Each method is called on the original namespace.
export type NotionCursorBindings = Readonly<{
  clientProgramRowSourcePrepareCursorProgress(maxPages: number, maxRows: number, pageSize: number, maxCursorBytes: number): unknown;
  clientProgramRowSourceCursorRemainingRows(progress: unknown, pageIndex: number, rowCount: number): unknown;
  clientProgramRowSourceCursorHasNext(progress: unknown): boolean;
  clientProgramRowSourceCursorNext(progress: unknown): unknown;
  clientProgramRowSourceAdvanceProviderPageCursor(progress: unknown, pageIndex: number, rowCount: number,
    pageRows: number, cursorPresent: boolean, cursor: string): unknown;
  clientProgramRowSourceCursorIssueCode(issue: unknown): string;
}>;
export type NotionSynchronousProjection = <Result>(method: (...args: never[]) => Result, receiver: unknown,
  args: readonly unknown[]) => Result;
type CursorPorts<Names extends readonly (keyof NotionCursorBindings)[]> =
  {[Index in keyof Names]: NotionCursorBindings[Names[Index]]};
type Inputs = Readonly<{moon: Partial<NotionUserListBindings> | undefined;
  common: Partial<NotionCursorBindings> | undefined; names: readonly string[]; limits: NotionPageLimits;
  request?: RestReadOriginal | RestSourceRead}>;
type Frame = Readonly<{pageIndex: number; rowCount: number}>;
type Response = Readonly<{accepted: boolean; statusCode: number; body: ArrayBufferView}>;

export class NotionUserListReadFailure extends Error {
  declare readonly code: 'NotionUserListReadFailed';

  constructor(cause: unknown) {
    super('NotionUserListReadFailed', {cause});
    this.code = 'NotionUserListReadFailed';
  }
}

export function prepareNotionUserListPages({moon, common, names, limits, request: capturedRequest}: Inputs,
  applySynchronousProjection: NotionSynchronousProjection) {
  if (!Array.isArray(names) || !limits || typeof limits !== 'object') fail('InvalidNotionUserListRead');
  if (typeof applySynchronousProjection !== 'function') fail('InvalidNotionUserListRead');
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name => {
    const original = moon?.[name];
    if (typeof original !== 'function') fail('InvalidNotionUserListRead');
    return [name, (...args: unknown[]) => applySynchronousProjection(original, moon, args)];
  }))) as NotionUserListBindings;
  const bound = Object.freeze({...limits});
  const request = capturedRequest ?? captureRestSourceRead(userListRequest.read, cursorParameter);
  const declaredPageSize = typeof request.page === 'function' ? request.pageSize : request.pageSize!.limit;
  if (!limitFields.every(name => positive(bound[name])) || bound.pageSize > declaredPageSize!) fail('InvalidNotionUserListRead');
  const columns = Object.freeze(provider.notionUserListColumnNames().slice());
  if (names.length > columns.length || new Set(names).size !== names.length ||
      names.some(name => !columns.includes(name))) fail('InvalidNotionUserListRead');
  // The fixed inventory produces one checked method at each original index.
  const [prepareCursor, remainingRows, hasNextCursor, nextCursor, advanceCursor, issueCode] =
    cursorMethods.map(name => {
      const original = common?.[name];
      if (typeof original !== 'function') fail('NotionUserListCursorRuntimeUnavailable');
      return original;
    }) as unknown as CursorPorts<typeof cursorMethods>;
  // Request page size and response row admission are independent. The codec
  // retains its original smaller response limit when maxRows < pageSize.
  const progress = cursorResult(Reflect.apply(prepareCursor, common,
    [bound.maxPages, bound.maxTotalRows, bound.pageSize, bound.maxCursorBytes]), common, issueCode);
  // Source capture keeps the complete declared row before the user's SELECT.
  const selected = Object.freeze(columns.slice());
  const identities = checked(provider.notionUserListPrepareIdentityProgress(bound.maxTotalRows));
  return Object.freeze({
    fetchPage({pageIndex, rowCount}: Frame) {
      const remaining = cursorResult(Reflect.apply(remainingRows, common,
        [progress, pageIndex, rowCount]), common, issueCode);
      const hasNext = Reflect.apply(hasNextCursor, common, [progress]);
      if (typeof hasNext !== 'boolean') fail('NotionUserListCursorRuntimeMismatch');
      const cursor = hasNext ? cursorResult(Reflect.apply(nextCursor, common, [progress]), common, issueCode)
        : undefined;
      const target = typeof request.page === 'function'
        ? request.page(remaining as number, bound.pageSize, cursor as string | undefined)
        : restSourcePageRequest(request, cursorParameter, remaining, cursor);
      if (Buffer.byteLength(requestTarget(target.path, target.query)) > bound.maxTargetBytes) fail('NotionUserListTargetLimit');
      return target;
    },
    decodePage(response: Response, {pageIndex, rowCount, receivedBodyBytes}: Frame & Readonly<{receivedBodyBytes: bigint}>) {
      // The Host retains and charges this exact body before entering here.
      if (receivedBodyBytes > BigInt(bound.maxTotalResponseBytes)) fail('NotionUserListResponseLimit');
      if (!response.accepted || response.statusCode !== 200) fail('NotionUserListReadRejected');
      const page = checked(provider.notionProjectUserList(response.body, bound.maxResponseBytes,
        bound.maxNodes, bound.maxDepth, Math.min(bound.maxRows, bound.pageSize), bound.maxCursorBytes,
        bound.maxIdentityBytes, bound.maxValueNodes, bound.maxValueTextBytes));
      const metadata = checked(provider.notionUserListMetadata(page,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth));
      const pageRows = runtimeField(metadata, 0);
      const cursorPresent = runtimeField(metadata, 1);
      const cursor = runtimeField(metadata, 2);
      if (!Number.isSafeInteger(pageRows) || (pageRows as number) < 0 ||
          typeof cursorPresent !== 'boolean' || typeof cursor !== 'string') {
        fail('NotionUserListCursorRuntimeMismatch');
      }
      const remaining = cursorResult(Reflect.apply(remainingRows, common,
        [progress, pageIndex, rowCount]), common, issueCode);
      if ((pageRows as number) > (remaining as number)) fail('NotionUserListRowLimit');
      const tracked = provider.notionUserListTrackPageIdentities(identities, page);
      if (runtimeIsError(tracked)) {
        const code = runtimeField(tracked, 0);
        fail(typeof code === 'string' ? code : 'NotionUserListIdentityRuntimeMismatch');
      }
      checked(tracked);
      const done = cursorResult(Reflect.apply(advanceCursor, common,
        [progress, pageIndex, rowCount, pageRows, cursorPresent, cursor]), common, issueCode);
      if (typeof done !== 'boolean') fail('NotionUserListCursorRuntimeMismatch');
      const rowsWire = checked(provider.notionUserListRowsWire(page, selected,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth));
      return {rowsWire: rowsWire as string, rowCount: pageRows as number, done};
    },
    onError(cause: unknown) {return new NotionUserListReadFailure(cause);},
  });
}
