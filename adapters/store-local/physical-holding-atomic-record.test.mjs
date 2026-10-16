// Actual local Store/filesystem and process interruption; protocol admission
// uses the explicit contract-control fixture, not genuine Core or Model grants.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {createHash} from 'node:crypto';
import {readdir, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';
const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

for (const mode of ['empty', 'partial']) {
  test(`interrupted ${mode} holding metadata never becomes a final ownership record`, async t => {
    const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
      prefix: `holding-atomic-${mode}-`, label: 'physical holding interrupted publication', retain: true});
    const directory = join(scratch.path, 'store');
    const child = spawn(process.execPath, [new URL('./fixtures/physical-holding-interrupted.fixture.mjs',
      import.meta.url).pathname, directory, mode], {stdio: ['ignore', 'pipe', 'pipe']});
    const stdout = [], stderr = [];
    child.stdout.on('data', bytes => stdout.push(bytes));
    child.stderr.on('data', bytes => stderr.push(bytes));
    const [code, signal] = await once(child, 'close');
    assert.equal(signal, null);
    assert.equal(code, 77, Buffer.concat(stderr).toString('utf8'));
    const observation = JSON.parse(Buffer.concat(stdout).toString('utf8'));
    assert.equal(observation.boundary, 'holding-record-before-complete-write');
    assert.equal((await readFile(observation.path)).length, mode === 'empty' ? 0 : 11);
    const finalNames = await readdir(join(directory, 'physical-holdings'));
    assert.deepEqual(finalNames, [], 'Only complete bytes may occupy a final holding name');
    const store = await openLocalPublicationStore({directory,
      storeAuthorityCid: cid('atomic holding authority'), capacityBytes: 65536,
      maxObjectBytes: 4096, maxObjects: 8, maxContractNodes: 256, maxContractDepth: 32},
    createPublicationContractControlFixture());
    t.after(async () => { if (!store.status().closed) await store.close(); });
    assert.equal(await store.inspectPhysicalHolding(cid('atomic original holding')), undefined);
    assert.deepEqual(await readdir(join(directory, 'staging')), []);
    await store.close();
    scratch.passed();
  });
}
