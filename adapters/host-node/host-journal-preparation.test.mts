import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';

type AstNode = {
  type: string; start: number; end: number; method?: boolean;
  key?: {name: string}; id?: {name: string}; declaration?: AstNode;
  body?: {start: number; end: number; body: AstNode[]};
  block?: {body: AstNode[]};
  name?: string; expression?: AstNode; argument?: AstNode;
  callee?: AstNode; object?: AstNode; property?: AstNode; computed?: boolean;
  declarations?: AstNode[]; init?: AstNode; consequent?: AstNode; alternate?: AstNode;
};
type Registry = ReturnType<typeof createEmbeddedHostRegistry>;
type Installation = {root: string};
type OriginalPair = Readonly<{host: object; installation: Installation; generation: object}>;
type CheckCurrent = (originals: OriginalPair) => void;
type JournalPreparation = {retainHostJournalPreparation(root: string, principal: string, directory: string): void};
type OriginalJournal = {root: string; principalId: string; journalDirectory: string; assertCurrent(): void};


const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}) as unknown as {body: AstNode[]};
const nodes: AstNode[] = [];
function collect(node: unknown) {
  if (node === null || typeof node !== 'object') return;
  nodes.push(node as AstNode);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collect);
    else if (value !== null && typeof value === 'object') collect(value);
  }
}
collect(ast);
const retain = nodes.filter(node => node.type === 'Property' && node.method &&
  node.key!.name === 'retainHostJournalPreparation');
const read = ast.body.map(node => node.declaration ?? node).find(node =>
  node.type === 'FunctionDeclaration' && node.id!.name === 'readHostJournalPreparation');
assert.equal(retain.length, 1);
assert.ok(read);
const make = compileFunction(`return {${source.slice(retain[0].start, retain[0].end)}};`,
  ['assertInitialControlHostPreparation', 'originals', 'originalInstallation',
    'host', 'profiles', 'join', 'clientOperationError']) as (
    current: CheckCurrent, originals: OriginalPair, installation: Installation, host: object,
    profiles: Registry, joinPaths: typeof join, failure: (code: string) => unknown,
  ) => JournalPreparation;
const lookup = compileFunction(source.slice(read.body!.start + 1, read.body!.end - 1),
  ['originals', 'assertInitialControlHostPreparation', 'profiles']) as (originals: OriginalPair, current: CheckCurrent, profiles: Registry) => OriginalJournal;

function fixture() {
  const profiles = createEmbeddedHostRegistry(() => false);
  const host = {}, installation = {root: '/original-host'};
  const originals = Object.freeze({host, installation, generation: host});
  profiles.registerPreparation(host, installation, host);
  const current = (value: OriginalPair) => profiles.assertPreparation(
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
    node.type === 'FunctionDeclaration' && node.id!.name === 'openInstalledHost');
  const preparationCall = (node: AstNode | undefined, name: string) => {
    const call = node?.type === 'ChainExpression' ? node.expression : node;
    return call?.type === 'CallExpression' && call.callee?.type === 'MemberExpression' &&
      !call.callee.computed && call.callee.object?.name === 'preparation' && call.callee.property?.name === name;
  };
  const holdsOriginal = (node: AstNode) =>
    node.type === 'ExpressionStatement' && preparationCall(node.expression, 'retainHostJournalPreparation');
  const calls = host!.body!.body.find(node =>
    node.type === 'TryStatement' && node.block!.body.some(holdsOriginal))!.block!.body;
  const held = calls.findIndex(holdsOriginal);
  const journal = calls.findIndex(node => {
    const statement = node.type === 'IfStatement' ? node.consequent : node;
    return statement?.type === 'ExpressionStatement' && statement.expression?.type === 'AwaitExpression' &&
      preparationCall(statement.expression.argument, 'prepareHostJournal');
  });
  const format = calls.findIndex(node => node.type === 'VariableDeclaration' &&
    node.declarations!.some(declaration => {
      const initializer = declaration.init;
      return declaration.id?.name === 'rootCreation' && initializer?.type === 'ConditionalExpression' &&
        initializer.consequent?.type === 'AwaitExpression' &&
        initializer.consequent.argument?.type === 'CallExpression' &&
        initializer.consequent.argument.callee?.name === 'admitHostRootFormat' &&
        initializer.alternate?.type === 'AwaitExpression' &&
        preparationCall(initializer.alternate.argument, 'admitRootFormat');
    }));
  assert.ok(held >= 0 && journal > held && format > journal);
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
