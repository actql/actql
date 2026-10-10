import {lstat, readdir} from 'node:fs/promises';
import {join} from 'node:path';

// Read only fixed diagnostic directory names from this test's retained root.
// Never open payloads, SQLite, identities or credentials, or follow symlinks.
// These markers describe issuer progress, not a durable outcome or release.
export async function readNativeEffectCaptureProgress(root) {
  try {
    const ownedRoot = await lstat(root);
    if (!ownedRoot.isDirectory() || ownedRoot.isSymbolicLink()) {
      return {status: 'unavailable', reason: 'unsafe-root'};
    }
    const entries = await readdir(root, {withFileTypes: true});
    const phases = [];
    for (const entry of entries) {
      const match = /\.review-capture-(preparing|prepared|advancing|completed)-(\d+)-(\d+)$/u.exec(entry.name);
      if (!entry.isDirectory() || match === null) continue;
      const metadata = await lstat(join(root, entry.name));
      if (!metadata.isDirectory() || metadata.isSymbolicLink()) continue;
      phases.push({phase: match[1], advances: match[2], logicalWork: match[3],
        observedAt: new Date(metadata.mtimeMs).toISOString()});
    }
    phases.sort((a, b) => a.observedAt.localeCompare(b.observedAt) ||
      (BigInt(a.advances) < BigInt(b.advances) ? -1 : BigInt(a.advances) > BigInt(b.advances) ? 1 :
        ['preparing', 'prepared', 'advancing', 'completed'].indexOf(a.phase) -
        ['preparing', 'prepared', 'advancing', 'completed'].indexOf(b.phase)));
    return {status: 'observed', phases};
  } catch {
    // Diagnostic collection must never replace the original test's failure,
    // or turn missing evidence into completed capture or absent custody.
    return {status: 'unavailable', reason: 'collection-failed'};
  }
}
