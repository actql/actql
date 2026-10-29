// The standard REST API's pure page adaptation for the one managed Host reader.
// Core parses original bytes; this module never parses JSON or owns I/O,
// credentials, currentness, row charging, cancellation or physical cleanup.
import {checked} from '../host-common/runtime-result.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const names = ['clientProgramRowSourceProjectJsonPage', 'clientProgramRowSourceJsonPageRowsWire',
  'clientProgramRowSourceJsonPageRowCount', 'clientProgramRowSourceJsonPageHasNextCursor',
  'clientProgramRowSourceJsonPageNextCursor'];

export function restSourcePageReader({moon, source, decodePage}) {
  const original = Object.freeze(Object.fromEntries(names.map(name => {
    const method = moon?.[name];
    if (typeof method !== 'function') fail('RestSourcePageProjectionUnavailable');
    return [name, (...args) => Reflect.apply(method, moon, args)];
  })));
  if (decodePage !== undefined && typeof decodePage !== 'function') fail('InvalidRestSourceTransform');
  const transform = decodePage;
  const bound = Object.freeze({...source.limits});
  const resource = source.resource, path = source.read.path;
  const items = Object.freeze([...source.pagination.items]);
  const nextPath = source.pagination.kind === 'none' ? undefined
    : Object.freeze([...source.pagination.next]);
  const parameter = source.pagination.parameter;
  const columns = Object.freeze(source.fields.map(field => field.name));
  const transformContext = Object.freeze({resource, columns});
  const project = (bytes, itemsPath, cursorPath, maxRows) => {
    const page = checked(original.clientProgramRowSourceProjectJsonPage(bytes,
      itemsPath, cursorPath !== undefined, cursorPath ?? [], bound.maxPageBytes,
      bound.maxNodes, bound.maxDepth, maxRows, bound.maxCursorBytes));
    const hasNext = original.clientProgramRowSourceJsonPageHasNextCursor(page);
    // Core keeps Option representation inside its bridge. An unknown scalar
    // layout refuses rather than silently becoming EOF or erasing ''.
    if (typeof hasNext !== 'boolean') fail('RestSourceCursorRuntimeBindingMismatch');
    const nextCursor = hasNext
      ? checked(original.clientProgramRowSourceJsonPageNextCursor(page)) : undefined;
    return {rowsWire: original.clientProgramRowSourceJsonPageRowsWire(page),
      rowCount: original.clientProgramRowSourceJsonPageRowCount(page), nextCursor};
  };
  const checkCursor = value => {
    if (value !== undefined && (typeof value !== 'string' || !value.isWellFormed() ||
        Buffer.byteLength(value, 'utf8') > bound.maxCursorBytes)) fail('InvalidRestSourceCursor');
  };
  return function preparePageReader() {
    let cursor;
    const cursors = new Set();
    return Object.freeze({
      fetchPage({pageIndex, rowCount}) {
        if (pageIndex >= bound.maxPages) fail('RestSourcePageLimit');
        if (rowCount >= bound.maxRows) fail('RestSourceRowLimit');
        return Object.freeze({method: 'GET', path,
          query: cursor === undefined ? [] : [[parameter, cursor]],
          headers: [['accept', 'application/json']], responseHeaders: []});
      },
      decodePage(response, {pageIndex, rowCount}) {
        if (!response.accepted || response.statusCode !== 200) fail('RestSourceProviderRejected');
        const remaining = Math.min(bound.maxPageRows, bound.maxRows - rowCount);
        if (remaining < 0) fail('RestSourceRowLimit');
        let page = project(response.body, items, nextPath, remaining);
        if (transform !== undefined) {
          const value = transform(Object.freeze({...page}), transformContext);
          if (typeof value?.then === 'function') {
            void Promise.resolve(value).catch(() => {});
            fail('InvalidRestSourceTransform');
          }
          if (value === null || typeof value !== 'object' ||
              typeof value.rowsWire !== 'string' ||
              Object.keys(value).some(key => !['rowsWire', 'nextCursor'].includes(key))) {
            fail('InvalidRestSourceTransform');
          }
          if (Object.hasOwn(value, 'nextCursor') && value.nextCursor !== page.nextCursor) {
            fail('RestSourceCursorProjectionMismatch');
          }
          // Only a changed wire needs another existing Core parse. Counts
          // never come from an author callback and JS never rounds values.
          if (value.rowsWire !== page.rowsWire) {
            const changed = project(Buffer.from(value.rowsWire, 'utf8'), [], undefined, remaining);
            page = {...changed, nextCursor: page.nextCursor};
          }
        }
        checkCursor(page.nextCursor);
        if (page.nextCursor !== undefined) {
          if (cursors.has(page.nextCursor)) fail('RestSourceCursorCycle');
          if (pageIndex + 1 >= bound.maxPages) fail('RestSourcePageLimit');
          if (rowCount + page.rowCount >= bound.maxRows) fail('RestSourceRowLimit');
          cursors.add(page.nextCursor);
        }
        cursor = page.nextCursor;
        return Object.freeze({rowsWire: page.rowsWire, rowCount: page.rowCount,
          done: cursor === undefined});
      },
    });
  };
}
