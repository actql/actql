// Observation only: an empty snapshot does not acknowledge product cleanup.
import {execFileSync} from 'node:child_process';
import {readdir, readlink, realpath} from 'node:fs/promises';
import {resolve, sep} from 'node:path';

export function recordApprovalScopedPaths(paths, roots) {
  return paths.filter(path => {
    const original = path.replace(/ \(deleted\)$/, '');
    return roots.some(root => original === root || original.startsWith(root + sep));
  });
}

export async function observeRecordApprovalDescriptors(roots) {
  const scopeRoots = [...new Set((await Promise.all(roots.map(async root =>
    [resolve(root), await realpath(root)]))).flat())];
  let paths, observer;
  if (process.platform === 'linux') {
    observer = 'procfs';
    paths = (await Promise.all((await readdir('/proc/self/fd')).map(async fd => {
      try {return await readlink('/proc/self/fd/' + fd);}
      catch (error) {if (error.code === 'ENOENT') return undefined; throw error;}
    }))).filter(path => path !== undefined);
  } else if (process.platform === 'darwin') {
    observer = 'lsof';
    paths = execFileSync('/usr/sbin/lsof', ['-Fn', '-p', String(process.pid)],
      {encoding: 'utf8'}).split('\n').filter(line => line.startsWith('n')).map(line => line.slice(1));
  } else {
    throw new Error('RecordApprovalDescriptorObserverUnavailable');
  }
  return {observer, pid: process.pid, scopeRoots,
    openPaths: recordApprovalScopedPaths(paths, scopeRoots)};
}
