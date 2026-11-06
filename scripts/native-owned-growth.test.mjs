import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
const root = fileURLToPath(new URL('../', import.meta.url));
const provider = join(root, 'packages/python-local-runtime/native/pre-root');

test('same-owner Native physical growth retains loans and failed cleanup', () => {
  assert.ok((process.platform === 'linux' && process.arch === 'x64') ||
    (process.platform === 'darwin' && process.arch === 'arm64'), 'actual selected Native platform required');
  const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-owned-growth-'));
  const executable = join(scratch, 'growth');
  const args = ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror', '-pthread',
    ...(process.platform === 'linux' ? ['-D_GNU_SOURCE', '-DACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN=1'] : []),
    join(provider, 'fixtures/growth.c'), '-o', executable];
  const build = spawnSync(process.env.CC ?? 'cc', args, {cwd: root, encoding: 'utf8', timeout: 60_000});
  assert.equal(build.status, 0, `${build.error ?? ''}\n${build.stderr}`);
  const run = spawnSync(executable, [], {cwd: root, encoding: 'utf8', timeout: 10_000});
  assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
  const result = JSON.parse(run.stdout);
  assert.equal(result.native_growth_cases, 29);
  assert.equal(result.passed, result.native_growth_cases);
});

test('same original local domain attaches already-held parent backing', () => {
  const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-domain-growth-'));
  const executable = join(scratch, 'domain-growth');
  const build = spawnSync(process.env.CC ?? 'cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror', '-pthread',
    ...(process.platform === 'linux' ? ['-D_GNU_SOURCE', '-DACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN=1'] : []),
    join(provider, 'fixtures/domain_growth.c'), '-o', executable], {cwd: root, encoding: 'utf8', timeout: 60_000});
  assert.equal(build.status, 0, `${build.error ?? ''}\n${build.stderr}`);
  const run = spawnSync(executable, [], {cwd: root, encoding: 'utf8', timeout: 10_000});
  assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
  const result = JSON.parse(run.stdout);
  assert.equal(result.native_domain_growth_cases, 37);
  assert.equal(result.passed, result.native_domain_growth_cases);
});

test('selected scoped provider retains escaped old and new Read allocations', () => {
  assert.ok(process.env.MOON_HOME, 'source-pinned MoonBit installation is required');
  assert.ok((process.platform === 'linux' && process.arch === 'x64') ||
    (process.platform === 'darwin' && process.arch === 'arm64'), 'actual selected Native platform required');
  const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-domain-read-growth-'));
  const stage = join(scratch, 'provider');
  const prepare = spawnSync('python', [join(provider, 'prepare_scoped_read.py'),
    '--moonbit', process.env.MOON_HOME, '--destination', stage, '--target',
    process.platform === 'linux' ? 'x86_64-unknown-linux-gnu' : 'aarch64-apple-darwin'],
  {cwd: root, encoding: 'utf8', timeout: 30_000});
  assert.equal(prepare.status, 0, `${prepare.error ?? ''}\n${prepare.stderr}`);
  const record = JSON.parse(prepare.stdout);
  const executable = join(scratch, 'domain-read-growth');
  const build = spawnSync(process.env.CC ?? 'cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror', '-pthread',
    ...record.required_defines.map(value => `-D${value}`), '-DACTQL_SCOPED_READ_PROVIDER=1',
    // This fixture never enters the ordinary File allocator; no product default is selected.
    ...(process.platform === 'linux' ? ['-DACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS=1'] : []),
    '-DACTQL_DOMAIN_GROWTH_READ=1', `-DOWNED_SOURCE="${join(stage, 'owned_capacity.c')}"`,
    join(provider, 'fixtures/domain_growth.c'), join(stage, 'libmoonbitrun.o'), '-o', executable],
  {cwd: root, encoding: 'utf8', timeout: 60_000});
  assert.equal(build.status, 0, `${build.error ?? ''}\n${build.stderr}`);
  const run = spawnSync(executable, [], {cwd: root, encoding: 'utf8', timeout: 10_000});
  assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
  const result = JSON.parse(run.stdout);
  assert.equal(result.native_domain_growth_cases, 48);
  assert.equal(result.passed, result.native_domain_growth_cases);
});

for (const scoped of [false, true]) test(`same-domain original supplier with staged cleanup (${scoped ? 'scoped Read' : 'physical'})`, () => {
  assert.ok((process.platform === 'linux' && process.arch === 'x64') ||
    (process.platform === 'darwin' && process.arch === 'arm64'), 'actual selected Native platform required');
  const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-domain-supplier-'));
  const executable = join(scratch, 'domain-supplier');
  let definitions = process.platform === 'linux'
    ? ['-D_GNU_SOURCE', '-DACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN=1'] : [];
  let inputs = [];
  if (scoped) {
    assert.ok(process.env.MOON_HOME, 'source-pinned MoonBit installation is required');
    const stage = join(scratch, 'provider');
    const prepare = spawnSync('python', [join(provider, 'prepare_scoped_read.py'),
      '--moonbit', process.env.MOON_HOME, '--destination', stage, '--target',
      process.platform === 'linux' ? 'x86_64-unknown-linux-gnu' : 'aarch64-apple-darwin'],
    {cwd: root, encoding: 'utf8', timeout: 30_000});
    assert.equal(prepare.status, 0, `${prepare.error ?? ''}\n${prepare.stderr}`);
    const record = JSON.parse(prepare.stdout);
    definitions = [...record.required_defines.map(value => `-D${value}`),
      '-DACTQL_SCOPED_READ_PROVIDER=1', '-DACTQL_DOMAIN_GROWTH_READ=1',
      `-DOWNED_SOURCE="${join(stage, 'owned_capacity.c')}"`,
      ...(process.platform === 'linux' ? ['-DACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS=1'] : [])];
    inputs = [join(stage, 'libmoonbitrun.o')];
  }
  const build = spawnSync(process.env.CC ?? 'cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror', '-pthread',
    ...definitions, join(provider, 'fixtures/domain_supplier.c'), ...inputs, '-o', executable],
  {cwd: root, encoding: 'utf8', timeout: 60_000});
  assert.equal(build.status, 0, `${build.error ?? ''}\n${build.stderr}`);
  const run = spawnSync(executable, [], {cwd: root, encoding: 'utf8', timeout: 10_000});
  assert.equal(run.status, 0, `${run.error ?? ''}\n${run.stdout}\n${run.stderr}`);
  const result = JSON.parse(run.stdout);
  assert.equal(result.native_domain_supplier_cases, scoped ? 77 : 73);
  assert.equal(result.passed, result.native_domain_supplier_cases);
});
