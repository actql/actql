// Explicit Native build-system diagnostic. No Host, Run, Store or Provider.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {createOwnedScratch} from './owned-scratch.mjs';

const root = new URL('../', import.meta.url);
const packages = [
  ['host_bootstrap', 'bootstrap_stub.c', ['process_region.h', 'live_channel.h']],
  ['executor_slot', 'executor_slot_stub.c', ['duplex_stub.h', 'child_launch_stub.h']],
];

test('split Native stub bodies are local compiler header inputs', () => {
  for (const [name, stub, headers] of packages) {
    const directory = new URL(`src/platform_native/${name}/`, root);
    const source = readFileSync(new URL(stub, directory), 'utf8');
    for (const header of headers) {
      assert(source.includes(`#include "${header}"`));
      assert(existsSync(new URL(header, directory)));
      assert(!existsSync(new URL(header.replace(/\.h$/u, '.inc'), directory)));
    }
  }
});

test('actual Native incremental build observes a header-only body change', async () => {
  const moonHome = process.env.MOON_HOME;
  assert(moonHome, 'explicit pinned Moon toolchain required');
  const scratch = await createOwnedScratch({parent: new URL('../_build/', import.meta.url).pathname,
    prefix: 'native-header-input-', label: 'Native header input probe',
    digests: () => ['commands.json']});
  const commands = [];
  const run = args => {
    const result = spawnSync(join(moonHome, 'bin/moon'), args, {
      cwd: scratch.path, encoding: 'utf8', timeout: 15000, killSignal: 'SIGTERM',
      maxBuffer: 1024 * 1024, env: process.env,
    });
    commands.push({args, status: result.status, signal: result.signal,
      error: result.error?.code ?? null, stdout: result.stdout, stderr: result.stderr});
    writeFileSync(join(scratch.path, 'commands.json'), JSON.stringify(commands, null, 2) + '\n');
    assert(!result.error, result.error?.message);
    assert.equal(result.signal, null);
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  };
  // This is a fresh compiler fixture, not a replacement product success case.
  writeFileSync(join(scratch.path, 'moon.mod'), 'name = "actql/header_probe"\n');
  writeFileSync(join(scratch.path, 'moon.pkg'),
    'pkgtype(kind: "executable")\noptions("native-stub": ["probe.c"])\n');
  writeFileSync(join(scratch.path, 'main.mbt'),
    'extern "C" fn original_value() -> Int = "actql_header_probe"\nfn main { println(original_value()) }\n');
  writeFileSync(join(scratch.path, 'probe.c'),
    '#include <stdint.h>\n#include "original.h"\nint32_t actql_header_probe(void) { return ORIGINAL_VALUE; }\n');
  const header = join(scratch.path, 'original.h');
  writeFileSync(header, '#define ORIGINAL_VALUE 17\n');
  const args = ['run', '--target', 'native', '-j', '1', '.'];
  assert.equal(run(args), '17');
  const object = join(scratch.path, '_build/native/debug/build/probe.o');
  const digest = () => createHash('sha256').update(readFileSync(object)).digest('hex');
  const original = digest();
  assert.equal(run(args), '17');
  assert.equal(digest(), original, 'unchanged inputs retain the same compiled object');
  // All compiler/module/C/Moon sources and flags remain unchanged. Only this
  // separately discovered header changes between completely reaped commands.
  writeFileSync(header, '#define ORIGINAL_VALUE 29\n');
  assert.equal(run(args), '29');
  assert.notEqual(digest(), original, 'header-only change must rebuild the actual stub');
  scratch.passed();
});


test('Python provider recipe isolates image capture from ordinary bootstrap', () => {
  const result = spawnSync('python3', ['scripts/test_python_native_provider.py', '-v'], {
    cwd: root, encoding: 'utf8', timeout: 60000, killSignal: 'SIGTERM',
    maxBuffer: 1024 * 1024, env: process.env,
  });
  assert(!result.error, result.error?.message);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /Ran [1-9][0-9]* tests/u, 'nonzero Python cases required');
});
