// The CLI and the installed runner select the same finite input.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstatSync, readFileSync} from 'node:fs';
import {isAbsolute, resolve, sep} from 'node:path';

const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const closed = (value, keys) => record(value) && Object.keys(value).length === keys.length &&
  keys.every(key => Object.hasOwn(value, key));
const sha256 = value => typeof value === 'string' && /^[0-9a-f]{64}$/u.test(value);
const gitIdentity = value => typeof value === 'string' && /^[0-9a-f]{40}$/u.test(value);
const absolute = value => typeof value === 'string' && isAbsolute(value);
const name = value => typeof value === 'string' && /^[a-z][a-z0-9_]*$/u.test(value);
const connection = value => typeof value === 'string' && /^[a-z][a-z0-9_-]*$/u.test(value);
const relative = value => typeof value === 'string' &&
  /^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/u.test(value) &&
  value.split('/').every(part => part !== '.' && part !== '..');
const fixtureTarget = value => typeof value === 'string' && value.startsWith('/') &&
  !value.startsWith('//') && !/[\\#\s\u0000-\u001f\u007f]/u.test(value);

export function readRestConformanceInput(path) {
  const selected = JSON.parse(readFileSync(path, 'utf8'));
  const fields = ['kind', 'sourceSha', 'sourceTree', 'manifestPath',
    'manifestSha256', 'outputRoot', 'accountConfigurationPath', 'mode'];
  if (selected?.mode === 'author') fields.push('casePath', 'caseSha256');
  assert(closed(selected, fields) && selected.kind === 'actql-standard-rest-normal/0.1' &&
    ['empty', 'one', 'paged', 'notion-users', 'author'].includes(selected.mode) &&
    gitIdentity(selected.sourceSha) && gitIdentity(selected.sourceTree) &&
    sha256(selected.manifestSha256) &&
    ['manifestPath', 'outputRoot', 'accountConfigurationPath'].every(key => absolute(selected[key])) &&
    (selected.mode !== 'author' || absolute(selected.casePath) && sha256(selected.caseSha256)),
  'Invalid actql-standard-rest-normal/0.1 descriptor; select a runtime, Account and case explicitly');
  return selected;
}

// Open only a named input under the case directory. Retain the checked bytes
// for staging rather than reopening an author's file during installation.
export function readAuthorBytes(root, path, digest, maxBytes) {
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

export function readPinnedBytes(path, digest, maxBytes) {
  const info = lstatSync(path);
  assert(info.isFile() && info.size <= maxBytes, 'Invalid REST case input file');
  const bytes = readFileSync(path);
  assert(bytes.length <= maxBytes && createHash('sha256').update(bytes).digest('hex') === digest,
    'REST case input digest mismatch');
  return bytes;
}

export function readAuthorRestCase(path, digest) {
  const author = JSON.parse(readPinnedBytes(path, digest, 1024 * 1024));
  assert(closed(author, ['id', 'connector', 'connection', 'schema', 'seed',
    'program', 'parameters', 'expected', 'protocol']) && name(author.id) && connection(author.connection),
  'Invalid REST author case');
  const {connector, schema, seed, program, parameters, expected, protocol} = author;
  const definition = connector?.kind === 'definition';
  assert((definition || connector?.kind === 'packed') &&
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
  assert(closed(expected, ['rows', 'before', 'after', 'control']) &&
    Array.isArray(expected.rows) && expected.rows.every(record) && record(expected.before) &&
    record(expected.after) && record(expected.control), 'Invalid REST author expectations');
  assert(closed(protocol, definition ? ['exchanges'] : ['port', 'exchanges']) &&
    (definition || Number.isInteger(protocol.port) && protocol.port > 0 && protocol.port <= 65535) &&
    Array.isArray(protocol.exchanges) && protocol.exchanges.length > 0 &&
    protocol.exchanges.every(exchange => closed(exchange, ['target', 'page']) &&
      fixtureTarget(exchange.target) && name(exchange.page) && Object.hasOwn(seed.pages, exchange.page)),
  'Invalid REST author fixture protocol');
  return author;
}

export function assertAuthorRestSchema(schema, views) {
  const view = views.views?.find(item => item.resource === schema.resource);
  assert.deepEqual(view, {resource: schema.resource, resource_kind: 'record', fields: schema.fields},
    'REST installed source does not match the independent case schema');
}

export function assertAuthorRestRows(expected, actual) {
  assert.deepEqual(actual, expected.rows, 'REST Result does not match the independent row oracle');
}

export function createAuthorRestProvider({seed, expected, protocol}) {
  const state = structuredClone(seed);
  const requests = [];
  return Object.freeze({
    handle({method, target}) {
      const exchange = protocol.exchanges[requests.length];
      requests.push({method, target});
      assert.equal(method, 'GET');
      assert.equal(target, exchange?.target, 'Unexpected REST fixture request');
      return {statusCode: 200, body: JSON.stringify(state.pages[exchange.page])};
    },
    requests() {return requests.map(value => ({...value}));},
    assertRequests(transport) {
      const original = protocol.exchanges.map(({target}) => ({method: 'GET', target}));
      assert.deepEqual(requests, original);
      assert.deepEqual(transport.map(({method, path, authorized}) => ({method, target: path, authorized})),
        original.map(request => ({...request, authorized: true})));
    },
    assertState(phase) {
      assert.deepEqual(state.pages, expected[phase], `REST fixture ${phase} records differ`);
      assert.deepEqual(state.control, expected.control, 'REST fixture control records differ');
      return structuredClone(state);
    },
  });
}
