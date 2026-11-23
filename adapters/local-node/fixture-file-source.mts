// Fixture transport DATA only. The installing Source owns its original read,
// issued Resource inventory and physical cleanup. Common owns listing/keyed
// admission, the Run Ledger, Store capture and ContentRef issuance.
import {createHash} from 'node:crypto';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checked} from '../host-common/runtime-result.mjs';

type RelationRuntime = Readonly<{
  clientProgramRelationObserveTarget(document: unknown, declaration: unknown, identity: string): unknown;
  clientProgramRelationTargetRowCount(document: unknown): number | undefined;
  clientProgramRelationTargetRowIdentity(document: unknown, index: number): string | undefined;
  clientProgramRelationTargetText(row: unknown, field: string): string | undefined;
  clientProgramRelationTargetTextBytes(row: unknown, field: string): Uint8Array | undefined;
  clientProgramRelationTargetVersion(row: unknown): string | undefined;
}>;
type Physical = Readonly<{
  declaration: unknown;
  resource: string;
  itemsPath: readonly string[];
  keyPath: readonly string[];
  primaryIdentity: string;
  writableFields: readonly string[];
}>;
type Fields = Readonly<{identity: string; name: string; version: string; mediaType: string;
  contentUtf8: string; path?: string}>;
type Limits = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number; maxRows: number;
  maxWork: number; maxPageBytes: number; maxContentBytes: number}>;
type ResourceRef = Readonly<Record<string, string>>;
type RetainRawResponse = (bytes: Uint8Array) => unknown;
type ReadOptions<RowRun> = Readonly<{
  rowRun: RowRun; signal?: AbortSignal; retainRawResponse?: RetainRawResponse; verifyRead(): unknown;
}>;
type ReadControl<Charge> = Readonly<{
  verifyRead(): unknown;
  chargePage(bytes: Uint8Array): Charge;
}>;
type ListingOptions<RowRun, Charge> = ReadOptions<RowRun> & ReadControl<Charge> & Readonly<{
  listing: Readonly<{
    beginRequest(token: undefined): unknown;
    consumePage(body: Uint8Array, received: Readonly<{charge: NonNullable<Charge>}>): unknown;
  }>;
}>;
type ContentOptions<RowRun, Charge, Content> = ReadOptions<RowRun> & ReadControl<Charge> & Readonly<{
  columns?: readonly string[];
  requestWire: string;
  beginRequest(bytes: Uint8Array): unknown;
  consumeObservation(charge: NonNullable<Charge>): unknown;
  captureContent(observed: Readonly<{bytes: Uint8Array; mediaType: string; contentCid: string}>):
    Content | PromiseLike<Content>;
  consumePage(rows: readonly Readonly<{resource: ResourceRef; version: string; content: Content;
    name?: string; path?: string | null; media_type?: string}>[]): unknown;
}>;
type SupplierInputs<RowRun> = Readonly<{
  moon: RelationRuntime;
  physical: Physical;
  fields: Fields;
  limits: Limits;
  readOriginalBytes(options: ReadOptions<RowRun>): Uint8Array | PromiseLike<Uint8Array>;
  projectOriginalDocument(bytes: Uint8Array, options: ReadOptions<RowRun>): unknown;
  issueResource(identity: string): unknown;
  resolveResource(resource: ResourceRef): unknown;
  assertCurrent(): unknown;
}>;

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0 && value.isWellFormed();
const integer = (value: unknown): value is number =>
  Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= 2147483647;
const callbacks = <Value, Key extends keyof Value & string>(value: Value, names: readonly Key[]):
  Readonly<Pick<Value, Key>> => {
  const captured = Object.fromEntries(names.map(name => [name, value?.[name]]));
  if (Object.values(captured).some(method => typeof method !== 'function')) {
    fail('FixtureFileCallbacksUnavailable');
  }
  return Object.freeze(captured) as Readonly<Pick<Value, Key>>;
};
const rawResponseRetainer = (options: object): RetainRawResponse | undefined => {
  const descriptor = Object.getOwnPropertyDescriptor(options, 'retainRawResponse');
  if (descriptor === undefined) return undefined;
  if (!Object.hasOwn(descriptor, 'value') ||
      descriptor.value !== undefined && typeof descriptor.value !== 'function') {
    fail('FixtureFileCallbacksUnavailable');
  }
  return descriptor.value as RetainRawResponse | undefined;
};

