// Same original C adapter and platform SQLite; selected-module provenance,
// managed Store scope and normal Host consumers require separate evidence.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {join} from 'node:path';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {createOwnedScratch} from './owned-scratch.mjs';
import {createCommandEvidence, commandSource} from './packed-query-evidence.mjs';

async function checkFixture(args, expected) {
  assert.equal(process.platform, 'darwin');
  assert.equal(process.arch, 'arm64');
  const root = process.cwd(), moon = process.env.MOON_HOME;
  assert(moon, 'explicit pinned toolchain required');
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'read-statement-c-', label: 'physical read statement controls',
    digests: () => ['read-statement']});
  const evidence = createCommandEvidence({scratch: join(root, '_build/read-statement-c-evidence'),
    revision: commandSource(root).revision, cwd: root});
  try {
    const compile = ['-Wl,-dead_strip', '-std=c11', '-O0', '-DMOONBIT_ALLOCATOR=2',
      `-I${moon}/include`, join(root, 'scripts/fixtures/native-sqlite-read-statement.c'),
      `${moon}/lib/runtime/runtime.c`, `${moon}/lib/runtime/backtrace.c`,
      `${moon}/lib/libmoonbitrun.o`, '-isysroot',
      '/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk',
      '-lsqlite3', '-o', join(scratch.path, 'read-statement')];
    const built = evidence.capture('/Library/Developer/CommandLineTools/usr/bin/clang',
      compile, {timeout: 20000, killSignal: 'SIGTERM', maxBuffer: 2 * 1024 * 1024});
    assert.equal(built.result.status, 0, built.result.stderr);
    assert(!built.result.error && !built.result.signal && !built.writeFailure);
    const actual = evidence.capture(join(scratch.path, 'read-statement'), args,
      {timeout: 20000, killSignal: 'SIGTERM', maxBuffer: 2 * 1024 * 1024}, result => {
        const matches = [...(result.stdout ?? '').matchAll(/^.+: PASS$/gm)];
        const valid = result.status === 0 && !result.signal && !result.error &&
          matches.length === expected && (result.stdout ?? '').includes(`Physical read statement C cases: ${expected}/${expected}`);
        return {status: valid ? 0 : 1, counts: {tests: matches.length,
          passed: valid ? expected : 0, failed: valid ? 0 : matches.length,
          cancelled: 0, skipped: 0, todo: 0}};
      });
    process.stdout.write(actual.result.stdout ?? '');
    process.stderr.write(actual.result.stderr ?? '');
    assert.equal(actual.result.status, 0);
    assert(!actual.result.error && !actual.result.signal && !actual.writeFailure);
    assert.equal(actual.checked.status, 0);
    assert.equal(actual.checked.counts.tests, expected);
    evidence.finish('passed');
    assert(evidence.summary.complete);
    scratch.passed();
  } catch (error) {
    evidence.finish('failed');
    throw error;
  }
}

test('physical journal reads reuse one finite original-Database statement and retain checked close',
  () => checkFixture([], 1));

test('physical journal statement reset errors limits transactions and pending close retain original semantics',
  () => checkFixture(['controls'], 8));

test('finite read statement keeps exact row admission and private selected ABI bindings', () => {
  const source = readFileSync(new URL('../src/platform_native/sqlite/sqlite_stub.c', import.meta.url), 'utf8');
  const start = source.indexOf('static int32_t actql_database_read(');
  const row = source.indexOf('  int32_t result = actql_bind_key(', start);
  const end = source.indexOf('  int finalize_code', row);
  assert.equal(createHash('sha256').update(source.slice(row, end)).digest('hex'),
    '68d5f9ee07f0d524a8cd4a17eedbb7561bee5df9be85d40aa449f3e365de0cb1',
    'Both original bindings, step, extent/revision/type and all row/body limits stay exact');
  assert.match(source, /bool reusable = !exact_extent && database->library->reset != NULL &&\n    database->library->clear_bindings != NULL/u);
  assert.equal([...source.matchAll(/sqlite3_stmt \*record_read_statement;/gu)].length, 1);
  const api = readFileSync(new URL('../packages/python-local-runtime/native/sqlite-component/api.h', import.meta.url), 'utf8');
  const selected = readFileSync(new URL('../src/platform_native/sqlite/sqlite_selected_component.inc', import.meta.url), 'utf8');
  assert.match(api, /#define ACTQL_SQLITE_COMPONENT_ABI 3/u);
  assert.match(selected, /api->abi != ACTQL_SQLITE_COMPONENT_ABI/u);
  assert.match(selected, /api->bytes != sizeof\(\*api\)/u);
  for (const port of ['reset', 'clear_bindings']) {
    assert(selected.includes(`api->${port} == NULL`));
    assert(selected.includes(`(void *)api->${port}`), 'Every added port retains actual module-origin validation');
    assert(selected.includes(`library->${port} = api->${port};`));
    assert(source.includes(`!ACTQL_LOAD(library, ${port}, "sqlite3_${port}")`));
  }
});
