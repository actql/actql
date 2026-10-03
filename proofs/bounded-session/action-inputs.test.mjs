import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { compareManifests, domain, encode, inventoryAction, keyForInputs, parseManifest, serializeManifest, validateManifest } from './action-inputs.mjs';
const directory = fileURLToPath(new URL('.', import.meta.url));
const revisionA = '1'.repeat(40), revisionB = '2'.repeat(40);
function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-action-inputs-')));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const model = join(root, 'proofs/bounded-session'), distribution = join(root, 'lean-4.30.0-rc1-linux');
  mkdirSync(model, { recursive: true }); mkdirSync(join(distribution, 'bin'), { recursive: true });
  mkdirSync(join(distribution, 'lib/lean'), { recursive: true });
  for (const name of ['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain']) copyFileSync(join(directory, name), join(model, name));
  // Fixtures model bytes, never claim to be a Lean compiler or a proof pass.
  for (const name of ['Init.olean', 'Lean.olean']) writeFileSync(join(distribution, 'lib/lean', name), `fixture ${name}`);
  const lean = join(distribution, 'bin/lean'), node = join(root, 'node');
  writeFileSync(lean, '#!/bin/sh\necho 4.30.0-rc1\n', { mode: 0o755 });
  writeFileSync(node, 'node executable fixture', { mode: 0o755 });
  const env = { PATH: join(distribution, 'bin'), LANG: 'C.UTF-8', HOME: root };
  const options = { root, executable: node, env, sourceRevision: revisionA };
  return { root, model, distribution, lean, node, env, report: extra => inventoryAction({ ...options, ...extra }) };
}
function unknown(report, pattern) {
  assert.equal(report.coverage.status, 'unknown'); assert.equal(report.coverage.eligibleForReuse, false);
  assert(report.coverage.unresolved.some(reason => pattern.test(reason)), report.coverage.unresolved.join('\n'));
}

test('independent UTF-8 encoding and domain-separated SHA-256 vectors', () => {
  // Authored JSON bytes and digests calculated independently with Python's
  // json.dumps + hashlib, not this encoder or generated product expectations.
  const value = { z: [3, 'é', null], a: { x: 'line\n\0', true: true } };
  const expected = '{"a":{"true":true,"x":"line\\n\\u0000"},"z":[3,"é",null]}';
  assert.equal(encode(value), expected);
  assert.equal(createHash('sha256').update(domain + encode(value)).digest('hex'), '4451581028026248d9a691ef4da7f2f36afd39752e77552d52742170175bbb9d');
  assert.equal(keyForInputs({ files: [], value: 'µ', environment: [] }), '947239cd04cc0aa12a5bca77b68f980f136ede7b9038a3c51bbe7f3a4bdfb9d9');
  assert.notEqual(createHash('sha256').update(expected).digest('hex'), '4451581028026248d9a691ef4da7f2f36afd39752e77552d52742170175bbb9d');
  for (const invalid of [undefined, NaN, 1.5, -0, '\ud800', new Date(), [,,]]) assert.throws(() => encode(invalid));
});

test('captures original theorem, typed Claims and generated axiom stdin bytes', t => {
  const f = fixture(t), report = f.report();
  const model = readFileSync(join(f.model, 'Session.lean'), 'utf8'), claims = readFileSync(join(f.model, 'Claims.lean'), 'utf8');
  const names = ['delta_reconstructs', 'delta_bounded', 'charges_telescope', 'consumed_token_rejected',
    'foreign_owner_rejected', 'terminal_cannot_resume', 'pending_result_keeps_state', 'reclaim_preserves_completed',
    'changed_is_not_completion', 'terminal_poll_closes', 'cleanup_preserves_outcome', 'running_cannot_reclaim',
    'cleanup_completed_stays_completed', 'provider_accounting_instance'];
  assert.deepEqual(report.inputs.generated.theorems, names); assert.deepEqual(report.inputs.generated.imports, ['Lean']);
  const audit = names.map(name => `#print axioms BoundedSession.${name}`).join('\n');
  assert.equal(report.inputs.generated.typedClaims, claims); assert.equal(report.inputs.commands[2].stdin, `${model}\n${claims}\n${audit}\n`);
  assert.deepEqual(report.inputs.commands.map(command => command.args), [
    ['proofs/bounded-session/check.mjs'], ['--short-version'], ['-DwarningAsError=true', '--stdin'],
  ]);
  assert(report.inputs.files.some(entry => entry.path === f.lean && entry.digest));
  assert(report.inputs.files.some(entry => entry.path === join(f.distribution, 'lib/lean/Lean.olean') && entry.digest));
  for (const reason of [/runtime-boundary/, /distribution-boundary/, /environment-boundary/]) unknown(report, reason);
  assert(!report.coverage.unresolved.some(reason => /unrecognized source/.test(reason)));
  assert.deepEqual(parseManifest(serializeManifest(report)), report);
});

