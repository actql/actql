// The standard REST API's pure page adaptation for the one managed Host reader.
// Core parses original bytes; this module never parses JSON or owns I/O,
// credentials, currentness, row charging, cancellation or physical cleanup.
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeIsError, runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {types} from 'node:util';
import {captureRestSourceRead, restSourcePageRequest} from './rest-source-request.mjs';

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
  'clientProgramRowSourceTypedJsonPageNextCursor', 'clientProgramRowSourcePrepareCursorProgress',
  'clientProgramRowSourceCursorRemainingRows', 'clientProgramRowSourceAdvanceCursorProgress',
  'clientProgramRowSourceCursorHasNext', 'clientProgramRowSourceCursorNext',
  'clientProgramRowSourceCursorIssueCode'];

export function restSourcePageReader({moon, source, decodePage, request: capturedRequest}) {
  const original = Object.freeze(Object.fromEntries(names.map(name => {
    const method = moon?.[name];
    if (typeof method !== 'function') fail('RestSourcePageProjectionUnavailable');
    return [name, (...args) => Reflect.apply(method, moon, args)];
  })));
  if (decodePage !== undefined && typeof decodePage !== 'function') fail('InvalidRestSourceTransform');
  const transform = decodePage;
  const bound = Object.freeze({...source.limits});
  const resource = source.resource;
  const items = Object.freeze([...source.pagination.items]);
  const nextPath = source.pagination.kind === 'none' ? undefined
    : Object.freeze([...source.pagination.next]);
  const parameter = source.pagination.parameter;
  const request = capturedRequest ?? captureRestSourceRead({method: 'GET', ...source.read}, parameter);
  const columns = Object.freeze(source.fields.map(field => field.name));
  const transformContext = Object.freeze({resource, columns});
  const cursorResult = result => {
    if (runtimeIsError(result)) {
      const cause = runtimeField(result, 0);
      const code = original.clientProgramRowSourceCursorIssueCode(cause);
      if (typeof code !== 'string' || !code) fail('RestSourceCursorRuntimeBindingMismatch');
      throw Object.assign(new Error(code, {cause}), {code});
    }
    return checked(result);
  };
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
  return function preparePageReader(_input, applySynchronousProjection) {
    if (transform !== undefined && typeof applySynchronousProjection !== 'function') {
      fail('RestSourceTransformOwnerUnavailable');
    }
    const progress = cursorResult(original.clientProgramRowSourcePrepareCursorProgress(
      bound.maxPages, bound.maxRows, bound.maxPageRows, bound.maxCursorBytes));
    return Object.freeze({
      fetchPage({pageIndex, rowCount}) {
        const remaining = cursorResult(original.clientProgramRowSourceCursorRemainingRows(progress, pageIndex, rowCount));
        const hasNext = original.clientProgramRowSourceCursorHasNext(progress);
        if (typeof hasNext !== 'boolean') fail('RestSourceCursorRuntimeBindingMismatch');
        const cursor = hasNext ? cursorResult(original.clientProgramRowSourceCursorNext(progress)) : undefined;
        return Object.freeze(restSourcePageRequest(request, parameter, remaining, cursor));
      },
      decodePage(response, {pageIndex, rowCount}) {
        if (!response.accepted || response.statusCode !== 200) fail('RestSourceProviderRejected');
        const remaining = cursorResult(original.clientProgramRowSourceCursorRemainingRows(
          progress, pageIndex, rowCount));
        let page = project(response.body, items, nextPath, remaining, transform !== undefined);
        const envelope = page.originalPage;
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
        const done = cursorResult(original.clientProgramRowSourceAdvanceCursorProgress(
          progress, pageIndex, rowCount, envelope, page.originalPage));
        if (typeof done !== 'boolean') fail('RestSourceCursorRuntimeBindingMismatch');
        // Only the same compiled namespace can admit this opaque parsed page.
        // It still consumes the original response charge and full row schema.
        return Object.freeze({projectedPage: page.originalPage, rowCount: page.rowCount,
          done});
      },
    });
  };
}
