import {spawn} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';

// Wait for the child to close before restoring its compilation inputs. A caught
// parent signal is an interruption, even when the child prints an assertion.
// SIGKILL cannot run cleanup; the existing supervisor must retain that custody.
export async function runRestoredMutation(file, source, mutant, command, args, options, observeMutation) {
  const original = Buffer.from(source);
  const changed = Buffer.from(mutant);
  if (observeMutation !== undefined && typeof observeMutation !== 'function') {
    throw new Error('Mutation observer must be a synchronous function');
  }
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
    // The chain receipt records its actual mutated snapshot before launch.
    // This observer cannot supply arguments or a decision to the child.
    observeMutation?.();
    if (!readFileSync(file).equals(changed)) {
      throw new Error('Mutation source changed before child execution');
    }
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

// Assertion-shaped output from an interrupted or uncompleted process is not
// fault detection. Keep the original nonzero assertion and compiler refusals.
export function requireMutationDetection(result, output) {
  if (result.error || result.interrupted || result.signal ||
      !Number.isSafeInteger(result.status) || result.status <= 0) {
    throw result.error ?? new Error('Process failure is not assertion detection');
  }
  const count = Number(output.match(/Total tests: \d+, passed: \d+, failed: (\d+)/)?.[1] ?? 0);
  if (!Number.isSafeInteger(count) || count <= 0 || /Error: \[\d+\]/.test(output)) {
    throw new Error('Mutation was not killed by running assertions');
  }
  return count;
}
