import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const nodes = [];
function collect(node) {
  if (node === null || typeof node !== 'object') return;
  nodes.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collect);
    else if (value !== null && typeof value === 'object') collect(value);
  }
}
collect(ast);
const retain = nodes.filter(node => node.type === 'Property' && node.method &&
  node.key.name === 'retainHostJournalPreparation');
const read = ast.body.map(node => node.declaration ?? node).find(node =>
  node.type === 'FunctionDeclaration' && node.id.name === 'readHostJournalPreparation');
assert.equal(retain.length, 1);
assert.ok(read);
const make = compileFunction(`return {${source.slice(retain[0].start, retain[0].end)}};`,
  ['assertInitialControlHostPreparation', 'originals', 'originalInstallation',
    'host', 'profiles', 'join', 'clientOperationError']);
const lookup = compileFunction(source.slice(read.body.start + 1, read.body.end - 1),
  ['originals', 'assertInitialControlHostPreparation', 'profiles']);

function fixture() {
  const profiles = createEmbeddedHostRegistry(() => false);
  const host = {}, installation = {root: '/original-host'};
  const originals = Object.freeze({host, installation, generation: host});
  profiles.registerPreparation(host, installation, host);
  const current = value => profiles.assertPreparation(
    value.host, value.installation, value.generation);
  const preparation = make(current, originals, installation, host, profiles, join,
    code => Object.assign(new Error(code), {code}));
  return {profiles, host, installation, originals, preparation,
    read: (value = originals) => lookup(value, current, profiles)};
}

// Actual Host preparation statements and its existing registry, with explicit
// stopping startup/currentness ports. No SQLite/FS supplier or grant is issued.
test('Host retains its Journal subject before root-format I/O can create the first marker', () => {
  const host = ast.body.map(node => node.declaration ?? node).find(node =>
    node.type === 'FunctionDeclaration' && node.id.name === 'openInstalledHost');
  const calls = host.body.body.find(node => node.type === 'TryStatement').block.body;
  const held = calls.findIndex(node => node.type === 'ExpressionStatement' &&
    source.slice(node.start, node.end).includes('preparation?.retainHostJournalPreparation('));
  const format = calls.findIndex(node => node.type === 'ExpressionStatement' &&
    node.expression.type === 'AwaitExpression' &&
    node.expression.argument.callee.name === 'admitHostRootFormat');
  assert.ok(held >= 0 && format > held);
});

test('fixed Host Journal projection retains one original pair and refuses copies and replacement', () => {
  const f = fixture();
  assert.throws(() => f.read(), {code: 'InstalledHostPreparationChanged'});
  f.preparation.retainHostJournalPreparation('/original-host', 'original actor',
    join('/original-host', 'requests'));
  const original = f.read();
  assert.ok(Object.isFrozen(original));
  assert.equal(original.root, '/original-host');
  assert.equal(original.principalId, 'original actor');
  assert.equal(original.journalDirectory, join('/original-host', 'requests'));
  assert.strictEqual(f.read(), original);
  original.assertCurrent();
  assert.throws(() => ({...original}).assertCurrent(), {code: 'InstalledHostPreparationChanged'});
  for (const value of [{...f.originals, host: {}},
    {...f.originals, installation: {...f.installation}}, {...f.originals, generation: {}}]) {
    assert.throws(() => f.read(value), {code: 'InstalledHostPreparationChanged'});
  }
  assert.throws(() => f.preparation.retainHostJournalPreparation('/original-host',
    'original actor', join('/original-host', 'requests')), {code: 'InstalledHostPreparationChanged'});
  f.installation.root = '/replacement-host';
  assert.throws(() => original.assertCurrent(), {code: 'InstalledHostPreparationChanged'});
});

test('Host Journal projection rejects foreign subject paths and retired originals without rediscovery', () => {
  const f = fixture();
  for (const [root, principal, directory] of [
    ['/replacement-host', 'actor', '/replacement-host/requests'],
    ['/original-host', '', '/original-host/requests'],
    ['/original-host', 'actor', '/other-journal'],
  ]) {
    assert.throws(() => f.preparation.retainHostJournalPreparation(root, principal, directory),
      {code: 'InstalledHostPreparationChanged'});
    assert.throws(() => f.read(), {code: 'InstalledHostPreparationChanged'});
  }
  f.preparation.retainHostJournalPreparation('/original-host', 'actor',
    join('/original-host', 'requests'));
  const original = f.read();
  f.profiles.retirePreparation(f.host, f.installation, f.host);
  assert.throws(() => f.read(), {code: 'InstalledHostPreparationChanged'});
  assert.throws(() => original.assertCurrent(), {code: 'InstalledHostPreparationChanged'});
});
