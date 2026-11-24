import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync, spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync,
  rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test, {type TestContext} from 'node:test';
import {checkInterfaceOwners} from './check-interface-owners.mjs';
import {repositoryFiles} from './distribution-interface-roots.mjs';
import {checkoutState, initializeNormalPackSourceIndex, normalPackSourceInputs} from './packed-client-packages.mjs';

const reviewAudit = 'reviews/2026-10-13-vector-scalar-installed-source/public-audit.mts';
const reviewRunner = 'reviews/2026-10-14-time-series-release-matrix/prepared-release-public.mts';
const unselectedReview = 'reviews/2026-10-14-time-series-release-matrix/other.mts';

const attributes = ['responsibility', 'inputsOutputs', 'identity', 'ownership',
  'synchronization', 'failure', 'cancellation', 'resources', 'extension', 'verification'];
function fixture(t: TestContext) {
  const root = mkdtempSync(join(tmpdir(), 'actql-normal-pack-source-'));
  t.after(() => rmSync(root, {recursive: true}));
  const source = join(root, 'source'), producer = join(root, 'producer');
  mkdirSync(source); mkdirSync(producer);
  const put = (path: string, value: string) => {
    mkdirSync(dirname(join(source, path)), {recursive: true});
    writeFileSync(join(source, path), value);
  };
  const module = 'export function identity(value) {return value;}\n';
  const declaration = {module: 'packages/example/index.mjs',
    sha256: createHash('sha256').update(module).digest('hex'),
    exports: ['identity'], operations: [{name: 'identity', parameters: ['value'], async: false}],
    role: 'common-semantics', responsibilityFacet: 'primary', owner: 'authored identity owner',
    contracts: [{operations: ['<module>', 'identity'], exports: ['identity'],
      attributes: Object.fromEntries(attributes.map(name => [name,
        [{path: 'docs/original.md', anchor: 'Original identity responsibility'}]]))}]};
  put('packages/example/package.json', JSON.stringify({name: '@fixture/example', exports: './index.mjs'}));
  put('packages/example/index.mjs', module);
  const save = () => put('packages/example/interface-boundaries.json', JSON.stringify([declaration]));
  save();
  put('docs/original.md', 'Original identity responsibility\n');
  put('docs/not-an-input.md', 'Unrelated source is not acquired\n');
  put('release/input.json', '{}\n');
  put('portability/corpus/generation.json', '{"original":true}\n');
  put('docs/spec/generation.md', 'Original normative generation input\n');
  put('tsconfig.tooling.json', JSON.stringify({include: ['scripts/**/*.mts', reviewAudit, reviewRunner]}));
  put(reviewAudit, 'export {};\n');
  put(reviewRunner, 'export {};\n');
  put('reviews/2026-10-13-vector-scalar-installed-source/receipt.json', '{}\n');
  put(unselectedReview, 'export {};\n');
  put('.gitignore', '_build/\n');
  execFileSync('git', ['init', '-q'], {cwd: source});
  const listed = () => repositoryFiles(source);
  const copy = (paths: readonly string[]) => {
    for (const path of paths) {
      mkdirSync(dirname(join(producer, path)), {recursive: true});
      copyFileSync(join(source, path), join(producer, path));
    }
  };
  return {root, source, producer, put, save, declaration, listed, copy};
}

test('normal pack copied sources satisfy the original required interface entrance without history', async t => {
  const f = fixture(t), paths = await normalPackSourceInputs(f.source, f.listed());
  assert(paths.includes('docs/original.md'));
  assert(paths.includes('release/input.json'));
  assert(paths.includes('portability/corpus/generation.json'));
  assert(paths.includes('docs/spec/generation.md'));
  assert(paths.includes(reviewAudit));
  assert(paths.includes(reviewRunner));
  assert(!paths.includes(unselectedReview));
  assert(!paths.includes('reviews/2026-10-13-vector-scalar-installed-source/receipt.json'));
  assert(!paths.includes('docs/not-an-input.md'));
  f.copy(paths);
  const before = paths.map(path => readFileSync(join(f.producer, path)).toString('hex'));
  // CI places this unindexed copy under the checkout's ignored _build root.
  // Parent Git discovery can return an empty listing instead of failing;
  // neither case may admit the copied interfaces before their own index exists.
  await assert.rejects(checkInterfaceOwners(f.producer), error =>
    /git ls-files/u.test((error as Error).message) ||
    (error as NodeJS.ErrnoException).code === 'ERR_ASSERTION' &&
    (error as Error).message === 'No normal product interfaces discovered');
  initializeNormalPackSourceIndex(f.producer, paths);
  assert.deepEqual(repositoryFiles(f.producer), [...paths].sort());
  assert.notEqual(spawnSync('git', ['rev-parse', '--verify', 'HEAD'], {cwd: f.producer}).status, 0);
  const checked = await checkInterfaceOwners(f.producer);
  assert.equal(checked.result.primaryComplete, true);
  assert.equal(checked.result.primaryCovered, 1);
  assert.equal(existsSync(join(f.producer, '_build')), false);
  assert.deepEqual(paths.map(path => readFileSync(join(f.producer, path)).toString('hex')), before);
});

