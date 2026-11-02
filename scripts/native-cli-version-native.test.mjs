// Focused matching Native C/stdlib mechanism only; no full CLI/Host/normal supplier.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {prepareNativeVersionCompiler, observeNativePackageVersion} from './native-cli-version.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
const repository=fileURLToPath(new URL('../',import.meta.url));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');

test('Native package version: actual compiled getter uses immutable bounded literals and ignores runtime version inputs', async () => {
  const moon = resolve(process.env.MOON_HOME ?? ''); assert(process.env.MOON_HOME, 'Select the pinned Native toolchain');
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-version-c-',
    label: 'Native version C mechanism, not full CLI', preserve: true});
  const fixture = join(scratch.path, 'fixture.c');
  await writeFile(fixture, '#include "moonbit.h"\n#include <assert.h>\n#include <stdio.h>\n' +
    'extern moonbit_string_t actql_native_client_package_version(void);\n' +
    'int main(void){moonbit_string_t s=actql_native_client_package_version();int n=Moonbit_array_length(s);' +
    'assert(n>0&&n<=128);for(int i=0;i<n;i++){assert(s[i]>32&&s[i]<127);putchar((char)s[i]);}' +
    'putchar(10);moonbit_decref(s);return 0;}\n');
  const records = [], stub = join(repository, 'src/cmd/native_client/version_stub.c');
  const command = (program, args, env = process.env) => {
    const result = spawnSync(program, args, {cwd: repository, env, encoding: 'utf8', timeout: 20000, maxBuffer: 1024 * 1024});
    records.push({program, args, code: result.status, signal: result.signal, stdout: result.stdout, stderr: result.stderr, error: result.error?.code ?? null});
    assert.ifError(result.error); assert.equal(result.signal, null); return result;
  };
  const common = ['-std=c11', '-O0', '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC', `-I${join(moon, 'include')}`];
  for (const [index, value] of [undefined, '0.0.7-rc.1', '0.0.7', '0.0.' + '1'.repeat(124), '0.0.7\n', '0.0.' + '1'.repeat(125)].entries()) {
    const object = join(scratch.path, `version-${index}.o`), executable = join(scratch.path, `version-${index}`);
    const base = [...common, '-c', stub, '-o', object]; let compiler = 'cc', args = base;
    if (index === 1) {
      const shim = await prepareNativeVersionCompiler(join(scratch.path, 'compiler'), repository, value);
      compiler = shim.path;
    } else if (value !== undefined) args = [...base, `-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION=${JSON.stringify(value)}`];
    const built = command(compiler, args);
    if (index === 5) {assert.notEqual(built.status, 0); continue;}
    assert.equal(built.status, 0, built.stderr);
    const linked = command('cc', [...common, fixture, object, join(moon, 'lib/runtime/runtime.c'),
      join(moon, 'lib/runtime/backtrace.c'), join(moon, 'lib/libmoonbitrun.o'), '-lm', '-o', executable]);
    assert.equal(linked.status, 0, linked.stderr);
    const observed = command(executable, ['--version'], {...process.env, ACTQL_NATIVE_CLIENT_PACKAGE_VERSION: '9.9.9', ACTQL_VERSION: '9.9.9'});
    if (index === 4) {assert.equal(observed.status, 2); assert.equal(observed.stdout, ''); continue;}
    assert.equal(observed.status, 0, observed.stderr); assert.equal(observed.stdout, `${value ?? '0.0.0-development'}\n`);
    if (value !== undefined) assert.equal(observeNativePackageVersion(executable, value).stdout, `${value}\n`);
  }
  await writeFile(join(scratch.path, 'commands.json'), JSON.stringify({qualification: 'C/O0/pinned stdlib getter only; no complete CLI/Host/profile acceptance',
    stubSha256: sha(await readFile(stub)), records}, null, 2) + '\n');
  await scratch.passed();
});
