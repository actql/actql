import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, chmodSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {gitTree, readBlobBatch} from './inputs.mjs';

const object = bytes => createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
const record = bytes => Buffer.concat([Buffer.from(`${object(bytes)} blob ${bytes.length}\n`), bytes, Buffer.from('\n')]);

test('Git batch parsing preserves binary, empty and embedded protocol-looking blob bytes', () => {
  const buffers = [Buffer.alloc(0), Buffer.from('line\n'), Buffer.from([0, 255, 10, 13]),
    Buffer.from(`${'a'.repeat(40)} blob 100\nnot another record\n`)];
  const parsed = readBlobBatch(Buffer.concat(buffers.map(record)), buffers.map(object));
  assert.deepEqual([...parsed.values()], buffers);
});

test('Git batch identity, type, length, content, ordering and complete response are required', () => {
  const bytes = Buffer.from('actual\0blob\n'), id = object(bytes), valid = record(bytes);
  for (const output of [
    Buffer.from(`${id} missing\n`),
    Buffer.from(`${id} commit ${bytes.length}\n${bytes}\n`),
    Buffer.from(`${'f'.repeat(40)} blob ${bytes.length}\n${bytes}\n`),
    valid.subarray(0, valid.length - 1),
    Buffer.concat([valid, Buffer.from('extra\n')]),
    Buffer.from(`${id} blob 99999999999999999999\n${bytes}\n`),
    Buffer.from(`${id} blob ${bytes.length}\nsubstitute!\n`),
  ]) assert.throws(() => readBlobBatch(output, [id]));
  const other = Buffer.from('other');
  assert.throws(() => readBlobBatch(Buffer.concat([record(other), valid]), [id, object(other)]));
  assert.throws(() => readBlobBatch(Buffer.concat([valid, valid]), [id, id]));
  assert.throws(() => readBlobBatch(valid, []));
});

test('batched reads use actual immutable Git blobs and modes, including shared bytes and dirty checkout', () => {
  const root = mkdtempSync(join(tmpdir(), 'actql-git-inputs-'));
  const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8',
    env: {...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1'}}).trim();
  try {
    git(['init', '--quiet']);
    const bytes = Buffer.from([0, 255, 10, 13, 0]);
    writeFileSync(join(root, 'one'), bytes); writeFileSync(join(root, 'two'), bytes);
    writeFileSync(join(root, 'empty'), ''); chmodSync(join(root, 'two'), 0o755);
    git(['add', 'one', 'two', 'empty']);
    git(['-c', 'user.name=ActQL fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
      'commit', '--quiet', '-m', 'test: pin binary Git inputs']);
    const revision = git(['rev-parse', 'HEAD']), tree = gitTree(root, revision);
    tree.prefetch(['two', 'empty', 'one']);
    assert.deepEqual(tree.read('one'), bytes); assert.deepEqual(tree.read('two'), bytes);
    assert.equal(tree.entries.get('one').mode, '100644'); assert.equal(tree.entries.get('two').mode, '100755');
    assert.equal(tree.entries.get('one').object, tree.entries.get('two').object);
    assert.equal(tree.read('empty').length, 0);
    writeFileSync(join(root, 'one'), 'uncommitted body');
    assert.deepEqual(gitTree(root, revision).read('one'), bytes);
    assert.throws(() => tree.prefetch(['missing']), /Missing source/u);
  } finally { rmSync(root, {recursive: true}); }
});