test('normal package freshness includes new normative generation inputs without unrelated documentation', t => {
  const f = fixture(t);
  rmSync(join(f.source, reviewRunner));
  execFileSync('git', ['add', '.'], {cwd: f.source});
  execFileSync('git', ['-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
    'commit', '-qm', 'Authored source fixture'], {cwd: f.source});
  assert.equal(checkoutState(f.source).clean, true);
  f.put('docs/unrelated-new.md', 'Unrelated documentation\n');
  f.put(reviewRunner, 'export {};\n');
  assert.equal(checkoutState(f.source).clean, false);
  rmSync(join(f.source, reviewRunner));
  assert.equal(checkoutState(f.source).clean, true);
  for (const path of ['portability/corpus/new.json', 'docs/spec/new.md']) {
    f.put(path, 'New normative generation input\n');
    assert.equal(checkoutState(f.source).clean, false, path);
    rmSync(join(f.source, path));
    assert.equal(checkoutState(f.source).clean, true);
  }
});

test('normal pack reference acquisition preserves canonical malformed and missing-reference refusals', async t => {
  const f = fixture(t);
  await assert.rejects(normalPackSourceInputs(f.source, f.listed().filter(path => path !== reviewRunner)),
    /UnlistedNormalPackSourceReference:.*prepared-release-public\.mts/u);
  f.declaration.contracts[0].attributes.failure = [{path: 'docs/original.md', anchor: 'Absent original anchor'}];
  f.save();
  await assert.rejects(normalPackSourceInputs(f.source, f.listed()), /Missing interface reference/u);
  f.declaration.contracts[0].attributes.failure = [{path: '../outside.md', anchor: 'Original'}];
  f.save();
  await assert.rejects(normalPackSourceInputs(f.source, f.listed()), /Invalid interface reference/u);
  f.declaration.contracts[0].attributes.failure = [{path: 'docs/not-listed.md', anchor: 'Original'}];
  f.save();
  await assert.rejects(normalPackSourceInputs(f.source, f.listed()), /UnlistedNormalPackSourceReference/u);
});

test('normal pack acquisition refuses an original reference symlink outside the copied source root', async t => {
  const f = fixture(t);
  writeFileSync(join(f.root, 'outside.md'), 'Original identity responsibility\n');
  symlinkSync(join(f.root, 'outside.md'), join(f.source, 'docs/escape.md'));
  f.declaration.contracts[0].attributes.failure = [{path: 'docs/escape.md', anchor: 'Original identity responsibility'}];
  f.save();
  await assert.rejects(normalPackSourceInputs(f.source, f.listed()), /EscapedNormalPackSourceReference/u);
});

test('normal pack source indexing is literal, bounded to copied paths, and cannot redirect an inherited index', t => {
  const f = fixture(t);
  f.put('literal [a] source.txt', 'Original literal file\n');
  f.put('ignored-source.mjs', 'export const original = true;\n');
  f.put('.gitignore', 'ignored-source.mjs\n');
  const paths = ['.gitignore', 'literal [a] source.txt', 'ignored-source.mjs'];
  f.copy(paths);
  const inherited = join(f.root, 'inherited-index'), previous = process.env.GIT_INDEX_FILE;
  writeFileSync(inherited, 'Untouched inherited index DATA\n');
  process.env.GIT_INDEX_FILE = inherited;
  try { initializeNormalPackSourceIndex(f.producer, paths); }
  finally {
    if (previous === undefined) delete process.env.GIT_INDEX_FILE;
    else process.env.GIT_INDEX_FILE = previous;
  }
  assert.equal(readFileSync(inherited, 'utf8'), 'Untouched inherited index DATA\n');
  assert.deepEqual(repositoryFiles(f.producer), [...paths].sort());
  assert.throws(() => initializeNormalPackSourceIndex(f.producer, paths), /index already exists/u);
  const empty = join(f.root, 'empty'); mkdirSync(empty);
  for (const values of [['../outside'], ['/absolute'], ['.git/config'], ['file', 'file'], ['bad\0path']]) {
    assert.throws(() => initializeNormalPackSourceIndex(empty, values), /source path/u);
    assert.equal(existsSync(join(empty, '.git')), false);
  }
});
