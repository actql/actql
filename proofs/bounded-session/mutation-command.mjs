import {spawn} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';

// Wait for the child to close before restoring its compilation inputs. A caught
// parent signal is an interruption, even when the child prints an assertion.
// SIGKILL cannot run cleanup; the existing supervisor must retain that custody.
export async function runRestoredMutation(file, source, mutant, command, args, options) {
  const original = Buffer.from(source);
  const changed = Buffer.from(mutant);
  if (!readFileSync(file).equals(original)) throw new Error('Mutation source changed before execution');
  let child;
  let interrupted;
  const stop = signal => {
    interrupted ??= signal;
    child?.kill(signal);
  };
  const term = () => stop('SIGTERM');
  const interrupt = () => stop('SIGINT');
  process.on('SIGTERM', term);
  process.on('SIGINT', interrupt);
  try {
    writeFileSync(file, changed);
    return await new Promise(resolve => {
      let error;
      const stdout = [];
      const stderr = [];
      let bytes = 0;
      child = spawn(command, args, {...options, stdio: ['ignore', 'pipe', 'pipe']});
      const capture = chunks => data => {
        bytes += data.length;
        if (bytes > options.maxBuffer) {
          error ??= new Error('Mutation command output exceeds maxBuffer');
          child.kill('SIGTERM');
        } else chunks.push(data);
      };
      child.stdout.on('data', capture(stdout));
      child.stderr.on('data', capture(stderr));
      child.on('error', failure => { error ??= failure; });
      child.on('close', (status, signal) => resolve({status, signal, error,
        interrupted, stdout: Buffer.concat(stdout).toString('utf8'),
        stderr: Buffer.concat(stderr).toString('utf8')}));
    });
  } finally {
    try {
      const current = readFileSync(file);
      if (!current.equals(original) && !current.equals(changed)) {
        throw new Error('Mutation source changed externally; refusing to overwrite it');
      }
      if (!current.equals(original)) writeFileSync(file, original);
    } finally {
      process.off('SIGTERM', term);
      process.off('SIGINT', interrupt);
    }
  }
}
