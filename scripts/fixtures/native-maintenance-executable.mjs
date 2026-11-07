// Prepare only a distinct test operator artifact, never the installed bundle.
import {readFile, writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';

export async function prepareMaintenanceTestExecutable(source, destination) {
  const original = await readFile(source);
  // Appending a trailer invalidates the Mach-O layout. A different ad-hoc
  // signing identifier gives the same code a valid, distinct artifact instead;
  // neither this OS launch signature nor its path grants execution authority.
  await writeFile(destination, process.platform === 'darwin' ? original
    : Buffer.concat([original, Buffer.from('\nmaintenance-test-binary\n')]),
  {mode: 0o700, flag: 'wx'});
  if (process.platform === 'darwin') {
    execFileSync('/usr/bin/codesign', ['--force', '--sign', '-',
      '--identifier', 'actql-native-resident-maintenance-test', destination],
    {stdio: ['ignore', 'ignore', 'pipe']});
    execFileSync('/usr/bin/codesign', ['--verify', '--strict', destination],
      {stdio: ['ignore', 'ignore', 'pipe']});
  }
}
