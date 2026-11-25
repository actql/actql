// The standard REST API's pure page adaptation for the one managed Host reader.
// Core parses original bytes; this module never parses JSON or owns I/O,
// credentials, currentness, row charging, cancellation or physical cleanup.
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeIsError, runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {types} from 'node:util';
import {captureRestSourceRead, restSourcePageRequest} from './rest-source-request.mjs';

import type {RestSourceInstallationDefinition, RestSourceTransform} from '../../packages/local-node/connector-installation.js';
import type {RestSourceRead} from './rest-source-request.mjs';
import type {RestReadOriginal} from './rest-read-original.mjs';

type Port = (...args: unknown[]) => unknown;
type DefinitionSource = RestSourceInstallationDefinition['sources'][number];
type CapturableRead = Omit<RestSourceRead, 'method'> & Readonly<{method?: 'GET'}>;
type Source = Pick<DefinitionSource, 'limits' | 'resource'> & Readonly<{
  pagination: DefinitionSource['pagination'] & Readonly<{parameter?: string}>;
  read?: CapturableRead;
  fields: DefinitionSource['fields'];
}>;
type Transform = (...args: Parameters<RestSourceTransform>) =>
  ReturnType<RestSourceTransform> & Readonly<{then?: never}>;
export type RestSourceProjection = (method: Transform, receiver: undefined,
  args: Readonly<Parameters<RestSourceTransform>>) => ReturnType<Transform>;
type PageOptions = Readonly<{moon: unknown; decodePage?: Transform}> & (
  Readonly<{source: Source; request: RestSourceRead | RestReadOriginal}> |
  Readonly<{source: Source & Readonly<{read: CapturableRead}>; request?: undefined}>
);
type Progress = Readonly<{pageIndex: number; rowCount: number}>;
type Response = Readonly<{accepted: boolean; statusCode: number; body: ArrayBufferView}>;
type PageReader = Readonly<{
  fetchPage(progress: Progress): Readonly<ReturnType<typeof restSourcePageRequest>>;
  decodePage(response: Response, progress: Progress): Readonly<{projectedPage: unknown; rowCount: number; done: boolean}>;
}>;
type PageFactory = (input?: unknown, project?: RestSourceProjection) => PageReader;
type TransformPageFactory = (input: unknown, project: RestSourceProjection) => PageReader;

const isProxy = types.isProxy;

