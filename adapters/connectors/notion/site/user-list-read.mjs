// Notion request and checked page meaning only. The shared Host reader owns
// authentication, accounting, current checks, cancellation and physical cleanup.
import {checked} from '../../../host-common/runtime-result.mjs';
import {requestTarget} from '../../../host-common/http-exchange.mjs';

export const NOTION_USER_LIST_OPERATION = 'notion:users:list';
// Reviewed vendor request version, not an ActQL identity/version authority.
export const NOTION_USER_LIST_API_VERSION = '2026-03-11';
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

export function prepareNotionUserListPages({moon, names, limits}) {
  if (!Array.isArray(names) || !limits || typeof limits !== 'object') fail('InvalidNotionUserListRead');
  const provider = Object.freeze(Object.fromEntries(providerExports.map(name => {
    const original = moon?.[name];
    if (typeof original !== 'function') fail('InvalidNotionUserListRead');
    return [name, (...args) => Reflect.apply(original, moon, args)];
  })));
  const bound = Object.freeze({...limits});
  if (!limitFields.every(name => positive(bound[name])) || bound.pageSize > 100) fail('InvalidNotionUserListRead');
  const columns = Object.freeze(provider.notionUserListColumnNames().slice());
  if (names.length > columns.length || new Set(names).size !== names.length ||
      names.some(name => !columns.includes(name))) fail('InvalidNotionUserListRead');
  const selected = Object.freeze(names.slice()), cursors = new Set(), ids = new Set();
  let cursor;
  return Object.freeze({
    fetchPage({pageIndex}) {
      if (pageIndex >= bound.maxPages) fail('NotionUserListPageLimit');
      const query = [['page_size', String(bound.pageSize)]];
      if (cursor !== undefined) query.push(['start_cursor', cursor]);
      const path = '/v1/users';
      if (Buffer.byteLength(requestTarget(path, query)) > bound.maxTargetBytes) fail('NotionUserListTargetLimit');
      return {method: 'GET', path, query, headers: [['accept','application/json'],
        ['notion-version',NOTION_USER_LIST_API_VERSION]], responseHeaders: []};
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
