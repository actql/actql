// Evidence and scratch ownership for this packed-query acceptance only.
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {appendFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {basename, join} from 'node:path';

export async function withPackedQueryEvidence({scratch, revision,
  keepArtifacts = false, githubOutput}, body) {
  mkdirSync(scratch, {recursive: true});
  const directory = mkdtempSync(join(scratch, 'public-query-evidence-'));
  const root = join(directory, 'artifacts');
  mkdirSync(root);
  const summary = {revision, keepArtifacts, status: 'running', commands: [],
    tarballs: [], artifactsRemoved: false};
  const persist = () => writeFileSync(join(directory, 'summary.json'),
    JSON.stringify(summary, null, 2) + '\n');
  persist();
  let failure;
  try {
    // Publish before any child runs: failed and timed-out runs need the same
    // evidence upload as successful runs. Never publish the artifact directory.
    if (githubOutput !== undefined) {
      if (/[\r\n]/u.test(directory)) throw new Error('InvalidEvidenceDirectory');
      appendFileSync(githubOutput, `evidence-directory=${directory}\n`);
    }
    await body({root, directory,
      recordTarball(path) {
        summary.tarballs.push({name: basename(path), sha256:
          createHash('sha256').update(readFileSync(path)).digest('hex')});
        persist();
      },
      run(command, args, {cwd = root, env = process.env,
        timeout = 240_000} = {}) {
        const started = performance.now();
        const result = spawnSync(command, args, {cwd, env, encoding: 'utf8',
          timeout, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024});
        const id = String(summary.commands.length + 1).padStart(3, '0');
        const outcome = {id, command, args, status: result.status,
          signal: result.signal, elapsedMs: performance.now() - started,
          error: result.error === undefined ? null : {
            code: result.error.code, message: result.error.message}};
        // Save both streams and the exit observation before classifying it.
        // Do not log the environment (it can contain credential references).
        writeFileSync(join(directory, `${id}.stdout.log`), result.stdout ?? '');
        writeFileSync(join(directory, `${id}.stderr.log`), result.stderr ?? '');
        summary.commands.push(outcome);
        persist();
        if (result.error || result.status !== 0) {
          throw Object.assign(new Error(`PackedQueryCommandFailed:${id}`, {
            cause: result.error}), {code: 'PackedQueryCommandFailed', outcome,
            evidenceDirectory: directory});
        }
        return result.stdout;
      }});
    summary.status = 'passed';
  } catch (error) {
    failure = error;
    summary.status = 'failed';
  } finally {
    // If evidence cannot be saved, preserve the artifacts for diagnosis.
    try {
      persist();
      if (!keepArtifacts) {
        rmSync(root, {recursive: true});
        summary.artifactsRemoved = true;
        persist();
      }
    } catch (cleanupError) {
      failure = failure === undefined ? cleanupError :
        new AggregateError([failure, cleanupError],
          'PackedQueryEvidenceCleanupFailed', {cause: failure});
    }
  }
  if (failure !== undefined) throw failure;
  return directory;
}
