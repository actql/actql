import {createHash, randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {constants} from 'node:fs';
import {
  link,
  mkdir,
  open,
  readdir,
  realpath,
  unlink,
} from 'node:fs/promises';
import {join} from 'node:path';
import {admitSignedRemoteRuntimeBundle} from
  './remote-bundle-signature.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const count = value => Number.isSafeInteger(value) && value >= 0;

function transaction(database, body) {
  database.exec('BEGIN IMMEDIATE');
  try {
    const value = body();
    database.exec('COMMIT');
    return value;
  } catch (error) {
    try { database.exec('ROLLBACK'); }
    catch (rollback) { fail('RemoteBundleStoreRollbackFailed', rollback); }
    throw error;
  }
}

async function syncDirectory(path) {
  const descriptor = await open(path, 'r');
  try { await descriptor.sync(); }
  finally { await descriptor.close(); }
}

const localDurability = Object.freeze({
  remove: unlink,
  syncDirectory,
});

async function digestFile(path, expectedBytes, expectedCid) {
  const descriptor = await open(
    path,
    constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0),
  );
  try {
    const information = await descriptor.stat();
    if (!information.isFile() || BigInt(information.size) !== expectedBytes) {
      fail('RemoteBundleComponentMismatch');
    }
    const hash = createHash('sha256');
    const buffer = Buffer.allocUnsafe(65_536);
    let offset = 0;
    while (offset < information.size) {
      const {bytesRead} = await descriptor.read(
        buffer,
        0,
        Math.min(buffer.length, information.size - offset),
        offset,
      );
      if (bytesRead === 0) fail('RemoteBundleComponentChanged');
      hash.update(buffer.subarray(0, bytesRead));
      offset += bytesRead;
    }
    if (`sha256:${hash.digest('hex')}` !== expectedCid) {
      fail('RemoteBundleComponentMismatch');
    }
    return information;
  } finally {
    await descriptor.close();
  }
}

async function copyComponent(sourcePath, stagingPath, expectedBytes,
  expectedCid) {
  const source = await open(
    sourcePath,
    constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0),
  );
  let destination;
  try {
    const information = await source.stat();
    if (!information.isFile() || BigInt(information.size) !== expectedBytes) {
      fail('RemoteBundleComponentMismatch');
    }
    destination = await open(
      stagingPath,
      constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY |
        (constants.O_NOFOLLOW ?? 0),
      0o500,
    );
    const hash = createHash('sha256');
    const buffer = Buffer.allocUnsafe(65_536);
    let offset = 0;
    while (offset < information.size) {
      const {bytesRead} = await source.read(
        buffer,
        0,
        Math.min(buffer.length, information.size - offset),
        offset,
      );
      if (bytesRead === 0) fail('RemoteBundleComponentChanged');
      const chunk = buffer.subarray(0, bytesRead);
      hash.update(chunk);
      let written = 0;
      while (written < bytesRead) {
        const result = await destination.write(
          chunk,
          written,
          bytesRead - written,
          offset + written,
        );
        if (result.bytesWritten === 0) fail('RemoteBundleWriteFailed');
        written += result.bytesWritten;
      }
      offset += bytesRead;
    }
    if (`sha256:${hash.digest('hex')}` !== expectedCid) {
      fail('RemoteBundleComponentMismatch');
    }
    await destination.sync();
  } finally {
    await source.close();
    if (destination !== undefined) await destination.close();
  }
}

