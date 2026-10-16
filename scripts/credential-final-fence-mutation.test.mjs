import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));

test('dropping final credential authorization fails the actual post-await revocation assertion', () => {
  const scratch = mkdtempSync(join(tmpdir(), 'credential-final-fence-'));
  try {
    mkdirSync(join(scratch, 'adapters/site-node'), {recursive: true});
    writeFileSync(join(scratch, 'package.json'), '{"type":"module"}\n');
    symlinkSync(join(root, 'adapters/host-common'), join(scratch, 'adapters/host-common'));
    symlinkSync(join(root, '_build'), join(scratch, '_build'));
    for (const name of ['sqlite-credential-journal.mjs', 'remote-credential-signature.mjs',
      'https-exchange-fixture.test.mjs']) symlinkSync(join(root, 'adapters/site-node', name),
        join(scratch, 'adapters/site-node', name));
    copyFileSync(join(root, 'adapters/site-node/https-credential-resource.test.mjs'),
      join(scratch, 'adapters/site-node/https-credential-resource.test.mjs'));
    const source = readFileSync(join(root, 'adapters/site-node/https-credential-resource.mjs'), 'utf8');
    const fence = '    journal.authorize(\n      claimed.use,\n      BigInt(now()),\n      scope,\n      control,\n    );';
    assert.equal(source.split(fence).length, 2, 'Exactly the final current fence is selected');
    writeFileSync(join(scratch, 'adapters/site-node/https-credential-resource.mjs'), source.replace(fence, ''));
    const env = {...process.env};
    // This is a separate test process, not a recursive node:test worker.
    delete env.NODE_TEST_CONTEXT;
    const child = spawnSync(process.execPath, ['--test',
      '--test-name-pattern=^revocation during secret resolution fences the final request',
      'adapters/site-node/https-credential-resource.test.mjs'],
      {cwd: scratch, env, encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024});
    assert.equal(child.error, undefined);
    assert.equal(child.signal, null);
    assert.equal(child.status, 1, child.stdout + child.stderr);
    const output = child.stdout + child.stderr;
    assert.match(output, /Missing expected rejection/u);
    assert.match(output, /# fail 1/u);
    assert.doesNotMatch(output, /ERR_MODULE_NOT_FOUND|SyntaxError|test timed out/u);
  } finally { rmSync(scratch, {recursive: true, force: true}); }
});