// Author transforms return closed plain own DATA. Descriptor capture enters no
// getter and keeps the same primitives for validation, encoding and cursor use.
function captureTransformResult(value: unknown) {
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

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const names = ['clientProgramRowSourceProjectJsonPage', 'clientProgramRowSourceJsonPageRowsWire',
  'clientProgramRowSourceJsonPageOriginal', 'clientProgramRowSourceProjectTypedJsonPage',
  'clientProgramRowSourceTypedJsonPageRowCount', 'clientProgramRowSourceTypedJsonPageHasNextCursor',
  'clientProgramRowSourceTypedJsonPageNextCursor', 'clientProgramRowSourcePrepareCursorProgress',
  'clientProgramRowSourceCursorRemainingRows', 'clientProgramRowSourceCursorRequestRows', 'clientProgramRowSourceAdvanceCursorProgress',
  'clientProgramRowSourceCursorHasNext', 'clientProgramRowSourceCursorNext',
  'clientProgramRowSourceCursorIssueCode'] as const;

export function restSourcePageReader(options: PageOptions & Readonly<{decodePage: Transform}>): TransformPageFactory;
export function restSourcePageReader(options: PageOptions & Readonly<{decodePage?: undefined}>): PageFactory;
export function restSourcePageReader(options: PageOptions): TransformPageFactory;
export function restSourcePageReader({moon, source, decodePage, request: capturedRequest}: PageOptions): PageFactory {
  const original = Object.freeze(Object.fromEntries(names.map(name => {
    const method = (moon as Readonly<Record<string, unknown>> | null | undefined)?.[name];
    if (typeof method !== 'function') fail('RestSourcePageProjectionUnavailable');
    return [name, (...args: unknown[]) => Reflect.apply(method, moon, args)];
  }))) as Readonly<Record<typeof names[number], Port>>;
  if (decodePage !== undefined && typeof decodePage !== 'function') fail('InvalidRestSourceTransform');
  const transform = decodePage;
  const bound = Object.freeze({...source.limits});
  const resource = source.resource;
  const items = Object.freeze([...source.pagination.items]);
  const nextPath = source.pagination.kind === 'none' ? undefined
    : Object.freeze([...source.pagination.next]);
  const parameter = source.pagination.parameter;
  const request = capturedRequest ?? captureRestSourceRead({method: 'GET', ...source.read}, parameter);
  const columns = Object.freeze(source.fields.map(field => field.name)) as readonly string[];
  const transformContext = Object.freeze({resource, columns});
  const cursorResult = (result: unknown) => {
    if (runtimeIsError(result)) {
      const cause = runtimeField(result, 0);
      const code = original.clientProgramRowSourceCursorIssueCode(cause);
      if (typeof code !== 'string' || !code) fail('RestSourceCursorRuntimeBindingMismatch');
      throw Object.assign(new Error(code, {cause}), {code});
    }
    return checked(result);
  };
  const project = (bytes: ArrayBufferView, itemsPath: readonly string[], cursorPath: readonly string[] | undefined,
    maxRows: number, wire = false) => {
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
      ? checked(original.clientProgramRowSourceTypedJsonPageNextCursor(page)) as string : undefined;
    return {originalPage: page,
      ...(wire ? {rowsWire: original.clientProgramRowSourceJsonPageRowsWire(projected) as string} : {}),
      rowCount: original.clientProgramRowSourceTypedJsonPageRowCount(page) as number, nextCursor};
  };
  return function preparePageReader(_input?: unknown, applySynchronousProjection?: RestSourceProjection) {
    if (transform !== undefined && typeof applySynchronousProjection !== 'function') {
      fail('RestSourceTransformOwnerUnavailable');
    }
    const progress = cursorResult(original.clientProgramRowSourcePrepareCursorProgress(
      bound.maxPages, bound.maxRows, bound.maxPageRows, bound.maxCursorBytes));
    return Object.freeze({
      fetchPage({pageIndex, rowCount}: Progress) {
        // The SAME progress record supplies total remaining rows and current
        // cursor. A checked Core read owns declared size/min/query/header
        // semantics; the legacy row-only representation keeps its old port.
        const requestRows = (typeof request.page === 'function'
          ? cursorResult(original.clientProgramRowSourceCursorRemainingRows(progress, pageIndex, rowCount))
          : cursorResult(original.clientProgramRowSourceCursorRequestRows(progress, pageIndex, rowCount,
            request.pageSize !== undefined, request.pageSize?.limit ?? 0))) as number;
        const hasNext = original.clientProgramRowSourceCursorHasNext(progress);
        if (typeof hasNext !== 'boolean') fail('RestSourceCursorRuntimeBindingMismatch');
        const cursor = hasNext ? cursorResult(original.clientProgramRowSourceCursorNext(progress)) as string : undefined;
        return typeof request.page === 'function'
          ? request.page(requestRows, bound.maxPageRows, cursor)
          : Object.freeze(restSourcePageRequest(request, parameter, requestRows, cursor));
      },
      decodePage(response: Response, {pageIndex, rowCount}: Progress) {
        if (!response.accepted || response.statusCode !== 200) fail('RestSourceProviderRejected');
        const remaining = cursorResult(original.clientProgramRowSourceCursorRemainingRows(
          progress, pageIndex, rowCount)) as number;
        let page = project(response.body, items, nextPath, remaining, transform !== undefined);
        const envelope = page.originalPage;
        if (transform !== undefined) {
          // The SAME managed owner invokes and joins even an invalid async
          // author computation. Capture only its synchronous returned DATA.
          const value = applySynchronousProjection!(transform, undefined,
            [Object.freeze({rowsWire: page.rowsWire!, rowCount: page.rowCount,
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
