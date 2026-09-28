import {DatabaseSync} from 'node:sqlite';
import fs from 'node:fs';
import {
  existsSync,
  mkdirSync,
  realpathSync,
} from 'node:fs';
import {join} from 'node:path';
import {createSqliteTransaction, throwSqliteInitializationFailure} from
  '../host-common/sqlite-transaction.mjs';
import {admitSignedRemoteCredentialGrant} from
  './remote-credential-signature.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const count = value => Number.isSafeInteger(value) && value >= 0;
const outcomes = Object.freeze(new Map([
  ['claimed', 0],
  ['succeeded', 1],
  ['failed', 2],
  ['unknown', 3],
]));

function syncDirectory(path) {
  const descriptor = fs.openSync(path, 'r');
  try { fs.fsyncSync(descriptor); }
  finally { fs.closeSync(descriptor); }
}

export function openSqliteCredentialJournal(root, {
  credentialAuthorities,
  maxGrants = 100_000,
  maxUses = 1_000_000,
  maxGrantBytes = 32_768,
  maxUseBytes = 4096,
} = {}) {
  if (!text(root) || !(credentialAuthorities instanceof Map) ||
      credentialAuthorities.size === 0 ||
      !count(maxGrants) || maxGrants === 0 ||
      !count(maxUses) || maxUses === 0 ||
      !count(maxGrantBytes) || maxGrantBytes === 0 ||
      !count(maxUseBytes) || maxUseBytes === 0) {
    fail('InvalidRemoteCredentialJournalConfiguration');
  }
  mkdirSync(root, {recursive: true, mode: 0o700});
  const directory = realpathSync(root);
  const path = join(directory, 'credential-journal.sqlite3');
  const existed = existsSync(path);
  const database = new DatabaseSync(path, {
    open: true,
    readOnly: false,
    enableForeignKeyConstraints: true,
  });
  const transaction = createSqliteTransaction(database,
    'RemoteCredentialJournal');
  let closed = false;
  let databaseClosed = false;
  let directorySynced = false;
  let creationSynced = existed;
  try {
    database.exec('PRAGMA journal_mode = WAL');
    database.exec('PRAGMA synchronous = FULL');
    database.exec('PRAGMA wal_autocheckpoint = 1000');
    database.exec(`
      CREATE TABLE IF NOT EXISTS journal_metadata (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      ) STRICT;
      CREATE TABLE IF NOT EXISTS credential_grants (
        grant_cid TEXT PRIMARY KEY NOT NULL,
        grant_json TEXT NOT NULL,
        signature_version TEXT NOT NULL,
        signature_key_id TEXT NOT NULL,
        signature TEXT NOT NULL,
        revoked INTEGER NOT NULL DEFAULT 0 CHECK (revoked IN (0, 1))
      ) STRICT;
      CREATE TABLE IF NOT EXISTS credential_uses (
        use_cid TEXT PRIMARY KEY NOT NULL,
        grant_cid TEXT NOT NULL,
        use_id TEXT NOT NULL,
        use_ordinal INTEGER NOT NULL CHECK (use_ordinal > 0),
        use_json TEXT NOT NULL,
        outcome INTEGER NOT NULL DEFAULT 0 CHECK (outcome BETWEEN 0 AND 3),
        FOREIGN KEY (grant_cid) REFERENCES credential_grants(grant_cid),
        UNIQUE (grant_cid, use_id),
        UNIQUE (grant_cid, use_ordinal)
      ) STRICT;
    `);
    transaction.run(() => {
      const row = database.prepare(
        'SELECT value FROM journal_metadata WHERE key = ?',
      ).get('schema_version');
      if (row === undefined) {
        database.prepare(`
          INSERT INTO journal_metadata (key, value) VALUES (?, ?)
        `).run('schema_version', 'actql-credential-journal/0.1');
      } else if (row.value !== 'actql-credential-journal/0.1') {
        fail('UnsupportedRemoteCredentialJournalVersion');
      }
    });
    if (!creationSynced) {
      syncDirectory(directory);
      creationSynced = true;
    }

  const selectGrant = database.prepare(
    'SELECT * FROM credential_grants WHERE grant_cid = ?',
  );
  const selectUse = database.prepare(
    'SELECT * FROM credential_uses WHERE use_cid = ?',
  );
  const selectUseId = database.prepare(`
    SELECT * FROM credential_uses WHERE grant_cid = ? AND use_id = ?
  `);
  const grantCount = database.prepare(
    'SELECT COUNT(*) AS count FROM credential_grants',
  );
  const useCount = database.prepare(
    'SELECT COUNT(*) AS count FROM credential_uses',
  );
  const grantUseCount = database.prepare(`
    SELECT COUNT(*) AS count FROM credential_uses WHERE grant_cid = ?
  `);
  const insertGrant = database.prepare(`
    INSERT INTO credential_grants (
      grant_cid,
      grant_json,
      signature_version,
      signature_key_id,
      signature
    ) VALUES (?, ?, ?, ?, ?)
  `);
  const insertUse = database.prepare(`
    INSERT INTO credential_uses (
      use_cid, grant_cid, use_id, use_ordinal, use_json
    ) VALUES (?, ?, ?, ?, ?)
  `);
  const revokeGrant = database.prepare(`
    UPDATE credential_grants SET revoked = 1 WHERE grant_cid = ?
  `);
  const finishUse = database.prepare(`
    UPDATE credential_uses SET outcome = ?
    WHERE use_cid = ? AND outcome IN (0, 3)
  `);
  const selectAllUses = database.prepare(`
    SELECT * FROM credential_uses ORDER BY rowid
  `);

  const active = () => {
    if (closed) fail('RemoteCredentialJournalClosed');
    transaction.assertUsable();
  };
  const requireControl = control => {
    if (typeof control?.identity !== 'function' ||
        typeof control?.json !== 'function' ||
        typeof control?.admitJson !== 'function' ||
        typeof control?.projection !== 'function' ||
        typeof control?.prepareUse !== 'function' ||
        typeof control?.useIdentity !== 'function' ||
        typeof control?.useJson !== 'function' ||
        typeof control?.authorizeUse !== 'function' ||
        typeof control?.useProjection !== 'function') {
      fail('MissingRemoteCredentialControl');
    }
    return control;
  };
  const record = row => Object.freeze({
    useCid: row.use_cid,
    grantCid: row.grant_cid,
    useId: row.use_id,
    useOrdinal: Number(row.use_ordinal),
    outcome: [...outcomes].find(([, code]) => code === row.outcome)?.[0],
  });
  const admitGrant = (row, control) => admitSignedRemoteCredentialGrant({
    version: row.signature_version,
    keyId: row.signature_key_id,
    grantCid: row.grant_cid,
    body: row.grant_json,
    signature: row.signature,
  }, credentialAuthorities, control);

  return Object.freeze({
    path,
    acceptGrant(envelope, control) {
      active();
      requireControl(control);
      const grant = admitSignedRemoteCredentialGrant(
        envelope,
        credentialAuthorities,
        control,
      );
      const grantCid = control.identity(grant);
      const grantJson = control.json(grant);
      const projection = control.projection(grant);
      if (!text(grantCid) || !Array.isArray(projection) ||
          projection.length !== 17 || projection[0] !== grantCid ||
          Buffer.byteLength(grantJson, 'utf8') > maxGrantBytes) {
        fail('InvalidRemoteCredentialGrant');
      }
      return transaction.run(() => {
        const existing = selectGrant.get(grantCid);
        if (existing !== undefined) {
          if (existing.grant_json !== grantJson ||
              existing.signature_version !== envelope.version ||
              existing.signature_key_id !== envelope.keyId ||
              existing.signature !== envelope.signature) {
            fail('RemoteCredentialGrantCollision');
          }
          return admitGrant(existing, control);
        }
        if (Number(grantCount.get().count) >= maxGrants) {
          fail('RemoteCredentialGrantCapacityExceeded');
        }
        insertGrant.run(
          grantCid,
          grantJson,
          envelope.version,
          envelope.keyId,
          envelope.signature,
        );
        return grant;
      });
    },
    checkGrant(grantCid, trustedNowMilliseconds, scope, control) {
      active();
      requireControl(control);
      if (!text(grantCid) || typeof trustedNowMilliseconds !== 'bigint' ||
          trustedNowMilliseconds < 0n || scope === null ||
          typeof scope !== 'object') fail('InvalidRemoteCredentialUse');
      return transaction.run(() => {
        const row = selectGrant.get(grantCid);
        if (row === undefined) fail('RemoteCredentialGrantMissing');
        const grant = admitGrant(row, control);
        // Reuse the common scope, expiry, revocation and remaining-use rules.
        // This prospective use is neither persisted nor a physical permit.
        control.prepareUse(grant, {
          useId: 'admission-check', trustedNowMilliseconds,
          usedCount: Number(grantUseCount.get(grantCid).count),
          revoked: row.revoked === 1, scope,
        });
        return grant;
      });
    },
    claim(grantCid, useId, trustedNowMilliseconds, scope, control) {
      active();
      requireControl(control);
      if (!text(grantCid) || !text(useId) ||
          typeof trustedNowMilliseconds !== 'bigint' ||
          trustedNowMilliseconds < 0n || scope === null ||
          typeof scope !== 'object') {
        fail('InvalidRemoteCredentialUse');
      }
      return transaction.run(() => {
        const grantRow = selectGrant.get(grantCid);
        if (grantRow === undefined) fail('RemoteCredentialGrantMissing');
        const grant = admitGrant(grantRow, control);
        const existing = selectUseId.get(grantCid, useId);
        const usedCount = existing === undefined
          ? Number(grantUseCount.get(grantCid).count)
          : Number(existing.use_ordinal) - 1;
        const use = control.prepareUse(grant, {
          useId,
          trustedNowMilliseconds,
          usedCount,
          revoked: grantRow.revoked === 1,
          scope,
        });
        const useCid = control.useIdentity(use);
        const useJson = control.useJson(use);
        const projection = control.useProjection(use);
        if (!Array.isArray(projection) || projection.length !== 4 ||
            projection[0] !== useCid || projection[1] !== grantCid ||
            projection[2] !== useId ||
            projection[3] !== String(usedCount + 1) ||
            Buffer.byteLength(useJson, 'utf8') > maxUseBytes) {
          fail('InvalidRemoteCredentialUse');
        }
        if (existing !== undefined) {
          if (existing.use_cid !== useCid || existing.use_json !== useJson) {
            fail('RemoteCredentialUseCollision');
          }
          return Object.freeze({
            replayed: true,
            record: record(existing),
            use,
          });
        }
        if (Number(useCount.get().count) >= maxUses) {
          fail('RemoteCredentialUseCapacityExceeded');
        }
        insertUse.run(useCid, grantCid, useId, usedCount + 1, useJson);
        return Object.freeze({
          replayed: false,
          record: record(selectUse.get(useCid)),
          use,
        });
      });
    },
    authorize(use, trustedNowMilliseconds, scope, control) {
      active();
      requireControl(control);
      if (typeof trustedNowMilliseconds !== 'bigint' ||
          trustedNowMilliseconds < 0n || scope === null ||
          typeof scope !== 'object') {
        fail('InvalidRemoteCredentialUse');
      }
      return transaction.run(() => {
        const useCid = control.useIdentity(use);
        const useRow = selectUse.get(useCid);
        if (useRow === undefined) fail('RemoteCredentialUseMissing');
        const grantRow = selectGrant.get(useRow.grant_cid);
        if (grantRow === undefined) fail('RemoteCredentialGrantMissing');
        control.authorizeUse(use, {
          trustedNowMilliseconds,
          revoked: grantRow.revoked === 1,
          scope,
        });
        return record(useRow);
      });
    },
    finish(useCid, outcome) {
      active();
      if (!text(useCid) || !outcomes.has(outcome) || outcome === 'claimed') {
        fail('InvalidRemoteCredentialOutcome');
      }
      return transaction.run(() => {
        const current = selectUse.get(useCid);
        if (current === undefined) fail('RemoteCredentialUseMissing');
        if (current.outcome === outcomes.get(outcome)) return record(current);
        if (current.outcome !== 0 && current.outcome !== 3) {
          fail('RemoteCredentialOutcomeConflict');
        }
        finishUse.run(outcomes.get(outcome), useCid);
        return record(selectUse.get(useCid));
      });
    },
    revoke(grantCid) {
      active();
      if (!text(grantCid)) fail('InvalidRemoteCredentialGrant');
      return transaction.run(() => {
        if (selectGrant.get(grantCid) === undefined) {
          fail('RemoteCredentialGrantMissing');
        }
        revokeGrant.run(grantCid);
        return true;
      });
    },
    inspect(useCid) {
      active();
      const row = selectUse.get(useCid);
      return row === undefined ? undefined : record(row);
    },
    recover() {
      active();
      return Object.freeze(selectAllUses.all().map(record));
    },
    close() {
      closed = true;
      if (!databaseClosed) {
        database.exec('PRAGMA wal_checkpoint(TRUNCATE)');
        database.close();
        databaseClosed = true;
      }
      if (!directorySynced) {
        syncDirectory(directory);
        directorySynced = true;
      }
    },
  });
  } catch (error) {
    throwSqliteInitializationFailure(database, error, 'credential-journal',
      !creationSynced ? () => syncDirectory(directory) : undefined);
  }
}
