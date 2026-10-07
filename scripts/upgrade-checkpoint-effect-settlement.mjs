// Explicit offline layout update. Ordinary Host startup never calls this tool.
import {constants, copyFileSync, chmodSync, closeSync, fsyncSync,
  existsSync, openSync, readFileSync, realpathSync, statSync} from 'node:fs';
import {dirname, resolve, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import {createHash} from 'node:crypto';
import {EFFECT_SETTLEMENT_JOURNAL_LAYOUT, PRE_EFFECT_SETTLEMENT_JOURNAL_LAYOUT,
  EFFECT_SETTLEMENT_TABLE_SQL} from '../adapters/host-node/sqlite-checkpoint-journal.mjs';

export function upgradeCheckpointEffectSettlement({root, backupPath, offline = false}) {
  if (offline !== true || typeof root !== 'string' || typeof backupPath !== 'string') {
    throw new Error('OfflineCheckpointUpgradeRequired');
  }
  const path = join(realpathSync(root), 'checkpoint-journal.sqlite3');
  if (!statSync(path).isFile()) throw new Error('CheckpointJournalFileRequired');
  const backup = resolve(backupPath);
  if (path === backup) throw new Error('CheckpointBackupMustBeSeparate');
  const database = new DatabaseSync(path, {enableForeignKeyConstraints: true});
  let transaction = false;
  try {
    database.exec('PRAGMA busy_timeout = 0');
    const version = database.prepare('SELECT value FROM journal_metadata WHERE key = ?')
      .get('schema_version')?.value;
    if (version !== PRE_EFFECT_SETTLEMENT_JOURNAL_LAYOUT) throw new Error('UnsupportedCheckpointUpgradeSource');
    if (database.prepare("SELECT name FROM sqlite_schema WHERE type = 'trigger' OR name = 'resume_effect_settlements'").get()) {
      throw new Error('UnexpectedCheckpointUpgradeSchema');
    }
    if (database.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok' ||
        database.prepare('PRAGMA foreign_key_check').all().length !== 0) {
      throw new Error('CheckpointUpgradeIntegrityFailed');
    }
    const checkpoint = database.prepare('PRAGMA wal_checkpoint(TRUNCATE)').get();
    if (checkpoint.busy !== 0) throw new Error('CheckpointUpgradeBusy');
    database.exec('BEGIN EXCLUSIVE');
    transaction = true;
    // A writer that raced the checkpoint must not leave evidence only in WAL
    // outside the standalone backup. The exclusive transaction now excludes
    // another writer; stop instead of guessing whether those frames matter.
    if (existsSync(`${path}-wal`) && statSync(`${path}-wal`).size !== 0) {
      throw new Error('CheckpointUpgradeBusy');
    }
    if (database.prepare('SELECT value FROM journal_metadata WHERE key = ?')
      .get('schema_version')?.value !== PRE_EFFECT_SETTLEMENT_JOURNAL_LAYOUT) {
      throw new Error('CheckpointUpgradeSourceChanged');
    }
    // The operator confirms every Host is stopped. Exclusive writing alone
    // cannot revoke an old process's already-open connection.
    copyFileSync(path, backup, constants.COPYFILE_EXCL);
    chmodSync(backup, 0o600);
    const fd = openSync(backup, 'r');
    try { fsyncSync(fd); } finally { closeSync(fd); }
    const directory = openSync(dirname(backup), 'r');
    try { fsyncSync(directory); } finally { closeSync(directory); }
    const backupSha256 = createHash('sha256').update(readFileSync(backup)).digest('hex');
    // No Run, claim, admission, resolution, Model, or Effect evidence row is
    // rewritten. The new durable observation mode starts empty.
    database.exec(EFFECT_SETTLEMENT_TABLE_SQL);
    const result = database.prepare('UPDATE journal_metadata SET value = ? WHERE key = ? AND value = ?')
      .run(EFFECT_SETTLEMENT_JOURNAL_LAYOUT, 'schema_version', PRE_EFFECT_SETTLEMENT_JOURNAL_LAYOUT);
    if (result.changes !== 1) throw new Error('CheckpointUpgradeSourceChanged');
    database.exec('COMMIT');
    transaction = false;
    return Object.freeze({path, backup, backupSha256,
      from: PRE_EFFECT_SETTLEMENT_JOURNAL_LAYOUT, to: EFFECT_SETTLEMENT_JOURNAL_LAYOUT});
  } finally {
    try { if (transaction) database.exec('ROLLBACK'); }
    finally { database.close(); }
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length !== 5 || args[0] !== '--offline' || args[1] !== '--root' || args[3] !== '--backup') {
    throw new Error('Usage: node scripts/upgrade-checkpoint-effect-settlement.mjs --offline --root JOURNAL_DIRECTORY --backup NEW_BACKUP_FILE');
  }
  console.log(JSON.stringify(upgradeCheckpointEffectSettlement({offline: true,
    root: args[2], backupPath: args[4]})));
}