for (const name of ['Session.lean', 'Claims.lean', 'check.mjs', 'lean-toolchain']) test(`${name} bytes invalidate key and retain unknown coverage`, t => {
  const f = fixture(t), before = f.report(), path = join(f.model, name);
  writeFileSync(path, `${readFileSync(path)}\n-- changed input\n`);
  const after = f.report(); assert.notEqual(after.actionKey, before.actionKey);
  assert.equal(compareManifests(before, after).inputEquality, 'changed'); unknown(after, /unrecognized/);
});

test('same displayed version cannot mask changed executable or distribution bytes', t => {
  const f = fixture(t), before = f.report();
  writeFileSync(f.lean, '#!/bin/sh\n# replaced executable\necho 4.30.0-rc1\n');
  const binary = f.report(); assert.notEqual(binary.actionKey, before.actionKey);
  writeFileSync(join(f.distribution, 'lib/lean/Lean.olean'), 'different distribution');
  const library = f.report(); assert.notEqual(library.actionKey, binary.actionKey);
  writeFileSync(f.node, 'different node bytes'); assert.notEqual(f.report().actionKey, library.actionKey);
});

test('environment and absent versus empty values affect key without disclosing values', t => {
  const f = fixture(t), before = f.report();
  for (const name of ['LEAN_PATH', 'LEAN_SYSROOT', 'LD_PRELOAD', 'NODE_OPTIONS', 'LANG']) {
    const report = f.report({ env: { ...f.env, [name]: 'private-value' } });
    assert.notEqual(report.actionKey, before.actionKey); assert(!serializeManifest(report).includes('private-value'));
  }
  assert.notEqual(f.report({ env: { ...f.env, LEAN_PATH: '' } }).actionKey, before.actionKey);
  assert.equal(f.report({ env: Object.fromEntries(Object.entries(f.env).reverse()) }).actionKey, before.actionKey);
  const unmodelled = f.report({ env: { ...f.env, PRIVATE_ACCESS_TOKEN: 'guessable-secret' } });
  const text = serializeManifest(unmodelled);
  for (const sensitive of ['PRIVATE_ACCESS_TOKEN', 'guessable-secret', createHash('sha256').update('guessable-secret').digest('hex')]) assert(!text.includes(sensitive));
  unknown(unmodelled, /environment-boundary/);
  assert.equal(compareManifests(before, unmodelled).eligibleForReuse, false);
});

test('documentation and explicit provenance changes do not alter execution inputs/key', t => {
  const f = fixture(t), before = f.report(); writeFileSync(join(f.root, 'README.md'), 'unrelated documentation');
  const after = f.report({ sourceRevision: revisionB }); assert.deepEqual(after.inputs, before.inputs); assert.equal(after.actionKey, before.actionKey);
  const comparison = compareManifests(before, after);
  assert.equal(comparison.inputEquality, 'equal'); assert.equal(comparison.provenanceChanged, true);
  assert.equal(comparison.status, 'unknown'); assert.equal(comparison.eligibleForReuse, false);
});

test('unordered inventory is stable; argument order, modes and paths remain significant', t => {
  const f = fixture(t), before = f.report(), reordered = structuredClone(before);
  reordered.inputs.files.reverse(); reordered.inputs.environment.reverse();
  assert.equal(keyForInputs(reordered.inputs), before.actionKey); assert.equal(compareManifests(before, reordered).inputEquality, 'equal');
  assert.notEqual(f.report({ args: ['--no-warnings', 'proofs/bounded-session/check.mjs'] }).actionKey, before.actionKey);
  chmodSync(join(f.model, 'Session.lean'), 0o600); assert.notEqual(f.report().actionKey, before.actionKey);
  const path = structuredClone(before.inputs); path.paths.cwd += '/different'; assert.notEqual(keyForInputs(path), before.actionKey);
  const order = structuredClone(before.inputs); order.commands[2].args.reverse(); assert.notEqual(keyForInputs(order), before.actionKey);
});

