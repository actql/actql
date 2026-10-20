import assert from 'node:assert/strict';
import test from 'node:test';
import {access, mkdir, mkdtemp, readFile, stat, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';

// Real source-checkout SDK/Host/Common/Store/SQLite and normal native module.
// The explicit Account below is a test operator's admitted configuration, not
// product Mock initialization or permission supplied by a Source service.
const accountConfiguration = JSON.stringify({version: 'actql-execution-account-config/0.1',
  account_id: 'actual-local-files-test', entries: [{entry_id: 'explicit-test-operator',
    outcome: 'allow', principal: {all: true}, connection: {all: true},
    resource: {all: true}, operation: {all: true}, exclusions: []}]});
const root = fileURLToPath(new URL('../../', import.meta.url));

test('ordinary Project Local files use one actual managed Run and preserve independent Host close/reopen', async t => {
  const directory = await mkdtemp(join(root, '_build', 'ordinary-project-files-host-'));
  const data = join(directory, 'data'); await mkdir(join(data, 'nested'), {recursive: true});
  await writeFile(join(data, 'one.txt'), 'exact one\n');
  await writeFile(join(data, 'nested/two.txt'), 'exact two\n');
  await writeFile(join(directory, 'actql.config.json'), JSON.stringify({version: 'actql-config/0.1',
    connectors: 'connectors.json'}));
  const connections = JSON.stringify({version: 'actql-connectors/0.1',
    connections: {local: {connector: 'local', root: './data', tables: {}}}});
  await writeFile(join(directory, 'connectors.json'), connections);
  const input = await stat(join(data, 'one.txt'), {bigint: true});
  const cwd = process.cwd(); let first, second, active, primary;
  const options = name => ({mode: 'local', owner: 'local', installation: {
    directory: join(directory, name), authorization: {accountConfiguration}}});
  const step = async (name, operation) => {
    active = name; const result = await operation();
    t.diagnostic(JSON.stringify({step: name, status: 'passed'})); return result;
  };
  const listing = 'SELECT path, size, modified_time, size_bytes, modified_at FROM LIST_FILES(local)';
  t.diagnostic(JSON.stringify({directory})); process.chdir(directory);
  try {
    first = await step('connect ordinary Project Local Source Host', () => connectEmbeddedLocal(options('first')));
    assert.deepEqual(await step('Source Host source-free SELECT', () => first.sql('SELECT 1 AS id').all()), [{id: 1}]);
    const rows = await step('actual Local LIST_FILES on the original managed Run', () => first.sql(listing).all());
    assert.deepEqual(rows.map(row => row.path).sort(), ['nested/two.txt', 'one.txt']);
    const one = rows.find(row => row.path === 'one.txt');
    assert.equal(String(one.size), String(input.size));
    assert.equal(one.size_bytes, Number(input.size));
    assert.equal(typeof one.modified_time, 'string');
    assert.equal(one.modified_time, one.modified_at);
    // The retained exact connection acquisition participates in Host reuse.
    // Changing only original bytes must not silently return the old service.
    await writeFile(join(directory, 'connectors.json'), connections + '\n');
    await step('changed original connection cannot reuse live Host', () =>
      assert.rejects(connectEmbeddedLocal(options('first')), /InstalledHostConfigurationMismatch/u));
    second = await step('connect independent Host on the new declaration acquisition', () => connectEmbeddedLocal(options('second')));
    await step('close original Source Host', () => first.close()); first = undefined;
    assert.deepEqual((await step('other Host remains usable', () => second.sql(listing).all())).map(row => row.path).sort(),
      ['nested/two.txt', 'one.txt']);
    first = await step('reopen original Host with current connection bytes', () => connectEmbeddedLocal(options('first')));
    assert.deepEqual(await step('reopened Source Host source-free SELECT', () => first.sql('SELECT 2 AS id').all()), [{id: 2}]);
    assert.deepEqual((await step('reopened Local Source original read', () => first.sql(listing).all())).map(row => row.path).sort(),
      ['nested/two.txt', 'one.txt']);
    assert.equal(await readFile(join(data, 'one.txt'), 'utf8'), 'exact one\n');
    const after = await stat(join(data, 'one.txt'), {bigint: true});
    assert.deepEqual([after.dev, after.ino, after.size, after.mtimeNs], [input.dev, input.ino, input.size, input.mtimeNs]);
    for (const name of ['first', 'second']) {
      await assert.rejects(access(join(directory, name, 'mock-account')), {code: 'ENOENT'});
    }
  } catch (cause) {
    primary = cause; t.diagnostic(JSON.stringify({firstFailedStep: active, code: cause.code,
      message: cause.message, stack: cause.stack, cause: inspect(cause.cause, {depth: 6})}));
  } finally {
    for (const client of [first, second]) try {await client?.close();}
    catch (cause) {primary = primary === undefined ? cause : new AggregateError([primary, cause],
      'Original Local Source and Host cleanup failed');
      t.diagnostic(JSON.stringify({cleanup: cause.code, message: cause.message,
        pending: cause.cleanupHandle?.status?.(), cause: inspect(cause, {depth: 4})}));}
    process.chdir(cwd);
  }
  if (primary !== undefined) throw primary;
  for (const name of ['first', 'second']) {
    await assert.rejects(access(join(directory, name, 'publication/owner/owner.json')), {code: 'ENOENT'});
  }
});
