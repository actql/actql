import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {sha256File} from './release-artifacts.mjs';

test('both bounded stream sizes preserve trailing bytes and detect changed content', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-artifact-hash-'));
  try {
    const path = join(directory, 'artifact');
    const bytes = Buffer.alloc(1024 * 1024 + 17, 0xa5); bytes[bytes.length - 1] = 3;
    await writeFile(path, bytes);
    const expected = createHash('sha256').update(bytes).digest('hex');
    for (const size of [64 * 1024, 1024 * 1024]) assert.equal(await sha256File(path, size), expected);
    bytes[bytes.length - 1] = 4; await writeFile(path, bytes);
    for (const size of [64 * 1024, 1024 * 1024]) assert.notEqual(await sha256File(path, size), expected);
    await assert.rejects(sha256File(path, 0), /InvalidArtifactReadChunkBytes/);
    await assert.rejects(sha256File(join(directory, 'absent')), {code: 'ENOENT'});
  } finally {await rm(directory, {recursive: true, force: true});}
});