for (const name of ['Session.lean', 'Claims.lean', 'check.mjs', 'lean-toolchain']) test(`missing ${name} is explicit unknown`, t => {
  const f = fixture(t); rmSync(join(f.model, name)); const report = f.report(); unknown(report, /missing regular source/);
  assert(report.inputs.files.some(entry => entry.path === join(f.model, name) && entry.kind === 'unknown'));
});

test('new imports, registry reads, dynamic reads and enumerations fail closed', t => {
  const f = fixture(t), model = join(f.model, 'Session.lean'), checker = join(f.model, 'check.mjs');
  writeFileSync(model, `import NewDependency\n${readFileSync(model)}`); unknown(f.report(), /unrecognized import/);
  const initial = readFileSync(checker);
  for (const addition of ["readFileSync(process.env.INPUT);", "readdirSync('.');", "import './registry.mjs';", "await import(process.env.MODULE);"]) {
    writeFileSync(checker, `${initial}\n${addition}\n`); unknown(f.report(), /unrecognized source structure: check.mjs/);
  }
});

test('new distribution entries are discovered without trusting an old file list', t => {
  const f = fixture(t), before = f.report(); writeFileSync(join(f.distribution, 'lib/lean/New.olean'), 'new bytes');
  const after = f.report(); assert.notEqual(after.actionKey, before.actionKey);
  assert(compareManifests(before, after).changes.some(change => change.name?.endsWith('New.olean') && change.change === 'added'));
  rmSync(join(f.distribution, 'lib/lean/Lean.olean')); unknown(f.report(), /missing Lean distribution input/);
});

test('same-byte symlink substitution and directory links are unknown', t => {
  const f = fixture(t), before = f.report(), model = join(f.model, 'Session.lean');
  renameSync(model, `${model}.real`); symlinkSync(`${model}.real`, model);
  const after = f.report(); assert.notEqual(after.actionKey, before.actionKey); unknown(after, /symlink/);
  const lib = join(f.distribution, 'lib/lean'); renameSync(lib, `${lib}.real`); symlinkSync(`${lib}.real`, lib); unknown(f.report(), /symlink/);
});

test('executable symlink retains target and resolved executable bytes', t => {
  const f = fixture(t), before = f.report(); renameSync(f.lean, `${f.lean}.real`); symlinkSync(`${f.lean}.real`, f.lean);
  const after = f.report(); assert.notEqual(after.actionKey, before.actionKey); unknown(after, /symlink/);
  assert.equal(after.inputs.paths.leanReal, `${f.lean}.real`);
  assert(after.inputs.files.some(entry => entry.path === `${f.lean}.real` && entry.digest));
});

test('relative and empty PATH components preserve action cwd semantics', t => {
  const f = fixture(t); copyFileSync(f.lean, join(f.model, 'lean')); chmodSync(join(f.model, 'lean'), 0o755);
  const empty = f.report({ env: { PATH: '' } }), relative = f.report({ env: { PATH: '.' } });
  assert.equal(empty.inputs.paths.lean, join(f.model, 'lean')); assert.equal(relative.inputs.paths.lean, join(f.model, 'lean'));
  assert.notEqual(empty.actionKey, relative.actionKey); unknown(f.report({ env: {} }), /PATH is absent/);
});

test('special inputs are reported without opening a FIFO', t => {
  const f = fixture(t), path = join(f.model, 'Claims.lean'); rmSync(path);
  assert.equal(spawnSync('mkfifo', [path]).status, 0); const report = f.report(); unknown(report, /nonregular input/);
  assert(report.inputs.files.some(entry => entry.path === path && entry.kind === 'special'));
});

test('unknown schemas, keys, fields and forged reuse claims are refused', t => {
  const f = fixture(t), valid = f.report();
  for (const mutate of [
    m => { m.schema = 'unknown'; }, m => { m.inputs.files[0].kind = 'socket'; }, m => { m.inputs.newField = true; },
    m => { m.inputs.files.push(m.inputs.files[0]); }, m => { m.inputs.environment.push(m.inputs.environment[0]); },
    m => { m.actionKey = '0'.repeat(64); }, m => { m.coverage.eligibleForReuse = true; }, m => { m.coverage.unresolved = []; },
    m => { delete m.inputs.commands; }, m => { m.provenance.sourceRevision = 'branch-name'; },
    m => { m.inputs.files = []; m.actionKey = keyForInputs(m.inputs); },
  ]) {
    const invalid = structuredClone(valid); mutate(invalid); assert.throws(() => validateManifest(invalid));
    assert.equal(compareManifests(valid, invalid).inputEquality, 'unknown'); assert.equal(compareManifests(valid, invalid).eligibleForReuse, false);
  }
  for (const bytes of ['{"schema":"bad","schema":"also-bad"}\n', `${serializeManifest(valid)} `, 'not JSON']) assert.throws(() => parseManifest(bytes));
});

