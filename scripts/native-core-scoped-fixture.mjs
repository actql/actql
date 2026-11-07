// Inputs for the existing selected-provider cases. Every call populates one
// fresh per-case namespace; initialized backing and Store state are never reused.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {closeSync, fstatSync, ftruncateSync, mkdirSync, openSync, realpathSync,
  statSync, writeFileSync} from 'node:fs';
import {isAbsolute, join} from 'node:path';

const namedBackingFiles = Object.freeze([
  'initialization-original.backing', 'initialization-budget-refused.backing',
  'request-original.backing', 'request-run-transfer.backing', 'request-unstarted.backing',
  'common-request-entrance.backing',
  'source-frame-original.backing', 'source-frame-left.backing', 'source-frame-right.backing',
  'consumer-current.backing', 'consumer-managed-graph.backing',
  'consumer-alias.backing', 'consumer-usage-alias.backing',
  'consumer-serial.backing', 'consumer-entry-first.backing',
  'consumer-entry-second.backing', 'consumer-leave-refused.backing',
  'consumer-serial-alias.backing', 'consumer-working-growth.backing', 'root-binding-first.backing',
  'root-binding-second.backing',
]);

const ordinaryBackingFiles = Object.freeze([
  'initial-domain.backing', 'installed-process-prepared.backing',
  'installed-process-closing.backing', 'installed-process-foreign.backing',
  'installed-process-small-envelope.backing', 'installed-process-capture-refusal.backing',
  'installed-process-known-spawn-refusal.backing', 'installed-process-captured-descriptor.backing',
  'installed-process-stopped-child.backing',
  'installed-child-byte-transport.backing',
  'installed-child-stop-request.backing',
  'installed-child-stop-preflight.backing',
  'installed-child-fd4.backing',
  'installed-child-known-failure.backing',
  'installed-child-preflight.backing',
]);

// Ordinary process/domain cases use file-backed input without selecting an
// allocation provider or component library. Slot files are created by the case.
export function nativeCoreOrdinaryProcessFixture(namespace) {
  const {root, backing} = backingFixture(namespace);
  for (const name of ordinaryBackingFiles) backing(name, 64);
  return {ACTQL_TEST_INSTALLED_PROCESS_ROOT: root};
}

function backingFixture(namespace) {
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
  return {root, backing};
}

// The Model frame correspondence cases use only the existing real FD-backed
// Request originals. They do not acquire a Crypto or SQLite component, so do
// not select an unrelated library merely to populate an unused environment.
export function nativeCoreModelFrameFixture(namespace) {
  const {root, backing} = backingFixture(namespace);
  for (const name of ['source-frame-original', 'source-frame-left', 'source-frame-right']) {
    backing(name + '.backing', 64);
  }
  return {ACTQL_TEST_INSTALLED_PROCESS_ROOT: root};
}

export function nativeCoreScopedFixture(namespace, {cryptoLibrary, sqliteLibrary, backingPages}) {
  for (const library of [cryptoLibrary, sqliteLibrary]) {
    assert(typeof library === 'string' && isAbsolute(library) && !library.includes('\0'),
      'An actual absolute component library selection is required');
  }
  // These are the authored physical fixture declarations, not selected product
  // limits. Crypto's original parent uses 8192 pages; retained/Store uses 256.
  assert(backingPages === 256 || backingPages === 8192, 'An exact authored backing size is required');
  const {root, backing} = backingFixture(namespace);
  backing('backing', backingPages);
  for (const probe of [0, 3, 4]) backing('backing-' + probe, 256);
  for (const probe of [0, 1, 2]) backing('extent-backing-' + probe, 256);
  for (const name of namedBackingFiles) backing(name, 64);
  mkdirSync(join(root, 'store'), {mode: 0o700});
  assert.equal(statSync(join(root, 'store')).mode & 0o777, 0o700);
  return {
    ACTQL_TEST_INSTALLED_PROCESS_ROOT: root,
    ACTQL_TEST_CRYPTO_COMPONENT: cryptoLibrary,
    ACTQL_TEST_SQLITE_COMPONENT: sqliteLibrary,
  };
}

// Independent finite input for the relation-file component. The existing Arena
// cases retain their page declarations above; this never changes their profile.
export function nativeRelationFileCaptureFixture(namespace) {
  const root = join(realpathSync(namespace), 'installed-process');
  mkdirSync(root, {mode: 0o700});
  assert.equal(statSync(root).mode & 0o777, 0o700, 'Private capture fixture required');
  const input = Buffer.from('{"items":[{"id":"first","value":1},{"id":"second","value":2}]}');
  const listing = Buffer.from('{"items":[{"id":"first","name":"Acme🌱","version":"label","media_type":"text/plain","body":"first\\nnotes","path":null},{"id":"second","name":"Globex","version":"label","media_type":"text/plain","body":"second notes","path":"notes/globex"}]}');
  const files = [
    ['row-source-input', input],
    ['row-source-large-input', Buffer.concat([input, Buffer.alloc(70000, 0x20)])],
    ['row-source-files', listing],
    ['row-source-malformed', Buffer.from('{"items":[')],
    ['row-source-oversized', 8193],
    ['row-source-backing', 384 * 1024 ** 2],
  ];
  for (const [name, content] of files) {
    const fd = openSync(join(root, name), 'wx', 0o600);
    try {
      if (typeof content === 'number') ftruncateSync(fd, content);
      else writeFileSync(fd, content);
      const stat = fstatSync(fd);
      assert(stat.isFile() && stat.nlink === 1, 'Exclusive regular capture fixture required');
      assert.equal(stat.mode & 0o777, 0o600);
      assert.equal(stat.size, typeof content === 'number' ? content : content.length);
    } finally { closeSync(fd); }
  }
  // This namespace owns files after the test closes its actual physical owner.
  // An interrupted test retains the namespace for diagnosis, never resets it.
  return {ACTQL_TEST_INSTALLED_PROCESS_ROOT: root};
}
