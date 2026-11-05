// Inputs for the existing selected-provider cases. Every call populates one
// fresh per-case namespace; initialized backing and Store state are never reused.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {closeSync, fstatSync, ftruncateSync, mkdirSync, openSync, realpathSync,
  statSync} from 'node:fs';
import {isAbsolute, join} from 'node:path';

const namedBackingFiles = Object.freeze([
  'initialization-original.backing', 'initialization-budget-refused.backing',
  'consumer-current.backing', 'consumer-managed-graph.backing',
  'consumer-alias.backing', 'consumer-usage-alias.backing',
  'consumer-serial.backing', 'consumer-entry-first.backing',
  'consumer-entry-second.backing', 'consumer-leave-refused.backing',
  'consumer-serial-alias.backing', 'root-binding-first.backing',
  'root-binding-second.backing',
]);

export function nativeCoreScopedFixture(namespace, {cryptoLibrary, sqliteLibrary, backingPages}) {
  for (const library of [cryptoLibrary, sqliteLibrary]) {
    assert(typeof library === 'string' && isAbsolute(library) && !library.includes('\0'),
      'An actual absolute component library selection is required');
  }
  // These are the authored physical fixture declarations, not selected product
  // limits. Crypto's original parent uses 8192 pages; retained/Store uses 256.
  assert(backingPages === 256 || backingPages === 8192, 'An exact authored backing size is required');
  const page = Number(execFileSync('/usr/bin/getconf', ['PAGESIZE'],
    {encoding: 'utf8', timeout: 5000, maxBuffer: 65536}).trim());
  assert(Number.isSafeInteger(page) && page > 0, 'Actual Native page size required');
  const root = join(realpathSync(namespace), 'installed-process');
  mkdirSync(root, {mode: 0o700});
  assert.equal(statSync(root).mode & 0o777, 0o700, 'Private installed-process fixture required');
  const backing = (name, pages) => {
    const fd = openSync(join(root, name), 'wx', 0o600);
    try {
      ftruncateSync(fd, pages * page);
      const stat = fstatSync(fd);
      assert.equal(stat.mode & 0o777, 0o600, 'Private original backing required');
      assert.equal(stat.size, pages * page, 'Exact original backing capacity required');
    } finally { closeSync(fd); }
  };
  backing('backing', backingPages);
  for (const probe of [0, 3, 4]) backing('backing-' + probe, 256);
  for (const name of namedBackingFiles) backing(name, 64);
  mkdirSync(join(root, 'store'), {mode: 0o700});
  assert.equal(statSync(join(root, 'store')).mode & 0o777, 0o700);
  return {
    ACTQL_TEST_INSTALLED_PROCESS_ROOT: root,
    ACTQL_TEST_CRYPTO_COMPONENT: cryptoLibrary,
    ACTQL_TEST_SQLITE_COMPONENT: sqliteLibrary,
  };
}
