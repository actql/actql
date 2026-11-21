// Notion request and checked page meaning only. The shared Host reader owns
// authentication, accounting, current checks, cancellation and physical cleanup.
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField, runtimeIsError} from '../../../host-common/compiler-binding.generated.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';
import {captureRestSourceRead, restSourcePageRequest} from '../../../host-node/rest-source-request.mjs';
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
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const providerExports = ['notionProjectUserList','notionUserListIds','notionUserListRowsWire',
  'notionUserListMetadataJson','notionUserListColumnNames'];
const cursorMethods = ['clientProgramRowSourcePrepareCursorProgress', 'clientProgramRowSourceCursorRemainingRows',
  'clientProgramRowSourceCursorHasNext', 'clientProgramRowSourceCursorNext',
  'clientProgramRowSourceAdvanceProviderPageCursor', 'clientProgramRowSourceCursorIssueCode'];
const cursorCodes = Object.freeze({
  RestSourcePageLimit: 'NotionUserListPageLimit',
  RestSourceRowLimit: 'NotionUserListRowLimit',
  RestSourceCursorCycle: 'NotionUserListRepeatedCursor',
});

function cursorResult(result, common, issueCode) {
  if (runtimeIsError(result)) {
    const cause = runtimeField(result, 0);
    const selected = Reflect.apply(issueCode, common, [cause]);
    const code = Object.hasOwn(cursorCodes, selected) ? cursorCodes[selected] : selected;
    if (typeof code !== 'string' || code.length === 0) fail('NotionUserListCursorRuntimeMismatch');
    throw Object.assign(new Error(code, {cause}), {code});
  }
  return checked(result);
}

const limitFields = ['maxResponseBytes','maxTotalResponseBytes','maxNodes','maxDepth',
  'maxRows','maxTotalRows','maxPages','pageSize','maxCursorBytes','maxIdentityBytes',
  'maxTargetBytes','maxValueNodes','maxValueTextBytes',
  'maxRowsWireBytes','maxRowsWireNodes','maxRowsWireDepth'];

export class NotionUserListReadFailure extends Error {
  constructor(cause) {
    super('NotionUserListReadFailed', {cause});
    this.code = 'NotionUserListReadFailed';
  }
}

export function prepareNotionUserListPages({moon, common, names, limits, request: capturedRequest}, applySynchronousProjection) {
  if (!Array.isArray(names) || !limits || typeof limits !== 'object') fail('InvalidNotionUserListRead');
  if (typeof applySynchronousProjection !== 'function') fail('InvalidNotionUserListRead');
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name => {
    const original = moon?.[name];
    if (typeof original !== 'function') fail('InvalidNotionUserListRead');
    return [name, (...args) => applySynchronousProjection(original, moon, args)];
  })));
  const bound = Object.freeze({...limits});
  const request = capturedRequest ?? captureRestSourceRead(userListRequest.read, cursorParameter);
  const declaredPageSize = typeof request.page === 'function' ? request.pageSize : request.pageSize.limit;
  if (!limitFields.every(name => positive(bound[name])) || bound.pageSize > declaredPageSize) fail('InvalidNotionUserListRead');
  const columns = Object.freeze(provider.notionUserListColumnNames().slice());
  if (names.length > columns.length || new Set(names).size !== names.length ||
      names.some(name => !columns.includes(name))) fail('InvalidNotionUserListRead');
  const [prepareCursor, remainingRows, hasNextCursor, nextCursor, advanceCursor, issueCode] =
    cursorMethods.map(name => {
      const original = common?.[name];
      if (typeof original !== 'function') fail('NotionUserListCursorRuntimeUnavailable');
      return original;
    });
  // Request page size and response row admission are independent. The codec
  // retains its original smaller response limit when maxRows < pageSize.
  const progress = cursorResult(Reflect.apply(prepareCursor, common,
    [bound.maxPages, bound.maxTotalRows, bound.pageSize, bound.maxCursorBytes]), common, issueCode);
  // Source capture keeps the complete declared row before the user's SELECT.
  const selected = Object.freeze(columns.slice()), ids = new Set();
  return Object.freeze({
    fetchPage({pageIndex, rowCount}) {
      const remaining = cursorResult(Reflect.apply(remainingRows, common,
        [progress, pageIndex, rowCount]), common, issueCode);
      const hasNext = Reflect.apply(hasNextCursor, common, [progress]);
      if (typeof hasNext !== 'boolean') fail('NotionUserListCursorRuntimeMismatch');
      const cursor = hasNext ? cursorResult(Reflect.apply(nextCursor, common, [progress]), common, issueCode)
        : undefined;
      const target = typeof request.page === 'function'
        ? request.page(remaining, bound.pageSize, cursor)
        : restSourcePageRequest(request, cursorParameter, remaining, cursor);
      if (Buffer.byteLength(requestTarget(target.path, target.query)) > bound.maxTargetBytes) fail('NotionUserListTargetLimit');
      return target;
    },
    decodePage(response, {pageIndex, rowCount, receivedBodyBytes}) {
      // The Host retains and charges this exact body before entering here.
      if (receivedBodyBytes > BigInt(bound.maxTotalResponseBytes)) fail('NotionUserListResponseLimit');
      if (!response.accepted || response.statusCode !== 200) fail('NotionUserListReadRejected');
      const page = checked(provider.notionProjectUserList(response.body, bound.maxResponseBytes,
        bound.maxNodes, bound.maxDepth, Math.min(bound.maxRows, bound.pageSize), bound.maxCursorBytes,
        bound.maxIdentityBytes, bound.maxValueNodes, bound.maxValueTextBytes));
      const metadata = JSON.parse(checked(provider.notionUserListMetadataJson(page,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)));
      const remaining = cursorResult(Reflect.apply(remainingRows, common,
        [progress, pageIndex, rowCount]), common, issueCode);
      if (metadata.rowCount > remaining) fail('NotionUserListRowLimit');
      for (const id of provider.notionUserListIds(page)) {
        if (ids.has(id)) fail('NotionUserListDuplicateUser');
        ids.add(id);
      }
      const done = cursorResult(Reflect.apply(advanceCursor, common,
        [progress, pageIndex, rowCount, metadata.rowCount, metadata.nextCursor !== null,
          metadata.nextCursor ?? '']), common, issueCode);
      if (typeof done !== 'boolean') fail('NotionUserListCursorRuntimeMismatch');
      const rowsWire = checked(provider.notionUserListRowsWire(page, selected,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth));
      return {rowsWire, rowCount: metadata.rowCount, done};
    },
    onError(cause) {return new NotionUserListReadFailure(cause);},
  });
}
