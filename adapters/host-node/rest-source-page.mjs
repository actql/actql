// The standard REST API's pure page adaptation for the one managed Host reader.
// Core parses original bytes; this module never parses JSON or owns I/O,
// credentials, currentness, row charging, cancellation or physical cleanup.
import {checked} from '../host-common/runtime-result.mjs';
import {types} from 'node:util';

const isProxy = types.isProxy;

// Author transforms return closed plain own DATA. Descriptor capture enters no
// getter and keeps the same primitives for validation, encoding and cursor use.
function captureTransformResult(value) {
  if (value === null || typeof value !== 'object' || isProxy(value)) {
    fail('InvalidRestSourceTransform');
  }
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== null && prototype !== Object.prototype) fail('InvalidRestSourceTransform');
  const fields = Object.getOwnPropertyDescriptors(value);
  if (!Object.hasOwn(fields, 'rowsWire') ||
      Reflect.ownKeys(fields).some(key => key !== 'rowsWire' && key !== 'nextCursor')) {
    fail('InvalidRestSourceTransform');
  }
  const rows = fields.rowsWire, hasNextCursor = Object.hasOwn(fields, 'nextCursor');
  const cursor = hasNextCursor ? fields.nextCursor : undefined;
  if (!Object.hasOwn(rows, 'value') || cursor !== undefined && !Object.hasOwn(cursor, 'value')) {
    fail('InvalidRestSourceTransform');
  }
  const rowsWire = rows.value, nextCursor = cursor?.value;
  if (typeof rowsWire !== 'string' || nextCursor !== undefined && typeof nextCursor !== 'string') {
    fail('InvalidRestSourceTransform');
  }
  return {rowsWire, hasNextCursor, nextCursor};
}

const fail = code => {throw Object.assign(new Error(code), {code});};
const names = ['clientProgramRowSourceProjectJsonPage', 'clientProgramRowSourceJsonPageRowsWire',
  'clientProgramRowSourceJsonPageOriginal', 'clientProgramRowSourceProjectTypedJsonPage',
  'clientProgramRowSourceTypedJsonPageRowCount', 'clientProgramRowSourceTypedJsonPageHasNextCursor',
  'clientProgramRowSourceTypedJsonPageNextCursor'];

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
  const project = (bytes, itemsPath, cursorPath, maxRows, wire = false) => {
    const projected = checked((wire ? original.clientProgramRowSourceProjectJsonPage
      : original.clientProgramRowSourceProjectTypedJsonPage)(bytes,
      itemsPath, cursorPath !== undefined, cursorPath ?? [], bound.maxPageBytes,
      bound.maxNodes, bound.maxDepth, maxRows, bound.maxCursorBytes));
    const page = wire ? original.clientProgramRowSourceJsonPageOriginal(projected) : projected;
    const hasNext = original.clientProgramRowSourceTypedJsonPageHasNextCursor(page);
    // Core keeps Option representation inside its bridge. An unknown scalar
    // layout refuses rather than silently becoming EOF or erasing ''.
    if (typeof hasNext !== 'boolean') fail('RestSourceCursorRuntimeBindingMismatch');
    const nextCursor = hasNext
      ? checked(original.clientProgramRowSourceTypedJsonPageNextCursor(page)) : undefined;
    return {originalPage: page,
      ...(wire ? {rowsWire: original.clientProgramRowSourceJsonPageRowsWire(projected)} : {}),
      rowCount: original.clientProgramRowSourceTypedJsonPageRowCount(page), nextCursor};
  };
  const checkCursor = value => {
    if (value !== undefined && (typeof value !== 'string' || !value.isWellFormed() ||
        Buffer.byteLength(value, 'utf8') > bound.maxCursorBytes)) fail('InvalidRestSourceCursor');
  };
  return function preparePageReader(_input, applySynchronousProjection) {
    if (transform !== undefined && typeof applySynchronousProjection !== 'function') {
      fail('RestSourceTransformOwnerUnavailable');
    }
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
        let page = project(response.body, items, nextPath, remaining, transform !== undefined);
        if (transform !== undefined) {
          // The SAME managed owner invokes and joins even an invalid async
          // author computation. Capture only its synchronous returned DATA.
          const value = applySynchronousProjection(transform, undefined,
            [Object.freeze({rowsWire: page.rowsWire, rowCount: page.rowCount,
              nextCursor: page.nextCursor}), transformContext]);
          const {rowsWire, hasNextCursor, nextCursor} = captureTransformResult(value);
          if (hasNextCursor && nextCursor !== page.nextCursor) {
            fail('RestSourceCursorProjectionMismatch');
          }
          // Only a changed wire needs another existing Core parse. Counts
          // never come from an author callback and JS never rounds values.
          if (rowsWire !== page.rowsWire) {
            if (rowsWire.length > bound.maxPageBytes ||
                Buffer.byteLength(rowsWire, 'utf8') > bound.maxPageBytes) {
              fail('RestSourceTransformPageLimit');
            }
            const changed = project(Buffer.from(rowsWire, 'utf8'), [], undefined, remaining);
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
        // Only the same compiled namespace can admit this opaque parsed page.
        // It still consumes the original response charge and full row schema.
        return Object.freeze({projectedPage: page.originalPage, rowCount: page.rowCount,
          done: cursor === undefined});
      },
    });
  };
}