export async function openRuntimeBundleStore(root, {
  bundleAuthorities,
  targetTriple,
  maxBundles = 1024,
  maxOwners = 100_000,
  maxComponentBytes = 1_073_741_824n,
} = {}, durability = localDurability) {
  if (!text(root) || !(bundleAuthorities instanceof Map) ||
      bundleAuthorities.size === 0 || !text(targetTriple) ||
      !count(maxBundles) || maxBundles === 0 ||
      !count(maxOwners) || maxOwners === 0 ||
      typeof maxComponentBytes !== 'bigint' || maxComponentBytes < 0n) {
    fail('InvalidRemoteBundleStoreConfiguration');
  }
  if (durability === null || typeof durability !== 'object' ||
      typeof durability.remove !== 'function' ||
      typeof durability.syncDirectory !== 'function') {
    fail('InvalidRemoteBundleStoreDurability');
  }
  const remove = durability.remove;
  const sync = durability.syncDirectory;
  await mkdir(root, {recursive: true, mode: 0o700});
  const directory = await realpath(root);
  const artifacts = join(directory, 'artifacts');
  const staging = join(directory, 'staging');
  await mkdir(artifacts, {recursive: true, mode: 0o700});
  await mkdir(staging, {recursive: true, mode: 0o700});
  const database = new DatabaseSync(join(directory, 'bundles.sqlite3'), {
    open: true,
    readOnly: false,
    enableForeignKeyConstraints: true,
  });
  let closed = false;
  try {
    database.exec('PRAGMA journal_mode = WAL');
    database.exec('PRAGMA synchronous = FULL');
    database.exec(`
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      ) STRICT;
      CREATE TABLE IF NOT EXISTS bundles (
        runtime_bundle_cid TEXT PRIMARY KEY NOT NULL,
        manifest_json TEXT NOT NULL,
        signature_version TEXT NOT NULL,
        signature_key_id TEXT NOT NULL,
        signature TEXT NOT NULL,
        artifact_name TEXT NOT NULL,
        component_cid TEXT NOT NULL,
        component_bytes TEXT NOT NULL,
        record_revision INTEGER NOT NULL CHECK (record_revision >= 0),
        phase INTEGER NOT NULL CHECK (phase BETWEEN 0 AND 3),
        owners INTEGER NOT NULL CHECK (owners >= 0),
        reclaim_pending INTEGER NOT NULL DEFAULT 0
          CHECK (reclaim_pending IN (0, 1))
      ) STRICT;
      CREATE TABLE IF NOT EXISTS bundle_holds (
        hold_id TEXT PRIMARY KEY NOT NULL,
        runtime_bundle_cid TEXT NOT NULL,
        kind TEXT NOT NULL,
        FOREIGN KEY (runtime_bundle_cid)
          REFERENCES bundles(runtime_bundle_cid)
      ) STRICT;
    `);
    transaction(database, () => {
      const version = database.prepare(
        'SELECT value FROM metadata WHERE key = ?',
      ).get('schema_version');
      if (version === undefined) {
        const insert = database.prepare(
          'INSERT INTO metadata (key, value) VALUES (?, ?)',
        );
        insert.run('schema_version', 'actql-runtime-bundle-store/0.1');
        insert.run('active_bundle_cid', '');
      } else if (version.value !== 'actql-runtime-bundle-store/0.1') {
        fail('UnsupportedRemoteBundleStoreVersion');
      }
    });
  } catch (error) {
    database.close();
    throw error;
  }

  const select = database.prepare(
    'SELECT * FROM bundles WHERE runtime_bundle_cid = ?',
  );
  const selectAll = database.prepare('SELECT * FROM bundles ORDER BY rowid');
  const total = database.prepare('SELECT COUNT(*) AS count FROM bundles');
  const activeRow = database.prepare(
    'SELECT value FROM metadata WHERE key = ?',
  );
  const setActive = database.prepare(
    'UPDATE metadata SET value = ? WHERE key = ?',
  );
  const insert = database.prepare(`
    INSERT INTO bundles (
      runtime_bundle_cid, manifest_json, signature_version,
      signature_key_id, signature, artifact_name, component_cid,
      component_bytes, record_revision, phase, owners
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const update = database.prepare(`
    UPDATE bundles SET record_revision = ?, phase = ?, owners = ?
    WHERE runtime_bundle_cid = ? AND record_revision = ? AND phase = ?
      AND owners = ?
  `);
  const selectHold = database.prepare(
    'SELECT * FROM bundle_holds WHERE hold_id = ?',
  );
  const insertHold = database.prepare(`
    INSERT INTO bundle_holds (hold_id, runtime_bundle_cid, kind)
    VALUES (?, ?, ?)
  `);
  const deleteHold = database.prepare(
    'DELETE FROM bundle_holds WHERE hold_id = ?',
  );
  const artifactUsers = database.prepare(`
    SELECT COUNT(*) AS count FROM bundles
    WHERE artifact_name = ? AND phase != 3 AND runtime_bundle_cid != ?
  `);

  const active = () => {
    if (closed) fail('RemoteBundleStoreClosed');
  };
  const requireControl = control => {
    for (const name of [
      'identity', 'json', 'admitJson', 'projection', 'open', 'restore',
      'prepareActivation', 'activationTransitionCount',
      'activationTransitionAt', 'commitActivation', 'prepareDrain',
      'prepareActiveDrain', 'prepareRetain', 'prepareActiveRetain',
      'prepareRelease', 'prepareReclaim', 'prepareInactiveReclaim',
      'transitionProjection', 'transitionKey', 'commitTransition',
      'recordProjection',
    ]) {
      if (typeof control?.[name] !== 'function') {
        fail('MissingRemoteBundleControl');
      }
    }
    return control;
  };
  const envelope = row => Object.freeze({
    version: row.signature_version,
    keyId: row.signature_key_id,
    runtimeBundleCid: row.runtime_bundle_cid,
    body: row.manifest_json,
    signature: row.signature,
  });
  const restore = (row, control) => {
    const manifest = admitSignedRemoteRuntimeBundle(
      envelope(row),
      bundleAuthorities,
      control,
    );
    return Object.freeze({
      manifest,
      record: control.restore(manifest, [
        String(row.record_revision),
        String(row.phase),
        String(row.owners),
      ]),
      artifactPath: join(artifacts, row.artifact_name),
      reclaimPending: row.reclaim_pending === 1,
    });
  };
  const persist = (transition, control) => {
    const [before, after] = control.transitionProjection(transition);
    const runtimeBundleCid = control.transitionKey(transition);
    const result = update.run(
      Number(after[0]),
      Number(after[1]),
      Number(after[2]),
      runtimeBundleCid,
      Number(before[0]),
      Number(before[1]),
      Number(before[2]),
    );
    if (result.changes !== 1) fail('RemoteBundleStateCollision');
    return after;
  };
  const artifactName = componentCid => componentCid.replace(':', '-');

  const store = {
    path: join(directory, 'bundles.sqlite3'),
    async install(sourcePath, signed, control) {
      active();
      requireControl(control);
      const manifest = admitSignedRemoteRuntimeBundle(
        signed,
        bundleAuthorities,
        control,
      );
      const projection = control.projection(manifest);
      const runtimeBundleCid = projection[0];
      const componentCid = projection[5];
      const componentBytes = BigInt(projection[6]);
      if (projection[4] !== targetTriple ||
          componentBytes > maxComponentBytes) {
        fail('RemoteBundleTargetRejected');
      }
      const name = artifactName(componentCid);
      const finalPath = join(artifacts, name);
      const stagingPath = join(staging, randomUUID());
      let staged = false;
      try {
        try {
          await digestFile(finalPath, componentBytes, componentCid);
        } catch (error) {
          if (error.code !== 'ENOENT') throw error;
          await copyComponent(
            sourcePath,
            stagingPath,
            componentBytes,
            componentCid,
          );
          staged = true;
          try {
            await link(stagingPath, finalPath);
            await sync(artifacts);
          } catch (error) {
            if (error.code !== 'EEXIST') throw error;
            await digestFile(finalPath, componentBytes, componentCid);
          }
        }
        const installed = transaction(database, () => {
          const existing = select.get(runtimeBundleCid);
          if (existing !== undefined) {
            if (existing.manifest_json !== signed.body ||
                existing.signature_version !== signed.version ||
                existing.signature_key_id !== signed.keyId ||
                existing.signature !== signed.signature ||
                existing.artifact_name !== name) {
              fail('RemoteBundleInstallCollision');
            }
            return restore(existing, control);
          }
          if (Number(total.get().count) >= maxBundles) {
            fail('RemoteBundleStoreCapacityExceeded');
          }
          const record = control.open(manifest);
          insert.run(
            runtimeBundleCid,
            signed.body,
            signed.version,
            signed.keyId,
            signed.signature,
            name,
            componentCid,
            projection[6],
            ...control.recordProjection(record).map(Number),
          );
          return restore(select.get(runtimeBundleCid), control);
        });
        return installed;
      } finally {
        if (staged) {
          try { await remove(stagingPath); }
          catch (error) { if (error.code !== 'ENOENT') throw error; }
          await sync(staging);
        }
      }
    },
    activate(runtimeBundleCid, control) {
      active();
      requireControl(control);
      return transaction(database, () => {
        const targetRow = select.get(runtimeBundleCid);
        if (targetRow === undefined) fail('RemoteBundleMissing');
        const currentCid = activeRow.get('active_bundle_cid').value;
        if (currentCid === runtimeBundleCid) return restore(targetRow, control);
        const target = restore(targetRow, control);
        let current;
        if (currentCid !== '') {
          const currentRow = select.get(currentCid);
          if (currentRow === undefined) fail('RemoteBundleActiveMissing');
          current = restore(currentRow, control);
        }
        const activation = control.prepareActivation(
          current?.record,
          target.record,
        );
        const transitionCount = control.activationTransitionCount(activation);
        for (let index = 0; index < transitionCount; index++) {
          persist(control.activationTransitionAt(activation, index), control);
        }
        setActive.run(runtimeBundleCid, 'active_bundle_cid');
        control.commitActivation(activation, true);
        return restore(select.get(runtimeBundleCid), control);
      });
    },
    rollback(runtimeBundleCid, control) {
      return store.activate(runtimeBundleCid, control);
    },
    drain(runtimeBundleCid, control) {
      active();
      requireControl(control);
      return transaction(database, () => {
        const row = select.get(runtimeBundleCid);
        if (row === undefined) fail('RemoteBundleMissing');
        const value = restore(row, control);
        const state = control.recordProjection(value.record);
        if (state[1] === '2') return value;
        const activeBundleCid = activeRow.get('active_bundle_cid').value;
        const transition = control.prepareActiveDrain(
          activeBundleCid === '' ? undefined : activeBundleCid,
          value.record,
        );
        persist(transition, control);
        setActive.run('', 'active_bundle_cid');
        control.commitTransition(transition, true);
        return restore(select.get(runtimeBundleCid), control);
      });
    },
    retain(runtimeBundleCid, holdId, kind, control) {
      active();
      requireControl(control);
      if (!text(holdId) || !text(kind)) fail('InvalidRemoteBundleHold');
      return transaction(database, () => {
        const existing = selectHold.get(holdId);
        if (existing !== undefined) {
          if (existing.runtime_bundle_cid !== runtimeBundleCid ||
              existing.kind !== kind) {
            fail('RemoteBundleHoldCollision');
          }
          return restore(select.get(runtimeBundleCid), control);
        }
        const currentCid = activeRow.get('active_bundle_cid').value;
        const row = select.get(runtimeBundleCid);
        if (row === undefined) fail('RemoteBundleMissing');
        const value = restore(row, control);
        const transition = control.prepareActiveRetain(
          currentCid === '' ? undefined : currentCid,
          value.record,
          maxOwners,
        );
        persist(transition, control);
        insertHold.run(holdId, runtimeBundleCid, kind);
        control.commitTransition(transition, true);
        return restore(select.get(runtimeBundleCid), control);
      });
    },
    release(holdId, control) {
      active();
      requireControl(control);
      if (!text(holdId)) fail('InvalidRemoteBundleHold');
      return transaction(database, () => {
        const hold = selectHold.get(holdId);
        if (hold === undefined) return false;
        const row = select.get(hold.runtime_bundle_cid);
        if (row === undefined) fail('RemoteBundleMissing');
        const value = restore(row, control);
        const transition = control.prepareRelease(value.record);
        persist(transition, control);
        deleteHold.run(holdId);
        control.commitTransition(transition, true);
        return true;
      });
    },
    async reclaim(runtimeBundleCid, control) {
      active();
      requireControl(control);
      const prepared = transaction(database, () => {
        const currentCid = activeRow.get('active_bundle_cid').value;
        const row = select.get(runtimeBundleCid);
        if (row === undefined) fail('RemoteBundleMissing');
        const value = restore(row, control);
        if (control.recordProjection(value.record)[1] === '3') {
          return Object.freeze({row, transition: undefined});
        }
        const transition = control.prepareInactiveReclaim(
          currentCid === '' ? undefined : currentCid,
          value.record,
        );
        database.prepare(`
          UPDATE bundles SET reclaim_pending = 1
          WHERE runtime_bundle_cid = ? AND reclaim_pending = 0
        `).run(runtimeBundleCid);
        return Object.freeze({row, transition});
      });
      if (prepared.transition === undefined) {
        return restore(prepared.row, control);
      }
      const users = Number(artifactUsers.get(
        prepared.row.artifact_name,
        runtimeBundleCid,
      ).count);
      if (users === 0) {
        try { await remove(join(artifacts, prepared.row.artifact_name)); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
        await sync(artifacts);
      }
      transaction(database, () => {
        persist(prepared.transition, control);
        database.prepare(`
          UPDATE bundles SET reclaim_pending = 0
          WHERE runtime_bundle_cid = ?
        `).run(runtimeBundleCid);
      });
      control.commitTransition(prepared.transition, true);
      return restore(select.get(runtimeBundleCid), control);
    },
    inspect(runtimeBundleCid, control) {
      active();
      requireControl(control);
      const row = select.get(runtimeBundleCid);
      return row === undefined ? undefined : restore(row, control);
    },
    active(control) {
      active();
      const runtimeBundleCid = activeRow.get('active_bundle_cid').value;
      return runtimeBundleCid === ''
        ? undefined
        : restore(select.get(runtimeBundleCid), requireControl(control));
    },
    list(control) {
      active();
      requireControl(control);
      return Object.freeze(selectAll.all().map(row => restore(row, control)));
    },
    async verify(runtimeBundleCid, control) {
      const value = store.inspect(runtimeBundleCid, control);
      if (value === undefined) fail('RemoteBundleMissing');
      const projection = control.projection(value.manifest);
      await digestFile(value.artifactPath, BigInt(projection[6]), projection[5]);
      return value;
    },
    async recover(control) {
      active();
      requireControl(control);
      for (const name of await readdir(staging)) {
        await remove(join(staging, name));
      }
      await sync(staging);
      for (const row of selectAll.all()) {
        if (row.reclaim_pending === 1) {
          await store.reclaim(row.runtime_bundle_cid, control);
        }
      }
      const referenced = new Set(selectAll.all()
        .filter(row => row.phase !== 3)
        .map(row => row.artifact_name));
      for (const name of await readdir(artifacts)) {
        if (!referenced.has(name)) await remove(join(artifacts, name));
      }
      await sync(artifacts);
      return store.list(control);
    },
    close() {
      if (closed) return false;
      database.exec('PRAGMA wal_checkpoint(TRUNCATE)');
      database.close();
      closed = true;
      return true;
    },
  };
  return Object.freeze(store);
}