test('CLI comparison requires two explicit manifests and malformed input refuses', t => {
  const f = fixture(t), left = join(f.root, 'left.json'), right = join(f.root, 'right.json');
  writeFileSync(left, serializeManifest(f.report())); writeFileSync(right, serializeManifest(f.report({ sourceRevision: revisionB })));
  const cli = join(directory, 'action-inputs.mjs');
  const valid = spawnSync(process.execPath, [cli, 'compare', left, right], { encoding: 'utf8' });
  assert.equal(valid.status, 0); assert.equal(JSON.parse(valid.stdout).inputEquality, 'equal');
  writeFileSync(right, '{bad');
  const invalid = spawnSync(process.execPath, [cli, 'compare', left, right], { encoding: 'utf8' });
  assert.equal(invalid.status, 1); assert.equal(JSON.parse(invalid.stdout).status, 'unknown');
  const missing = spawnSync(process.execPath, [cli, 'compare', left], { encoding: 'utf8' });
  assert.equal(missing.status, 1); assert.equal(JSON.parse(missing.stdout).eligibleForReuse, false);
});

test('bounded manifest reader rejects links, FIFOs, oversized files and in-read growth', t => {
  const f = fixture(t), regular = join(f.root, 'manifest.json'), link = join(f.root, 'link.json'), fifo = join(f.root, 'fifo.json');
  writeFileSync(regular, serializeManifest(f.report())); symlinkSync(regular, link);
  assert.equal(spawnSync('mkfifo', [fifo]).status, 0);
  const cli = join(directory, 'action-inputs.mjs');
  for (const path of [link, fifo]) {
    const result = spawnSync(process.execPath, [cli, 'compare', path, regular], { encoding: 'utf8', timeout: 2000 });
    assert.ifError(result.error); assert.equal(result.status, 1); assert.match(result.stdout, /regular file/);
  }
  // Subprocess-local fs instrumentation grows a two-byte file after fstat but
  // before read. It also independently checks the expected-size+1 read bound.
  writeFileSync(regular, '{}');
  const script = `
    import fs from 'node:fs'; import { syncBuiltinESMExports } from 'node:module';
    import { readManifestFile } from ${JSON.stringify(new URL('./action-inputs.mjs', import.meta.url).href)};
    const path = ${JSON.stringify(regular)}, original = fs.readSync;
    fs.readSync = function(fd, buffer, offset, length, ...rest) {
      if (length !== 3) throw new Error('UNBOUNDED_READ');
      fs.appendFileSync(path, Buffer.alloc(1024 * 1024));
      return original(fd, buffer, offset, length, ...rest);
    }; syncBuiltinESMExports();
    try { readManifestFile(path); process.exit(10); } catch (error) {
      if (error.message !== 'Input grew during read') throw error;
    }
  `;
  const growth = spawnSync(process.execPath, ['--input-type=module', '--eval', script], { encoding: 'utf8', timeout: 2000 });
  assert.ifError(growth.error); assert.equal(growth.status, 0, growth.stderr);
  // Sparse oversized input is rejected from stat before attempting allocation.
  const oversized = spawnSync(process.execPath, ['--input-type=module', '--eval', `
    import { truncateSync } from 'node:fs';
    import { readManifestFile } from ${JSON.stringify(new URL('./action-inputs.mjs', import.meta.url).href)};
    truncateSync(${JSON.stringify(regular)}, 33 * 1024 * 1024);
    try { readManifestFile(${JSON.stringify(regular)}); process.exit(10); }
    catch (error) { if (!error.message.includes('32 MiB')) throw error; }
  `], { encoding: 'utf8', timeout: 2000 });
  assert.ifError(oversized.error); assert.equal(oversized.status, 0, oversized.stderr);
});

test('unrecognized executable prefix is not recursively inventoried', t => {
  const f = fixture(t), generic = join(f.root, 'generic-prefix'); renameSync(f.distribution, generic);
  const report = f.report({ env: { ...f.env, PATH: join(generic, 'bin') } });
  unknown(report, /distribution root unresolved/);
  assert(!report.inputs.files.some(entry => entry.path === join(generic, 'lib/lean/Lean.olean')));
});
