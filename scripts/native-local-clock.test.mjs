import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import {createOwnedScratch} from './owned-scratch.mjs';

test('Native Local UTC FFI preserves millisecond timestamps and rejects unavailable clock or buffer', async () => {
  const scratch = await createOwnedScratch({parent: '/private/tmp', prefix: 'actql-native-local-clock-',
    label: 'Native Local clock FFI counterexamples'});
  const moonHome = process.env.MOON_HOME;
  assert.ok(moonHome, 'Select the repository-pinned Native toolchain explicitly');
  const stub = fileURLToPath(new URL('../src/cmd/native_client/stdout_stub.c', import.meta.url));
  const fixture = join(scratch.path, 'clock.c');
  const executable = join(scratch.path, 'clock');
  // The real FFI formatter consumes independently fixed clock readings. This
  // small C fixture does not build a MoonBit module or produce a CLI artifact.
  await writeFile(fixture, `
#include <sys/time.h>
#include <assert.h>
#include <string.h>
static long seconds;
static int micros, unavailable;
static int fixed_gettimeofday(struct timeval *now, void *unused) {
  (void)unused;
  if (unavailable) return -1;
  now->tv_sec = seconds;
  now->tv_usec = micros;
  return 0;
}
#define gettimeofday fixed_gettimeofday
#include ${JSON.stringify(stub)}
#undef gettimeofday
static void check(long s, int us, const char *expected) {
  unsigned char storage[31];
  memset(storage, 0xaa, sizeof(storage));
  seconds = s; micros = us;
  assert(actql_native_client_utc_now(storage + 3, 25) == 1);
  assert(memcmp(storage + 3, expected, 24) == 0 && storage[27] == 0);
  assert(storage[0] == 0xaa && storage[2] == 0xaa);
  assert(storage[28] == 0xaa && storage[30] == 0xaa);
}
int main(void) {
  check(0, 0, "1970-01-01T00:00:00.000Z");
  check(951782400, 999999, "2000-02-29T00:00:00.999Z");
  check(951868799, 1000, "2000-02-29T23:59:59.001Z");
  unsigned char bytes[25], expected[25];
  memset(bytes, 0xaa, sizeof(bytes)); memcpy(expected, bytes, sizeof(bytes));
  assert(actql_native_client_utc_now(bytes, 24) == 0);
  assert(memcmp(bytes, expected, sizeof(bytes)) == 0);
  unavailable = 1;
  assert(actql_native_client_utc_now(bytes, 25) == 0);
  assert(memcmp(bytes, expected, sizeof(bytes)) == 0);
  return 0;
}
`);
  const compile = spawnSync('/usr/bin/clang', ['-Wall', '-Wextra', '-Werror',
    `-I${join(resolve(moonHome), 'include')}`, fixture,
    join(resolve(moonHome), 'lib/libmoonbitrun.o'), '-o', executable],
  {encoding: 'utf8', timeout: 10000});
  assert.ifError(compile.error);
  assert.equal(compile.status, 0, compile.stderr);
  const run = spawnSync(executable, [], {encoding: 'utf8', timeout: 10000,
    env: {...process.env, TZ: 'Asia/Tokyo'}});
  assert.ifError(run.error);
  assert.equal(run.signal, null);
  assert.equal(run.status, 0, run.stderr);
  await scratch.passed();
});