export function createFixtureFileSupplier<RowRun>({moon, physical, fields, limits,
  readOriginalBytes, projectOriginalDocument, issueResource, resolveResource, assertCurrent}: SupplierInputs<RowRun>) {
  if (physical?.declaration === undefined || !text(physical.resource) ||
      !Array.isArray(physical.itemsPath) || !physical.itemsPath.every(text) ||
      !Array.isArray(physical.keyPath) || !physical.keyPath.every(text) ||
      !text(physical.primaryIdentity) || !Array.isArray(physical.writableFields) ||
      !physical.writableFields.every(text) || fields?.identity !== physical.primaryIdentity ||
      !(['identity', 'name', 'version', 'mediaType', 'contentUtf8'] as const).every(name => text(fields?.[name])) ||
      fields.path !== undefined && !text(fields.path) ||
      [readOriginalBytes, projectOriginalDocument, issueResource, resolveResource, assertCurrent]
        .some(value => typeof value !== 'function')) {
    fail('InvalidFixtureFileSupplier');
  }
  physical = Object.freeze({...physical, itemsPath: Object.freeze([...physical.itemsPath]),
    keyPath: Object.freeze([...physical.keyPath]),
    writableFields: Object.freeze([...physical.writableFields])});
  fields = Object.freeze({...fields});
  limits = Object.freeze({...limits});
  if (!(['maxBytes', 'maxNodes', 'maxDepth', 'maxRows', 'maxWork', 'maxPageBytes', 'maxContentBytes'] as const)
    .every(name => integer(limits[name])) ||
      (['maxBytes', 'maxNodes', 'maxDepth', 'maxWork', 'maxPageBytes'] as const).some(name => limits[name] === 0) ||
      limits.maxBytes > limits.maxPageBytes || limits.maxContentBytes > limits.maxBytes) {
    fail('InvalidFixtureFileLimits');
  }
  const ports = callbacks(moon, ['clientProgramRelationObserveTarget', 'clientProgramRelationTargetRowCount',
    'clientProgramRelationTargetRowIdentity', 'clientProgramRelationTargetText',
    'clientProgramRelationTargetTextBytes', 'clientProgramRelationTargetVersion']);
  const call = <Name extends keyof RelationRuntime>(name: Name, ...args: Parameters<RelationRuntime[Name]>):
    ReturnType<RelationRuntime[Name]> => Reflect.apply(ports[name], moon, args) as ReturnType<RelationRuntime[Name]>;
  const current = async (verifyRead: ReadControl<unknown>['verifyRead'], signal?: AbortSignal) => {
    signal?.throwIfAborted();
    assertCurrent();
    await verifyRead();
    signal?.throwIfAborted();
    assertCurrent();
  };
  const rowFor = (document: unknown, identity: string) => checked(call('clientProgramRelationObserveTarget',
    document, physical.declaration, identity));
  const rowText = (row: unknown, field: string) => {
    const value = call('clientProgramRelationTargetText', row, field);
    if (typeof value !== 'string') fail('FixtureFileFieldUnavailable');
    return value;
  };
  const pathFor = (row: unknown) => fields.path === undefined ? null
    : call('clientProgramRelationTargetText', row, fields.path) ?? null;
  const versionFor = (row: unknown) => {
    const declared = rowText(row, fields.version);
    const rowVersion = call('clientProgramRelationTargetVersion', row);
    if (!text(declared) || typeof rowVersion !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(rowVersion)) {
      fail('FixtureFileVersionUnavailable');
    }
    // A replaceable fixture may reuse its authored label. Bind the exposed
    // opaque provider version to the actual admitted row without changing it.
    return 'sha256:' + createHash('sha256').update(canonicalJson({
      declared_version: declared, row_version_cid: rowVersion,
    }, {dataKeys: true})).digest('hex');
  };
  // Charge the actual original response before any document parser or getter.
  // The physical reader remains the parent's same retained child on failure.
  const read = async <Charge,>(options: ReadOptions<RowRun>, selected: ReadControl<Charge>,
    retainRawResponse: RetainRawResponse | undefined) => {
    await current(selected.verifyRead, options.signal);
    const bytes = await readOriginalBytes(options);
    if (!(bytes instanceof Uint8Array)) fail('FixtureFileOriginalBytesUnavailable');
    const charge = selected.chargePage(bytes);
    if (charge === undefined || charge === null) fail('FixtureFileChargeUnavailable');
    await current(selected.verifyRead, options.signal);
    if (bytes.byteLength > limits.maxBytes) fail('FixtureFileOriginalBytesLimit');
    if (retainRawResponse !== undefined) {
      await retainRawResponse(bytes);
      await current(selected.verifyRead, options.signal);
    }
    // The same parent admits one original body and projects every declared
    // relation under its cumulative budget. Never parse/copy another body here.
    const document = projectOriginalDocument(bytes, options);
    if (document === undefined) fail('FixtureFileDocumentUnavailable');
    assertCurrent();
    return {document, charge};
  };

  return Object.freeze({
    async readListing<Charge>(options: ListingOptions<RowRun, Charge>) {
      const selected = callbacks(options, ['verifyRead', 'chargePage']);
      const listing = callbacks(options.listing, ['beginRequest', 'consumePage']);
      const retainRawResponse = rawResponseRetainer(options);
      await current(selected.verifyRead, options.signal);
      await listing.beginRequest(undefined);
      const {document, charge} = await read(options, selected, retainRawResponse);
      const count = call('clientProgramRelationTargetRowCount', document);
      if (!integer(count) || count > limits.maxRows) fail('FixtureFileRowsUnavailable');
      const items = [];
      for (let index = 0; index < count; index++) {
        await current(selected.verifyRead, options.signal);
        const identity = call('clientProgramRelationTargetRowIdentity', document, index);
        if (!text(identity)) fail('FixtureFileIdentityUnavailable');
        const row = rowFor(document, identity);
        const version = versionFor(row);
        // Only the installing Source may issue this reference. Neither the
        // physical fixture row nor a path/name is reference authority.
        const resource = issueResource(identity);
        assertCurrent();
        if (resource === null || typeof resource !== 'object' || Array.isArray(resource)) {
          fail('FixtureFileResourceUnavailable');
        }
        items.push({resource, version, name: rowText(row, fields.name), path: pathFor(row),
          media_type: rowText(row, fields.mediaType), size_bytes: null, modified_at: null});
      }
      const body = Buffer.from(JSON.stringify({items, request_token: null, next_token: null}));
      if (body.byteLength > limits.maxPageBytes) fail('FixtureFileListingEnvelopeLimit');
      await current(selected.verifyRead, options.signal);
      await listing.consumePage(body, {charge});
      await current(selected.verifyRead, options.signal);
    },

    async readContent<Charge, Content>(options: ContentOptions<RowRun, Charge, Content>) {
      const selected = callbacks(options, ['verifyRead', 'beginRequest', 'chargePage',
        'consumeObservation', 'captureContent', 'consumePage']);
      const retainRawResponse = rawResponseRetainer(options);
      const allowed = ['resource', 'version', 'content', 'name', 'path', 'media_type'];
      const columns = options.columns === undefined ? ['resource', 'version', 'content'] : options.columns;
      if (!Array.isArray(columns) || columns.length > allowed.length ||
          new Set(columns).size !== columns.length || columns.some(name => !allowed.includes(name)) ||
          typeof options.requestWire !== 'string' || Buffer.byteLength(options.requestWire) > limits.maxPageBytes) {
        fail('InvalidFixtureFileContentRequest');
      }
      const selectedColumns = new Set(columns);
      // The original DATA checks below establish the string fields before use.
      let request: {resource: ResourceRef; version: string};
      try {request = JSON.parse(options.requestWire);} catch {fail('InvalidFixtureFileContentRequest');}
      if (request === null || typeof request !== 'object' || Array.isArray(request) ||
          Object.keys(request).sort().join(',') !== 'resource,version' || !text(request.version) ||
          request.resource === null || typeof request.resource !== 'object' || Array.isArray(request.resource) ||
          Object.values(request.resource).some(value => typeof value !== 'string')) {
        fail('InvalidFixtureFileContentRequest');
      }
      Object.freeze(request.resource);
      Object.freeze(request);
      const requestBytes = Buffer.from(options.requestWire);
      await current(selected.verifyRead, options.signal);
      // Resolve through the Source's existing issued inventory, not by parsing
      // an ID out of the ResourceRef, inventing a path or trusting fixture refs.
      const identity = resolveResource(request.resource);
      assertCurrent();
      if (!text(identity)) fail('FixtureFileResourceUnavailable');
      await selected.beginRequest(requestBytes);
      const {document, charge} = await read(options, selected, retainRawResponse);
      // Inline UTF8 is derived DATA, not a second received response. Its buffer
      // and Store writer overlap belong to the original execution allowance.
      selected.consumeObservation(charge);
      const row = rowFor(document, identity);
      if (versionFor(row) !== request.version) fail('FixtureFileVersionMismatch');
      // Check the declared content ceiling before the Core getter allocates
      // UTF8 bytes. The admitted scalar stays in the original document.
      if (Buffer.byteLength(rowText(row, fields.contentUtf8), 'utf8') > limits.maxContentBytes) {
        fail('FixtureFileContentBytesUnavailable');
      }
      const bytes = call('clientProgramRelationTargetTextBytes', row, fields.contentUtf8);
      if (!(bytes instanceof Uint8Array) || bytes.byteLength > limits.maxContentBytes) {
        fail('FixtureFileContentBytesUnavailable');
      }
      const mediaType = rowText(row, fields.mediaType);
      await current(selected.verifyRead, options.signal);
      const content = await selected.captureContent({bytes, mediaType,
        contentCid: 'sha256:' + createHash('sha256').update(bytes).digest('hex')});
      await current(selected.verifyRead, options.signal);
      await selected.consumePage([{resource: request.resource, version: request.version, content,
        ...(selectedColumns.has('name') ? {name: rowText(row, fields.name)} : {}),
        ...(selectedColumns.has('path') ? {path: pathFor(row)} : {}),
        ...(selectedColumns.has('media_type') ? {media_type: mediaType} : {})}]);
      await current(selected.verifyRead, options.signal);
    },
  });
}
