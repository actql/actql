// Temporary Linux fixture diagnosis. Never a package producer or acceptance gate.
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {closeSync, openSync, writeSync} from 'node:fs';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {arch, platform, release} from 'node:os';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const sourceSha = '217d8fa9b31345780bfd3f0fd99d77618a92d6fe';
export const sourceTree = 'fbd4ebef6e3f0536a8ace779df5916c917f0527d';
export const commandArguments = Object.freeze(['--test',
  'scripts/analytic-offset-profiles.test.mjs',
  'scripts/distinct-join-order-source-input.test.mjs',
  'scripts/graph-difference-source-input.test.mjs',
  'scripts/graph-relation-join-source-input.test.mjs',
  'scripts/public-query-profiles.test.mjs',
  'scripts/packed-query-transports.test.mjs',
  'scripts/graph-argument-check.test.mjs',
  'scripts/graph-argument-origin-literals.test.mjs']);

const deadlineMs = 60_000, graceMs = 5000, outputLimit = 8 * 1024 * 1024;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

export function diagnosticExit(report) {
  if (report.stopReason === 'deadline') return 124;
  if (report.stopReason !== undefined || report.spawnError !== undefined) return 70;
  const original = report.native?.parentExit?.exitCode;
  if (report.complete && Number.isInteger(original) && original >= 0 && original <= 255) return original;
  const debuggerCode = report.debuggerExit?.code;
  return Number.isInteger(debuggerCode) && debuggerCode > 0 && debuggerCode <= 255 ? debuggerCode : 70;
}

export async function collect(root, directory) {
  await mkdir(directory, {recursive: true});
  const report = {sourceSha, sourceTree, command: [process.execPath, ...commandArguments],
    node: process.version, platform: platform(), arch: arch(), kernel: release(),
    startedAt: new Date().toISOString(), attempts: 0, instrumented: true,
    workflow: {sha: process.env.GITHUB_SHA, runId: process.env.GITHUB_RUN_ID,
      attempt: process.env.GITHUB_RUN_ATTEMPT, ref: process.env.GITHUB_WORKFLOW_REF},
    commandDeadlineMs: deadlineMs, graceMs, outputLimit, complete: false};
  const save = () => writeFile(resolve(directory, 'result.json'), JSON.stringify(report, null, 2) + '\n');
  await save();
  try {
    assert.equal(process.version, 'v22.22.0');
    assert.equal(platform(), 'linux');
    assert.equal(arch(), 'x64');
    const git = args => {
      const result = spawnSync('git', args, {cwd: root, encoding: 'utf8'});
      assert.equal(result.status, 0, `git ${args[0]} failed`);
      return result.stdout.trim();
    };
    assert.equal(git(['rev-parse', 'HEAD']), sourceSha);
    assert.equal(git(['rev-parse', 'HEAD^{tree}']), sourceTree);
    git(['diff', '--quiet', 'HEAD', '--']);
    git(['diff', '--cached', '--quiet', '--']);
    const members = await Promise.all(commandArguments.slice(1).concat([
      'scripts/fixtures/packed-query-transport-owner.mjs', 'package-lock.json',
      'adapters/connectors/duckdb/node/package-lock.json',
    ]).map(async path => {
      const bytes = await readFile(resolve(root, path));
      return {path, bytes: bytes.length, sha256: hash(bytes)};
    }));
    await writeFile(resolve(directory, 'source.json'), JSON.stringify({sourceSha, sourceTree, members}, null, 2) + '\n');
    const debuggerScript = fileURLToPath(new URL('./diagnose-packed-harness-abort.gdb.py', import.meta.url));
    report.debuggerScriptSha256 = hash(await readFile(debuggerScript));
    report.collectorSha256 = hash(await readFile(fileURLToPath(import.meta.url)));
    const output = openSync(resolve(directory, 'command.stdout.log'), 'wx');
    const errors = openSync(resolve(directory, 'command.stderr.log'), 'wx');
    let child, terminateTimer, deadline, size = 0;
    const stop = reason => {
      if (report.stopReason !== undefined) return;
      report.stopReason = reason;
      try {process.kill(-child.pid, 'SIGTERM');} catch (error) {
        if (error.code !== 'ESRCH') report.stopError = error.code;
      }
      terminateTimer = setTimeout(() => {
        try {process.kill(-child.pid, 'SIGKILL');} catch (error) {
          if (error.code !== 'ESRCH') report.killError = error.code;
        }
      }, graceMs);
    };
    try {
      // Follow all owned test subprocesses so a fatal child still yields a stack.
      // There is exactly one original command invocation; no bare-Node retry.
      child = spawn('gdb', ['--nx', '--batch', '--quiet', '--return-child-result',
        '--command', debuggerScript, '--args', process.execPath, ...commandArguments], {
        cwd: root, detached: true, stdio: ['ignore', 'pipe', 'pipe'],
        env: {...process.env, ACTQL_PACKED_HARNESS_EVIDENCE_DIRECTORY: directory},
      });
      report.attempts = 1;
      report.debuggerPid = child.pid;
      const keep = fd => bytes => {
        const remaining = Math.max(0, outputLimit - size);
        writeSync(fd, bytes.subarray(0, remaining));
        size += bytes.length;
        if (size > outputLimit) stop('output_limit');
      };
      child.stdout.on('data', keep(output));
      child.stderr.on('data', keep(errors));
      deadline = setTimeout(() => stop('deadline'), deadlineMs);
      const result = await new Promise(resolveExit => {
        child.once('error', error => {report.spawnError = error.code;});
        child.once('close', (code, signal) => resolveExit({code, signal}));
      });
      report.debuggerExit = result;
      report.outputBytes = size;
    } finally {
      clearTimeout(deadline);
      clearTimeout(terminateTimer);
      closeSync(output);
      closeSync(errors);
    }
    try {
      report.native = JSON.parse(await readFile(resolve(directory, 'native-events.json'), 'utf8'));
    } catch {report.nativeReportUnavailable = true;}
    report.complete = report.stopReason === undefined && report.spawnError === undefined &&
      report.native?.parentExit?.exitCode !== undefined && report.native.parentExit.exitCode !== null &&
      report.debuggerExit.signal === null && report.debuggerExit.code === report.native.parentExit.exitCode;
    report.exitCode = diagnosticExit(report);
    report.endedAt = new Date().toISOString();
    await save();
    return report.exitCode;
  } catch (error) {
    report.setupError = {name: error.name, code: error.code, message: error.message};
    report.exitCode = 70;
    report.endedAt = new Date().toISOString();
    await save();
    return 70;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 4);
  process.exitCode = await collect(resolve(process.argv[2]), resolve(process.argv[3]));
}
