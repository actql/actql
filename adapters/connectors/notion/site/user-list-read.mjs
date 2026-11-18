// Notion request and checked page meaning only. The shared Host reader owns
// authentication, accounting, current checks, cancellation and physical cleanup.
import {checked} from '../../../host-common/runtime-result.mjs';
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

export function prepareNotionUserListPages({moon, names, limits, request: capturedRequest}, applySynchronousProjection) {
  if (!Array.isArray(names) || !limits || typeof limits !== 'object') fail('InvalidNotionUserListRead');
  if (typeof applySynchronousProjection !== 'function') fail('InvalidNotionUserListRead');
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name => {
    const original = moon?.[name];
    if (typeof original !== 'function') fail('InvalidNotionUserListRead');
    return [name, (...args) => applySynchronousProjection(original, moon, args)];
  })));
  const bound = Object.freeze({...limits});
  const request = capturedRequest ?? captureRestSourceRead(userListRequest.read, cursorParameter);
  if (!limitFields.every(name => positive(bound[name])) || bound.pageSize > request.pageSize.limit) fail('InvalidNotionUserListRead');
  const columns = Object.freeze(provider.notionUserListColumnNames().slice());
  if (names.length > columns.length || new Set(names).size !== names.length ||
      names.some(name => !columns.includes(name))) fail('InvalidNotionUserListRead');
  // Source capture keeps the complete declared row before the user's SELECT.
  const selected = Object.freeze(columns.slice()), cursors = new Set(), ids = new Set();
  let cursor;
  return Object.freeze({
    fetchPage({pageIndex, rowCount}) {
      if (pageIndex >= bound.maxPages) fail('NotionUserListPageLimit');
      const remaining = bound.maxTotalRows - rowCount;
      if (remaining <= 0) fail('NotionUserListRowLimit');
      const target = restSourcePageRequest(request, cursorParameter,
        Math.min(bound.pageSize, remaining), cursor);
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
      if (metadata.rowCount > bound.maxTotalRows - rowCount) fail('NotionUserListRowLimit');
      for (const id of provider.notionUserListIds(page)) {
        if (ids.has(id)) fail('NotionUserListDuplicateUser');
        ids.add(id);
      }
      if (metadata.nextCursor !== null) {
        if (cursors.has(metadata.nextCursor)) fail('NotionUserListRepeatedCursor');
        cursors.add(metadata.nextCursor);
        if (pageIndex + 1 === bound.maxPages) fail('NotionUserListPageLimit');
      }
      const rows = JSON.parse(checked(provider.notionUserListRowsWire(page, selected,
        bound.maxRowsWireBytes, bound.maxRowsWireNodes, bound.maxRowsWireDepth)));
      cursor = metadata.nextCursor;
      return {rows, done: cursor === null};
    },
    onError(cause) {return new NotionUserListReadFailure(cause);},
  });
}
