import {constants} from 'node:fs';
import {open} from 'node:fs/promises';
import {copyExplorerLaunchInput} from './launch-input.mjs';

const invalid = () => {throw new Error('ExplorerInvalidArguments');};
export function explorerArguments(args) {
  let local = false, allowCancellation = false, stateDir, program, run, format;
  for (let i = 0; i < args.length; i++) {
    const flag = args[i], value = args[i + 1];
    if (flag === '--local' && !local) local = true;
    else if (flag === '--allow-cancel' && !allowCancellation) allowCancellation = true;
    else if (['--state-dir', '--program', '--run', '--format'].includes(flag) &&
        typeof value === 'string' && value.length > 0 && !value.startsWith('--')) {
      if (flag === '--state-dir' && stateDir === undefined) stateDir = value;
      else if (flag === '--program' && program === undefined) program = value;
      else if (flag === '--run' && run === undefined) run = value;
      else if (flag === '--format' && format === undefined) format = value;
      else invalid();
      i++;
    } else invalid();
  }
  if (!local) throw new Error('ExplorerExplicitHostRequired');
  if (program !== undefined && run !== undefined ||
      format !== undefined && (program === undefined || !['sql', 'aql', 'aql-text', 'program'].includes(format))) invalid();
  return Object.freeze({...(allowCancellation ? {allowCancellation:true} : {}), local: stateDir === undefined ? {} : {stateDir},
    ...(program === undefined ? {} : {program, format: format ?? 'sql'}),
    ...(run === undefined ? {} : {run})});
}

// Read only the explicitly named regular authoring/reference file. No directory
// is served, no input is printed, and this happens before opening a Local Host.
async function readLaunchFile(path) {
  const limit = 65536;
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = await file.stat();
    if (!before.isFile() || before.size < 1 || before.size > limit) invalid();
    const bytes = Buffer.alloc(limit + 1); let length = 0;
    while (length <= limit) {
      const {bytesRead} = await file.read(bytes, length, bytes.length - length, null);
      if (bytesRead === 0) break;
      length += bytesRead;
      if (length > limit) invalid();
    }
    const after = await file.stat();
    if (length !== before.size || after.dev !== before.dev || after.ino !== before.ino ||
        after.size !== before.size || after.mtimeMs !== before.mtimeMs || after.ctimeMs !== before.ctimeMs) invalid();
    return new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(bytes.subarray(0, length));
  } finally {await file.close();}
}

export async function explorerLaunchInput(selection) {
  if (selection.program !== undefined) return copyExplorerLaunchInput({
    kind: 'program', text: await readLaunchFile(selection.program), format: selection.format});
  if (selection.run !== undefined) return copyExplorerLaunchInput({
    kind: 'run', ref: JSON.parse(await readLaunchFile(selection.run))});
  return null;
}
