import {spawnSync} from 'node:child_process';

// The pinned Linux Native debug generator can overflow an 8 MiB stack after
// a preceding mutation invalidates its incremental object. Change the soft
// limit only in the selected Native child, preserving the caller and hard
// limit. This is an execution-environment prerequisite, not a resource law.
export function spawnProofCommand(command, args, target, options) {
  if (process.platform !== 'linux' || target !== 'native') {
    return spawnSync(command, args, options);
  }
  const index = args.indexOf('--target');
  if (!(index >= 0 && args[index + 1] === 'native') &&
      !args.includes('--target=native')) {
    throw new Error('Native proof command lacks an explicit Native target');
  }
  return spawnSync('bash', ['-eo', 'pipefail', '-c',
    'ulimit -S -s 65536\nexec "$@"', 'native-proof-child', command, ...args], options);
}
