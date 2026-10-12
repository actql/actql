// Explicit offline layout update. Ordinary Host startup never calls this tool.
import {constants, closeSync, fsyncSync, existsSync, openSync,
  readSync, realpathSync, statSync, writeSync} from 'node:fs';
import {dirname, resolve, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import {createHash} from 'node:crypto';
import {EFFECT_SETTLEMENT_JOURNAL_LAYOUT, PRE_EFFECT_SETTLEMENT_JOURNAL_LAYOUT,
  MODEL_CURRENT_CUT_JOURNAL_LAYOUT, EFFECT_SETTLEMENT_TABLE_SQL} from '../adapters/host-node/sqlite-checkpoint-journal.mjs';

export function upgradeCheckpointEffectSettlement({root, backupPath, offline = false}) {
  return upgradeCheckpointLayout({root, backupPath, offline, kind: 'effect'});
}

// Explicit second offline operation; ordinary startup never ALTERs old roots.
export function upgradeCheckpointModelCurrentCut({root, backupPath, offline = false}) {
  return upgradeCheckpointLayout({root, backupPath, offline, kind: 'model-cut'});
}

function upgradeCheckpointLayout({root, backupPath, offline, kind}) {
  if (offline !== true || typeof root !== 'string' || typeof backupPath !== 'string') {
    throw new Error('OfflineCheckpointUpgradeRequired');
  }
  const path = join(realpathSync(root), 'checkpoint-journal.sqlite3');
  if (!statSync(path).isFile()) throw new Error('CheckpointJournalFileRequired');
  const backup = resolve(backupPath);
  if (path === backup) throw new Error('CheckpointBackupMustBeSeparate');
  const database = new DatabaseSync(path, {enableForeignKeyConstraints: true});
  const sourceLayout = kind === 'effect' ? PRE_EFFECT_SETTLEMENT_JOURNAL_LAYOUT : EFFECT_SETTLEMENT_JOURNAL_LAYOUT;
  const targetLayout = kind === 'effect' ? EFFECT_SETTLEMENT_JOURNAL_LAYOUT : MODEL_CURRENT_CUT_JOURNAL_LAYOUT;
  let transaction = false;
  try {
    database.exec('PRAGMA busy_timeout = 0');
    const version = database.prepare('SELECT value FROM journal_metadata WHERE key = ?')
      .get('schema_version')?.value;
    if (version !== sourceLayout) throw new Error('UnsupportedCheckpointUpgradeSource');
    if (database.prepare("SELECT name FROM sqlite_schema WHERE type = 'trigger'").get() ||
        kind === 'effect' && database.prepare("SELECT name FROM sqlite_schema WHERE name = 'resume_effect_settlements'").get() ||
        database.prepare('PRAGMA table_info(resume_model_scopes)').all().some(column => column.name === 'current_cut_link_json')) {
      throw new Error('UnexpectedCheckpointUpgradeSchema');
    }
    if (kind === 'model-cut') database.prepare('SELECT intent_id, generation, refusal_code FROM resume_effect_settlements LIMIT 0');
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
      .get('schema_version')?.value !== sourceLayout) {
      throw new Error('CheckpointUpgradeSourceChanged');
    }
    // The operator confirms every Host is stopped. Exclusive writing alone
    // cannot revoke an old process's already-open connection.
    // The backup is private from its first byte, including an interrupted
    // copy. Bounded copying also avoids buffering the entire journal in RAM.
    const source = openSync(path, 'r');
    const digest = createHash('sha256');
    try {
      const fd = openSync(backup, constants.O_WRONLY | constants.O_CREAT |
        constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
      try {
        const buffer = Buffer.allocUnsafe(64 * 1024);
        let count;
        while ((count = readSync(source, buffer, 0, buffer.length, null)) !== 0) {
          let written = 0;
          while (written < count) written += writeSync(fd, buffer, written, count - written);
          digest.update(buffer.subarray(0, count));
        }
        fsyncSync(fd);
      } finally { closeSync(fd); }
    } finally { closeSync(source); }
    const directory = openSync(dirname(backup), 'r');
    try { fsyncSync(directory); } finally { closeSync(directory); }
    const backupSha256 = digest.digest('hex');
    // No Run, claim, admission, resolution, Model, or Effect evidence row is
    // rewritten. The new durable observation mode starts empty.
    database.exec(kind === 'effect' ? EFFECT_SETTLEMENT_TABLE_SQL :
      'ALTER TABLE resume_model_scopes ADD COLUMN current_cut_link_json TEXT DEFAULT NULL');
    const result = database.prepare('UPDATE journal_metadata SET value = ? WHERE key = ? AND value = ?')
      .run(targetLayout, 'schema_version', sourceLayout);
    if (result.changes !== 1) throw new Error('CheckpointUpgradeSourceChanged');
    database.exec('COMMIT');
    transaction = false;
    return Object.freeze({path, backup, backupSha256,
      from: sourceLayout, to: targetLayout});
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
