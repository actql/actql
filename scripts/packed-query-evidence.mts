// Owned, bounded command evidence shared by packed and focused verification.
// This captures only diagnostics from owned test commands, never an environment dump.
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {appendFileSync, constants, closeSync, fstatSync, ftruncateSync, lstatSync, mkdirSync,
  mkdtempSync, openSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {basename, join, resolve} from 'node:path';

export const COMMAND_OUTPUT_LIMIT = 8 * 1024 * 1024;
const MAX_COMMAND_OUTPUT_LIMIT = 64 * 1024 * 1024;
const same = (a, b) => a.dev === b.dev && a.ino === b.ino;
const timestamp = () => new Date().toISOString();
const errorCode = error => /^[A-Z][A-Z0-9_]+$/u.test(error?.code ?? '') ? error.code : 'EVIDENCE_WRITE_FAILED';

export function redactCommandEvidence(value, env = process.env) {
  let text = String(value);
  // Read only secret-labelled values for exact masking; no names or values are emitted.
  for (const [key, secret] of Object.entries(env)) {
    if (/(?:token|password|secret|authorization|credential|private[_-]?key)/iu.test(key) &&
        typeof secret === 'string' && secret.length >= 4) text = text.replaceAll(secret, '[REDACTED]');
  }
  return text.replace(/-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*?(?:-----END [^-]*PRIVATE KEY-----|$)/gu, '[REDACTED PRIVATE KEY]')
    .replace(/\b(Bearer|Basic)\s+[^\s"'<>]+/giu, '$1 [REDACTED]')
    .replace(/([?&](?:access_token|token|api_key|password|secret)=)[^&#\s"']*/giu, '$1[REDACTED]')
    .replace(/(https?:\/\/)[^/\s@]+@/giu, '$1[REDACTED]@')
    .replace(/((?:--)?(?:access[-_]token|api[-_]key|password|secret|token|authorization)["']?\s*[:=]\s*["']?)[^\s,"'}]+/giu, '$1[REDACTED]');
}
export function redactCommandArguments(args, env = process.env) {
  let secretNext = false;
  return args.map(arg => {
    const redact = secretNext;
    secretNext = /^--(?:access[-_]token|api[-_]key|password|secret|token|authorization)$/iu.test(arg);
    return redact ? '[REDACTED]' : redactCommandEvidence(arg, env);
  });
}

export function commandSource(cwd) {
  const git = args => spawnSync('git', ['--no-replace-objects', ...args], {
    cwd, encoding: 'utf8', maxBuffer: 1024 * 1024, timeout: 10_000,
  });
  const head = git(['rev-parse', '--verify', 'HEAD']);
  const root = git(['rev-parse', '--show-toplevel']);
  const dirty = git(['status', '--porcelain', '--untracked-files=normal']);
  return {revision: head.status === 0 && /^[0-9a-f]{40}\s*$/u.test(head.stdout) ? head.stdout.trim() : null,
    root: root.status === 0 ? root.stdout.trim() : null,
    dirty: dirty.status === 0 && !dirty.error ? dirty.stdout.length > 0 : null};
}
function cwdIdentity(cwd) {
  try {
    const path = realpathSync(cwd), stat = lstatSync(path);
    return {path: resolve(cwd), realpath: path, device: String(stat.dev), inode: String(stat.ino)};
  } catch { return {path: resolve(cwd), realpath: null, device: null, inode: null}; }
}
function githubIdentity(env) {
  return {runId: /^\d+$/u.test(env.GITHUB_RUN_ID ?? '') ? env.GITHUB_RUN_ID : null,
    runAttempt: /^\d+$/u.test(env.GITHUB_RUN_ATTEMPT ?? '') ? env.GITHUB_RUN_ATTEMPT : null,
    eventSha: /^[0-9a-f]{40}$/u.test(env.GITHUB_SHA ?? '') ? env.GITHUB_SHA : null,
    job: /^[\w.-]+$/u.test(env.GITHUB_JOB ?? '') ? env.GITHUB_JOB : null};
}

// A unique invocation never reopens or replaces a prior attempt. Initial and
// per-command start records are written before spawn; abrupt runner death leaves
// complete:false. spawnSync's in-memory streams cannot be recovered after that.
export function createCommandEvidence({scratch, revision, cwd = process.cwd(),
  env = process.env, githubOutput, prefix = 'public-query-evidence-'}) {
  const source = commandSource(cwd);
  mkdirSync(scratch, {recursive: true});
  if (!lstatSync(scratch).isDirectory() || lstatSync(scratch).isSymbolicLink()) throw new Error('InvalidEvidenceScratchDirectory');
  const directory = realpathSync(mkdtempSync(join(scratch, prefix)));
  const owned = lstatSync(directory), files = new Map();
  function checkDirectory() {
    const current = lstatSync(directory);
    if (!current.isDirectory() || current.isSymbolicLink() || !same(owned, current) ||
        realpathSync(directory) !== directory) throw new Error('EvidenceDirectoryOwnershipChanged');
  }
  function write(name, value) {
    checkDirectory();
    const path = join(directory, name), previous = files.get(name);
    const fd = openSync(path, constants.O_WRONLY | constants.O_NOFOLLOW |
      (previous ? 0 : constants.O_CREAT | constants.O_EXCL), 0o600);
    try {
      const current = fstatSync(fd);
      if (!current.isFile() || current.nlink !== 1 || (previous && !same(previous, current))) {
        throw new Error('EvidenceFileOwnershipChanged');
      }
      // Each summary update gets a new immutable snapshot, so interrupted writes
      // never erase the last committed observation.
      writeFileSync(fd, value);
      files.set(name, current);
    } finally { closeSync(fd); }
  }
  const summary = {version: 'actql-command-evidence/0.1', invocationId: basename(directory),
    revision: revision ?? source.revision, source, github: githubIdentity(env),
    startedAt: timestamp(), endedAt: null, status: 'running', complete: false,
    commands: [], tarballs: [], artifactsRemoved: false, evidenceErrors: []};
  let snapshot = 0;
  const persist = () => {
    const bytes = JSON.stringify(summary, null, 2) + '\n';
    write(`${String(++snapshot).padStart(4, '0')}.summary.json`, bytes);
    // Do not truncate a replaced file or follow links. Summary updates normally
    // grow, but a shorter final record must not leave trailing JSON bytes.
    checkDirectory();
    const path = join(directory, 'summary.json');
    const previous = files.get('summary.json');
    if (previous) {
      const current = lstatSync(path);
      if (!current.isFile() || current.isSymbolicLink() || current.nlink !== 1 || !same(previous, current)) {
        throw new Error('EvidenceFileOwnershipChanged');
      }
    }
    const fd = openSync(path, constants.O_WRONLY | constants.O_NOFOLLOW |
      (previous ? 0 : constants.O_CREAT | constants.O_EXCL), 0o600);
    try {
      const current = fstatSync(fd);
      if (!current.isFile() || current.nlink !== 1 || (previous && !same(previous, current))) throw new Error('EvidenceFileOwnershipChanged');
      // Truncation is done through the checked descriptor, never a fresh path.
      ftruncateSync(fd, 0);
      writeFileSync(fd, bytes);
      files.set('summary.json', current);
    } finally { closeSync(fd); }
  };
  persist();
  if (githubOutput !== undefined) {
    if (/[\r\n]/u.test(directory)) throw new Error('InvalidEvidenceDirectory');
    appendFileSync(githubOutput, `evidence-directory=${directory}\n`);
  }
  function noteError(error, stage = 'write') {
    summary.evidenceErrors.push({stage, code: errorCode(error)});
    summary.complete = false;
    summary.status = 'failed';
    console.error(`Command evidence write failed (${errorCode(error)}); evidence: ${directory}`);
  }
  function capture(command, args, options = {}, classify) {
    const {cwd: workingDirectory = cwd, env: childEnv = env, ...spawnOptions} = options;
    const id = String(summary.commands.length + 1).padStart(3, '0');
    const outcome = {id, command: redactCommandEvidence(command, childEnv), args: redactCommandArguments(args, childEnv),
      cwd: cwdIdentity(workingDirectory), source: commandSource(cwd),
      startedAt: timestamp(), endedAt: null, elapsedMs: null, status: null, signal: null,
      error: null, complete: false, verificationStatus: null, outputComplete: false};
    summary.commands.push(outcome);
    let writeFailure;
    try { write(`${id}.started.json`, JSON.stringify(outcome, null, 2) + '\n'); persist(); }
    catch (error) { writeFailure = error; noteError(error); }
    const limit = Math.min(spawnOptions.maxBuffer ?? COMMAND_OUTPUT_LIMIT, MAX_COMMAND_OUTPUT_LIMIT);
    outcome.outputLimitBytes = limit;
    const started = performance.now();
    const result = spawnSync(command, args, {...spawnOptions, cwd: workingDirectory,
      env: childEnv, encoding: 'utf8', stdio: 'pipe',
      maxBuffer: limit});
    const checked = classify?.(result);
    Object.assign(outcome, {endedAt: timestamp(), elapsedMs: performance.now() - started,
      status: result.status, signal: result.signal,
      error: result.error ? {code: errorCode(result.error)} : null,
      complete: !result.error && !result.signal,
      verificationStatus: checked?.status ?? (result.error || result.signal ? result.status || 1 : result.status),
      counts: checked?.counts ?? null,
      outputComplete: result.error?.code !== 'ENOBUFS'});
    try {
      for (const stream of ['stdout', 'stderr']) write(`${id}.${stream}.log`,
        Buffer.from(redactCommandEvidence(result[stream] ?? '', childEnv)).subarray(0, limit));
      write(`${id}.result.json`, JSON.stringify(outcome, null, 2) + '\n');
      persist();
    } catch (error) { writeFailure ??= error; noteError(error); }
    return {result, checked, outcome, writeFailure};
  }
  return {directory, summary, persist, capture, checkDirectory, noteError,
    finish(status) {
      summary.endedAt = timestamp();
      summary.status = status;
      summary.complete = status === 'passed' && summary.evidenceErrors.length === 0 &&
        summary.commands.every(command => command.complete && command.verificationStatus === 0);
      if (!summary.complete && status === 'passed') summary.status = 'failed';
      persist();
    }};
}

export async function withPackedQueryEvidence({scratch, revision,
  keepArtifacts = false, githubOutput}, body) {
  const evidence = createCommandEvidence({scratch, revision, githubOutput});
  const {directory, summary, persist} = evidence;
  const root = join(directory, 'artifacts');
  mkdirSync(root);
  const ownedRoot = lstatSync(root);
  summary.keepArtifacts = keepArtifacts;
  persist();
  let failure;
  try {
    await body({root, directory,
      recordTarball(path) {
        summary.tarballs.push({name: basename(path), sha256:
          createHash('sha256').update(readFileSync(path)).digest('hex')});
        persist();
      },
      run(command, args, {cwd = root, env = process.env, timeout = 240_000} = {}) {
        const {result, outcome, writeFailure} = evidence.capture(command, args,
          {cwd, env, timeout, killSignal: 'SIGKILL'});
        if (result.error || result.signal || result.status !== 0) {
          throw Object.assign(new Error(`PackedQueryCommandFailed:${outcome.id}`, {cause: result.error}),
            {code: 'PackedQueryCommandFailed', outcome, evidenceDirectory: directory,
              evidenceError: writeFailure ? errorCode(writeFailure) : null});
        }
        if (writeFailure) throw writeFailure;
        return result.stdout;
      }});
    summary.status = 'passed';
  } catch (error) {
    failure = error;
    summary.status = 'failed';
  } finally {
    try {
      // Keep completeness false until cleanup has also succeeded.
      persist();
      if (!keepArtifacts && summary.evidenceErrors.length === 0) {
        evidence.checkDirectory();
        const current = lstatSync(root);
        if (!current.isDirectory() || current.isSymbolicLink() || !same(ownedRoot, current) ||
            realpathSync(root) !== root) throw new Error('ArtifactDirectoryOwnershipChanged');
        rmSync(root, {recursive: true});
        summary.artifactsRemoved = true;
      }
      evidence.finish(summary.status);
    } catch (cleanupError) {
      evidence.noteError(cleanupError, 'cleanup');
      summary.endedAt = timestamp();
      try { persist(); } catch (writeError) { evidence.noteError(writeError); }
      failure = failure === undefined ? cleanupError :
        Object.assign(new AggregateError([failure, cleanupError], 'PackedQueryEvidenceCleanupFailed', {cause: failure}),
          {code: failure.code, outcome: failure.outcome});
    }
  }
  if (failure !== undefined) throw failure;
  if (!summary.complete) throw new Error('PackedQueryEvidenceIncomplete');
  return directory;
}

// The uploader consumes only this helper's diagnostic files. Reject links and
// oversized files before upload; artifacts/ and arbitrary scratch payloads are excluded.
export function checkCommandEvidenceUpload(directory) {
  const root = lstatSync(directory);
  if (!root.isDirectory() || root.isSymbolicLink() || realpathSync(directory) !== resolve(directory)) {
    throw new Error('InvalidEvidenceUploadDirectory');
  }
  const selected = readdirSync(directory).filter(name =>
    name === 'summary.json' || /\.(?:summary|started|result)\.json$|\.(?:stdout|stderr)\.log$/u.test(name));
  if (!selected.length) throw new Error('MissingEvidenceUploadFiles');
  for (const name of selected) {
    if (!/^(?:summary\.json|[0-9]+\.(?:summary|started|result)\.json|[0-9]+\.(?:stdout|stderr)\.log)$/u.test(name)) {
      throw new Error('UnexpectedEvidenceUploadFile');
    }
    const stat = lstatSync(join(directory, name));
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > MAX_COMMAND_OUTPUT_LIMIT) {
      throw new Error('UnsafeEvidenceUploadFile');
    }
  }
  return selected;
}
