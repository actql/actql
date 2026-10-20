import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, mkdtemp, readFile, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {loadExplorerAssets} from './assets.mjs';
import {gatewayLimits} from './gateway.mjs';
import {startExplorer} from './launcher.mjs';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

test('the installed loader admits actual frozen SPA bytes inside the existing asset bound', async () => {
  const assets = await loadExplorerAssets();
  // HTML, application JS/CSS and the separately emitted same-origin ELK Worker.
  assert.equal(assets.size, 4);
  assert([...assets.keys()].some(path => /^\/assets\/flow-layout-worker-[a-zA-Z0-9_-]+\.js$/u.test(path)));
  assert.match(assets.get('/index.html').body.toString(), /ActQL Explorer/u);
  const scripts = [...assets.get('/index.html').body.toString()
    .matchAll(/<script[^>]+src="(\/assets\/[a-zA-Z0-9_-]+\.js)"/gu)];
  assert.equal(scripts.length, 1);
  const script = assets.get(scripts[0][1]);
  assert(script); assert.match(script.body.toString(), /Read Plan/u);
  assert(!script.body.toString().includes('/@vite/client'));
  assert([...assets.values()].reduce((n, a) => n + a.body.length, 0) <= gatewayLimits.assetBytes);
});

test('a built viewer closes its server without closing, cancelling or submitting on the borrowed Client', async t => {
  const calls = [];
  const gateway = await startExplorer({client: {attach() {calls.push('attach');},
    close() {assert.fail('borrowed Client close');}, cancel() {assert.fail('cancel');},
    start() {assert.fail('submit');}}});
  t.after(() => gateway.close());
  const html = await fetch(gateway.origin);
  assert.equal(html.status, 200); assert.match(await html.text(), /ActQL Explorer/u);
  assert.equal(html.headers.get('cache-control'), 'no-store');
  assert.match(html.headers.get('content-security-policy'), /script-src 'self'/u);
  const bootstrap = gateway.issueBootstrap();
  const session = await fetch(`${gateway.origin}/api/session`, {method: 'POST',
    headers: {Origin: gateway.origin, 'Content-Type': 'application/json'},
    body: JSON.stringify({bootstrap: bootstrap.bootstrap})});
  const admitted = await session.json(); assert.equal(session.status, 200);
  assert.deepEqual(admitted.capabilities, {plan: false, run: true, resultMetadata: true,
    resultPayload: false, control: false, sample: false, cancellation: false,checkpointList:false,checkpointReview:false});
  await gateway.close(); assert.deepEqual(calls, []);
  await assert.rejects(fetch(gateway.origin));
});

test('the frozen inventory refuses replaced bytes, duplicate paths and escaping symlinks', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-explorer-assets-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const loader = await readFile(new URL('./assets.mjs', import.meta.url), 'utf8');
  await writeFile(join(directory, 'assets.mjs'), loader.replace("'./gateway.mjs'",
    JSON.stringify(new URL('./gateway.mjs', import.meta.url).href)));
  await mkdir(join(directory, 'dist/assets'), {recursive: true});
  const original = Buffer.from('<!doctype html>frozen');
  await writeFile(join(directory, 'dist/index.html'), original);
  const item = {path: '/index.html', bytes: original.length, sha256: hash(original)};
  const manifest = entries => writeFile(join(directory, 'dist/assets.json'), JSON.stringify({
    version: 'actql-explorer-assets/0.1', assets: entries}));
  const {loadExplorerAssets: load} = await import(`file://${directory}/assets.mjs`);
  await manifest([item]); assert.equal((await load()).size, 1);
  const exact = Buffer.alloc(gatewayLimits.assetBytes, 0x61);
  await writeFile(join(directory, 'dist/index.html'), exact);
  await manifest([{...item, bytes: exact.length, sha256: hash(exact)}]);
  assert.equal((await load()).get('/index.html').body.length, gatewayLimits.assetBytes);
  const over = Buffer.concat([exact, Buffer.from('x')]);
  await writeFile(join(directory, 'dist/index.html'), over);
  await manifest([{...item, bytes: over.length, sha256: hash(over)}]);
  await assert.rejects(load(), {code: 'ExplorerInvalidBuiltAssets'});
  await writeFile(join(directory, 'dist/assets.json'), Buffer.alloc(16385, 0x20));
  await assert.rejects(load(), {code: 'ExplorerInvalidBuiltAssets'});
  await manifest([item, ...Array.from({length: 32}, (_, n) => ({...item, path: `/assets/file${n}.js`}))]);
  await assert.rejects(load(), {code: 'ExplorerInvalidBuiltAssets'});
  await manifest([item]);
  await writeFile(join(directory, 'dist/index.html'), Buffer.from('x'.repeat(original.length)));
  await assert.rejects(load(), {code: 'ExplorerInvalidBuiltAssets'});
  await writeFile(join(directory, 'dist/index.html'), original);
  await manifest([item, item]); await assert.rejects(load(), {code: 'ExplorerInvalidBuiltAssets'});
  await manifest([{...item, path: '/../outside.html'}]);
  await assert.rejects(load(), {code: 'ExplorerInvalidBuiltAssets'});
  await manifest([item]); await rm(join(directory, 'dist/index.html'));
  await writeFile(join(directory, 'outside.html'), original);
  await symlink(join(directory, 'outside.html'), join(directory, 'dist/index.html'));
  await assert.rejects(load(), {code: 'ExplorerInvalidBuiltAssets'});
  await rm(join(directory, 'dist/index.html')); await copyFile(join(directory, 'outside.html'), join(directory, 'dist/index.html'));
  await rm(join(directory, 'dist/assets'), {recursive: true});
  await mkdir(join(directory, 'outside')); await writeFile(join(directory, 'outside/view.js'), original);
  await symlink(join(directory, 'outside'), join(directory, 'dist/assets'));
  await manifest([item, {...item, path: '/assets/view.js'}]);
  await assert.rejects(load(), {code: 'ExplorerInvalidBuiltAssets'});
});

test('the non-conflicting launcher requires explicit Host ownership and never prints arbitrary arguments', () => {
  const cli = new URL('./cli.mjs', import.meta.url);
  assert.match(execFileSync(process.execPath, [cli.pathname, '--help'], {encoding: 'utf8'}), /actql-explorer --local/u);
  assert.throws(() => execFileSync(process.execPath, [cli.pathname, '--token', 'private-secret'],
    {encoding: 'utf8', stdio: 'pipe'}), error => {
      assert.equal(error.status, 1); assert(!error.stderr.includes('private-secret'));
      assert.match(error.stderr, /ExplorerInvalidArguments/u); return true;
    });
  assert.throws(() => execFileSync(process.execPath, [cli.pathname], {encoding: 'utf8', stdio: 'pipe'}),
    error => {assert.match(error.stderr, /ExplorerExplicitHostRequired/u); return true;});
});
