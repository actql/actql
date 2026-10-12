// Offline private-layout update only. Never called by product startup.
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {upgradeCheckpointModelCurrentCut} from './upgrade-checkpoint-effect-settlement.mjs';

export {upgradeCheckpointModelCurrentCut};

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length !== 5 || args[0] !== '--offline' || args[1] !== '--root' || args[3] !== '--backup') {
    throw new Error('Usage: node scripts/upgrade-checkpoint-model-current-cut.mjs --offline --root JOURNAL_DIRECTORY --backup NEW_BACKUP_FILE');
  }
  console.log(JSON.stringify(upgradeCheckpointModelCurrentCut({offline: true,
    root: args[2], backupPath: args[4]})));
}
