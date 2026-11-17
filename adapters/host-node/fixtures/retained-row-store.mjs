import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, readFile, readdir} from 'node:fs/promises';
import {join} from 'node:path';

const rowWire = rows => JSON.stringify(rows, (_key, value) => {
  if (value === null || Array.isArray(value) || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0));
});
const cid = wire => `sha256:${createHash('sha256').update(wire).digest('hex')}`;

// Observe the existing post-physical-acceptance hooks. File names select no
// execution authority: the independent oracle reads bytes only after seal ACK,
// before the original writer binds its real generation for downstream reads.
export function createRetainedRowStoreProbe(directory) {
  const namespace = join(directory, 'carrier-snapshots');
  const seen = new Set(), appends = [], seals = [];
  let outputs;
  const checkpoint = () => ({appends: appends.length, seals: seals.length});
  return {
    checkpoint,
    observe(step, detail) {
      if (step === 'computed') outputs = detail.outputRepresentations;
    },
    async faultInjection(step, detail) {
      if (step === 'local_retained_output_appended') {
        assert.ok(BigInt(detail.admittedWriteBytes) > 0n);
        appends.push(detail);
      }
      if (step !== 'local_retained_output_sealed') return;
      assert.ok(BigInt(detail.sealedBytes) > 0n);
      assert.ok(BigInt(detail.reservedBytes) >= BigInt(detail.sealedBytes));
      const fresh = [];
      for (const lease of await readdir(namespace)) {
        const leasePath = join(namespace, lease);
        assert.ok((await lstat(leasePath)).isDirectory());
        for (const name of await readdir(leasePath)) {
          const path = join(leasePath, name);
          if (seen.has(path)) continue;
          const stat = await lstat(path);
          assert.ok(stat.isFile());
          const wire = await readFile(path);
          assert.equal(wire.length, Number(detail.sealedBytes));
          fresh.push({cid: cid(wire), bytes: wire.length, rows: JSON.parse(wire)});
          seen.add(path);
        }
      }
      assert.equal(fresh.length, 1, 'one original sealed Store generation per ACK');
      seals.push(fresh[0]);
    },
    assertCompleted(rows, {since = {appends: 0, seals: 0}, minimum = 1} = {}) {
      assert.ok(Array.isArray(outputs) && outputs.length > 0);
      assert.ok(outputs.every(item => item.representation === 'retained-file'));
      assert.equal(new Set(outputs.map(item => item.task)).size, outputs.length);
      const current = seals.slice(since.seals);
      assert.equal(current.length, outputs.length);
      if (rows.length > 0) assert.ok(appends.length > since.appends);
      const wire = rowWire(rows), expectedCid = cid(wire);
      const matching = current.filter(body => body.cid === expectedCid);
      assert.ok(matching.length >= minimum, JSON.stringify({expectedCid, actual: current}));
      for (const body of matching) {
        assert.equal(body.bytes, Buffer.byteLength(wire));
        assert.deepEqual(body.rows, rows);
      }
    },
    assertUnchanged(original) {assert.deepEqual(checkpoint(), original);},
    async assertReclaimed() {assert.deepEqual(await readdir(namespace), []);},
  };
}
