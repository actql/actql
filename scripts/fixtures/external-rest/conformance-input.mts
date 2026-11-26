// The CLI and the installed runner select the same finite input.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstatSync, readFileSync} from 'node:fs';
import {resolve, sep} from 'node:path';

type Fields = Record<string, unknown>;
type PageRecords = Record<string, Fields>;
export type AuthorRestSchema = {registration: string; resource: string; fields: (Fields & {name: string})[]};
type AuthorRestSeed = {pages: PageRecords; control: Fields};
type AuthorRestExpected = {rows: Fields[]; before: Fields; after: Fields; control: Fields};
type AuthorRestProtocol = {port?: number; exchanges: {target: string; page: string}[]};
export type AuthorRestCase = {
  id: string;
  connector: {kind: 'definition' | 'packed'; path: string; sha256: string; transformSha256?: string};
  connection: string;
  schema: AuthorRestSchema;
  seed: AuthorRestSeed;
  program: Fields & {results: Fields};
  parameters: Fields | null;
  expected: AuthorRestExpected;
  protocol: AuthorRestProtocol;
};
type ProviderRequest = {method: string; target: string};
type ObservedHttpRequest = {method: string; path: string; authorized: boolean};

const record = (value: unknown): value is Fields => value !== null && typeof value === 'object' && !Array.isArray(value);
const closed = (value: unknown, keys: readonly string[]): value is Fields => record(value) && Object.keys(value).length === keys.length &&
  keys.every(key => Object.hasOwn(value, key));
const sha256 = (value: unknown): value is string => typeof value === 'string' && /^[0-9a-f]{64}$/u.test(value);
const gitIdentity = (value: unknown): value is string => typeof value === 'string' && /^[0-9a-f]{40}$/u.test(value);
const name = (value: unknown): value is string => typeof value === 'string' && /^[a-z][a-z0-9_]*$/u.test(value);
const connection = (value: unknown): value is string => typeof value === 'string' && /^[a-z][a-z0-9_-]*$/u.test(value);
const relative = (value: unknown): value is string => typeof value === 'string' &&
  /^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/u.test(value) &&
  value.split('/').every(part => part !== '.' && part !== '..');
