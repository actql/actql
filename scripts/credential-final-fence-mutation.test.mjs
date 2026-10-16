import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));

function mutation(transform, pattern, expected) {
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
    const mutated = transform(source);
    assert.notEqual(mutated, source);
    writeFileSync(join(scratch, 'adapters/site-node/https-credential-resource.mjs'), mutated);
    const env = {...process.env};
    // This is a separate test process, not a recursive node:test worker.
    delete env.NODE_TEST_CONTEXT;
    const child = spawnSync(process.execPath, ['--test',
      `--test-name-pattern=${pattern}`,
      'adapters/site-node/https-credential-resource.test.mjs'],
      {cwd: scratch, env, encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024});
    assert.equal(child.error, undefined);
    assert.equal(child.signal, null);
    assert.equal(child.status, 1, child.stdout + child.stderr);
    const output = child.stdout + child.stderr;
    const evidence = mkdtempSync(join(root, '_build/credential-binding-mutation-'));
    writeFileSync(join(evidence, 'stdout.log'), child.stdout);
    writeFileSync(join(evidence, 'stderr.log'), child.stderr);
    writeFileSync(join(evidence, 'inputs.json'), JSON.stringify({pattern,
      sourceSha256: createHash('sha256').update(source).digest('hex'),
      mutantSha256: createHash('sha256').update(mutated).digest('hex'),
      expectedFailure: true, exit: child.status}, null, 2));
    assert.match(output, /# fail 1/u);
    assert.match(output, expected);
    assert.doesNotMatch(output, /ERR_MODULE_NOT_FOUND|SyntaxError|test timed out/u);
  } finally { rmSync(scratch, {recursive: true, force: true}); }
}

test('dropping final credential authorization fails the actual post-await revocation assertion', () => {
  mutation(source => {
    const fence = '    journal.authorize(\n      claimed.use,\n      BigInt(now()),\n      scope,\n      control,\n    );';
    assert.equal(source.split(fence).length, 2);
    return source.replace(fence, '');
  }, '^revocation during secret resolution fences the final request',
    /Missing expected rejection/u);
});

test('dropping retained-material comparison fails the real wrong-account no-send assertion', () => {
  mutation(source => {
    const comparison = /    if \(binding\?\.secret !== undefined && binding\.secret !== currentSecret\) \{\n      binding\.changed = true;\n      fail\('RemoteCredentialBindingChanged'\);\n    \}/u;
    assert.match(source, comparison);
    return source.replace(comparison, '');
  }, '^rotation after identity refuses a replacement token',
    /RemoteCredentialBindingChanged/u);
});

test('acknowledging cleanup before the original call retires fails the pending-custody assertion', () => {
  mutation(source => {
    assert.equal(source.split('state.retiring && !state.active &&').length, 2);
    return source.replace('state.retiring && !state.active &&', 'state.retiring &&');
  }, '^cleanup during resolution retains the same binding',
    /closed[\s\S]*pending/u);
});
