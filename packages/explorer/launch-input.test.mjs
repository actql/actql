import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {copyExplorerLaunchInput} from './launch-input.mjs';
import {explorerArguments, explorerLaunchInput} from './cli-input.mjs';

const ref = {namespaceId: 'original', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const hash = value => createHash('sha256').update(value).digest('hex');

test('launch metadata copies only original text or complete Run reference and has no credential fields', () => {
  assert.equal(copyExplorerLaunchInput(undefined), null);
  const selected = {kind: 'run', ref: {...ref}};
  const original = copyExplorerLaunchInput(selected);
  selected.ref.namespaceId = 'changed';
  assert.deepEqual(original, {kind: 'run', ref});
  assert(Object.isFrozen(original) && Object.isFrozen(original.ref));
  const text = '\uFEFFSELECT \'e\u0301\' AS n\r\n';
  assert.deepEqual(copyExplorerLaunchInput({kind: 'program', text, format: 'sql'}),
    {kind: 'program', text, format: 'sql'});
  for (const rejected of [{kind: 'run', ref: {...ref, token: 'private'}},
    {kind: 'run', ref: ref.runDefinitionCid}, {kind: 'program', text: '', format: 'sql'},
    {kind: 'program', text, format: 'auto'}, {kind: 'program', text, format: 'sql', start: true},
    {kind: 'program', text: {}, format: 'program'}]) {
    assert.throws(() => copyExplorerLaunchInput(rejected), {code: 'ExplorerInvalidLaunchInput'});
  }
});

test('launch envelope uses the exact existing 65536-byte bound including encoding', () => {
  const empty = {kind: 'program', text: '', format: 'sql'};
  const remaining = 65536 - Buffer.byteLength(JSON.stringify(empty));
  assert.equal(Buffer.byteLength(JSON.stringify(copyExplorerLaunchInput({
    ...empty, text: 'x'.repeat(remaining)}))), 65536);
  assert.throws(() => copyExplorerLaunchInput({...empty, text: 'x'.repeat(remaining + 1)}),
    {code: 'ExplorerInvalidLaunchInput'});
  for (const text of ['"'.repeat(remaining), '😀'.repeat(Math.floor(remaining / 2))]) {
    assert.throws(() => copyExplorerLaunchInput({...empty, text}), {code: 'ExplorerInvalidLaunchInput'});
  }
});

test('direct-open arguments keep Local explicit, formats explicit and program/run exclusive', () => {
  assert.deepEqual(explorerArguments(['--local', '--program', 'query.sql']),
    {local: {}, program: 'query.sql', format: 'sql'});
  assert.deepEqual(explorerArguments(['--local', '--state-dir', 'state', '--run', 'ref.json']),
    {local: {stateDir: 'state'}, run: 'ref.json'});
  assert.equal(explorerArguments(['--format', 'program', '--program', 'query.json', '--local']).format, 'program');
  assert.throws(() => explorerArguments(['--program', 'query.sql']), /ExplorerExplicitHostRequired/u);
  for (const args of [['--local', '--program', 'one', '--run', 'two'],
    ['--local', '--format', 'sql'], ['--local', '--program'],
    ['--local', '--program', 'one', '--format', 'auto'],
    ['--local', '--run', 'one', '--run', 'two'], ['--local', '--local'],
    ['--local', '--token', 'private']]) {
    assert.throws(() => explorerArguments(args), /ExplorerInvalidArguments/u);
  }
});

test('explicit launch files preserve exact UTF-8 text/reference and remain unchanged', async t => {
  const path = await mkdtemp(join(tmpdir(), 'actql-explorer-launch-'));
  t.after(() => rm(path, {recursive: true, force: true}));
  const program = join(path, 'query.sql'), run = join(path, 'ref.json');
  const text = '\uFEFFSELECT \'e\u0301\' AS n\r\n';
  await writeFile(program, text); await writeFile(run, JSON.stringify(ref));
  const before = await Promise.all([program, run].map(async p => hash(await readFile(p))));
  assert.deepEqual(await explorerLaunchInput(explorerArguments(['--local', '--program', program])),
    {kind: 'program', text, format: 'sql'});
  assert.deepEqual(await explorerLaunchInput(explorerArguments(['--local', '--run', run])), {kind: 'run', ref});
  assert.deepEqual(await Promise.all([program, run].map(async p => hash(await readFile(p)))), before);
  assert.equal(await explorerLaunchInput(explorerArguments(['--local'])), null);
});

test('launch file intake rejects symlinks, directories, oversize, invalid UTF-8 and foreign Run shape', async t => {
  const path = await mkdtemp(join(tmpdir(), 'actql-explorer-launch-invalid-'));
  t.after(() => rm(path, {recursive: true, force: true}));
  const file = join(path, 'query'), link = join(path, 'link');
  await writeFile(file, 'SELECT 1'); await symlink(file, link);
  const read = p => explorerLaunchInput(explorerArguments(['--local', '--program', p]));
  await assert.rejects(read(link)); await assert.rejects(read(path));
  await writeFile(file, Buffer.alloc(65537, 65)); await assert.rejects(read(file));
  await writeFile(file, Buffer.from([255])); await assert.rejects(read(file));
  await writeFile(file, JSON.stringify({...ref, namespaceId: 1}));
  await assert.rejects(explorerLaunchInput(explorerArguments(['--local', '--run', file])),
    {code: 'ExplorerInvalidLaunchInput'});
});