const fixtureTarget = (value: unknown): value is string => typeof value === 'string' && value.startsWith('/') &&
  !value.startsWith('//') && !/[\\#\s\u0000-\u001f\u007f]/u.test(value);

export {readRestConformanceInput} from '../../connector-conformance-input.mjs';

// Open only a named input under the case directory. Retain the checked bytes
// for staging rather than reopening an author's file during installation.
export function readAuthorBytes(root: string, path: unknown, digest: string | undefined, maxBytes: number) {
  assert(relative(path), 'Invalid REST author input path');
  const base = resolve(root);
  const filename = resolve(base, path);
  let cursor = base;
  for (const part of path.split('/')) {
    cursor = resolve(cursor, part);
    assert(!lstatSync(cursor).isSymbolicLink(), 'Aliased REST author input');
  }
  assert(filename.startsWith(base + sep) && lstatSync(filename).isFile(), 'Invalid REST author input file');
  return readPinnedBytes(filename, digest, maxBytes);
}

export function readPinnedBytes(path: string, digest: string | undefined, maxBytes: number) {
  const info = lstatSync(path);
  assert(info.isFile() && info.size <= maxBytes, 'Invalid REST case input file');
  const bytes = readFileSync(path);
  assert(bytes.length <= maxBytes && createHash('sha256').update(bytes).digest('hex') === digest,
    'REST case input digest mismatch');
  return bytes;
}

export function readAuthorRestCase(path: string, digest: string): AuthorRestCase {
  const author: unknown = JSON.parse(readPinnedBytes(path, digest, 1024 * 1024).toString('utf8'));
  assert(closed(author, ['id', 'connector', 'connection', 'schema', 'seed',
    'program', 'parameters', 'expected', 'protocol']) && name(author.id) && connection(author.connection),
  'Invalid REST author case');
  const {connector, schema, seed, program, parameters, expected, protocol} = author;
  assert(record(connector), 'Invalid REST author connector');
  const definition = connector.kind === 'definition';
  assert((definition || connector.kind === 'packed') &&
    closed(connector, ['kind', 'path', 'sha256', ...(definition && Object.hasOwn(connector, 'transformSha256')
      ? ['transformSha256'] : [])]) &&
    relative(connector.path) && sha256(connector.sha256) &&
    (connector.transformSha256 === undefined || sha256(connector.transformSha256)), 'Invalid REST author connector');
  assert(closed(schema, ['registration', 'resource', 'fields']) && name(schema.registration) &&
    name(schema.resource) && Array.isArray(schema.fields) && schema.fields.length > 0 &&
    schema.fields.every(field => record(field) && name(field.name)) &&
    new Set(schema.fields.map(field => field.name)).size === schema.fields.length, 'Invalid REST author schema');
  assert(record(program) && record(program.results) && Object.hasOwn(program.results, 'rows') &&
    (parameters === null || record(parameters)), 'Invalid REST author Program or parameters');
  assert(closed(seed, ['pages', 'control']) && record(seed.pages) &&
    Object.values(seed.pages).every(record) && record(seed.control), 'Invalid REST author seed');
  const pages = seed.pages;
  assert(closed(expected, ['rows', 'before', 'after', 'control']) &&
    Array.isArray(expected.rows) && expected.rows.every(record) && record(expected.before) &&
    record(expected.after) && record(expected.control), 'Invalid REST author expectations');
  assert(closed(protocol, definition ? ['exchanges'] : ['port', 'exchanges']) &&
    (definition || Number.isInteger(protocol.port) && (protocol.port as number) > 0 && (protocol.port as number) <= 65535) &&
    Array.isArray(protocol.exchanges) && protocol.exchanges.length > 0 &&
    protocol.exchanges.every(exchange => closed(exchange, ['target', 'page']) &&
      fixtureTarget(exchange.target) && name(exchange.page) && Object.hasOwn(pages, exchange.page)),
  'Invalid REST author fixture protocol');
  // The closed-shape checks above admit these case fields. Program contents and
  // individual record and field values stay opaque to this fixture.
  return author as AuthorRestCase;
}

export function assertAuthorRestSchema(schema: AuthorRestSchema, views: unknown) {
  const view = (views as {views?: {resource?: unknown}[]}).views?.find(item => item.resource === schema.resource);
  assert.deepEqual(view, {resource: schema.resource, resource_kind: 'record', fields: schema.fields},
    'REST installed source does not match the independent case schema');
}

export function assertAuthorRestRows(expected: Pick<AuthorRestExpected, 'rows'>, actual: unknown) {
  assert.deepEqual(actual, expected.rows, 'REST Result does not match the independent row oracle');
}

export function createAuthorRestProvider({seed, expected, protocol}: Pick<AuthorRestCase, 'seed' | 'expected' | 'protocol'>) {
  const state = structuredClone(seed);
  const requests: ProviderRequest[] = [];
  return Object.freeze({
    handle({method, target}: ProviderRequest) {
      const exchange = protocol.exchanges[requests.length];
      requests.push({method, target});
      assert.equal(method, 'GET');
      assert.equal(target, exchange?.target, 'Unexpected REST fixture request');
      return {statusCode: 200, body: JSON.stringify(state.pages[exchange.page])};
    },
    requests() {return requests.map(value => ({...value}));},
    assertRequests(transport: readonly ObservedHttpRequest[]) {
      const original = protocol.exchanges.map(({target}) => ({method: 'GET', target}));
      assert.deepEqual(requests, original);
      assert.deepEqual(transport.map(({method, path, authorized}) => ({method, target: path, authorized})),
        original.map(request => ({...request, authorized: true})));
    },
    assertState(phase: 'before' | 'after') {
      assert.deepEqual(state.pages, expected[phase], `REST fixture ${phase} records differ`);
      assert.deepEqual(state.control, expected.control, 'REST fixture control records differ');
      return structuredClone(state);
    },
  });
}
