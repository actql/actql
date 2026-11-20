// The complete original test-file selection, with strict execution accounting.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readdirSync, realpathSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nodeTestArguments, testExecutionResult} from './test-execution.mjs';

type TestResult = Parameters<typeof testExecutionResult>[3];
type FileSummary = {file?: string; counts: Record<string, number>};
type OutputStream = Pick<NodeJS.WriteStream, 'write'>;

export function sessionControlFiles(root: string) {
  const files = readdirSync(resolve(root, 'proofs/ci-evidence'))
    .filter(name => name.endsWith('.test.mjs')).sort()
    .map(name => 'proofs/ci-evidence/' + name);
  assert(files.length > 0, 'Empty Session control selection');
  return files;
}

export function verifySessionControls(root: string, files: readonly string[], result: TestResult):
  ReturnType<typeof testExecutionResult>['counts'] {
  assert(files.length > 0 && new Set(files).size === files.length, 'Empty or duplicate Session selection');
  const checked = testExecutionResult('node', process.execPath, nodeTestArguments(files), result);
  assert.equal(checked.status, 0, checked.diagnostic);
  const summaries = (result.stdout ?? '').split(/\r?\n/u)
    .filter(line => line.startsWith('ACTQL_TEST_SUMMARY '))
    .map(line => JSON.parse(line.slice('ACTQL_TEST_SUMMARY '.length)) as FileSummary)
    .filter(value => value.file !== undefined);
  const directory = realpathSync(root);
  assert.deepEqual(summaries.map(value => resolve(directory, value.file!)).sort(),
    files.map(file => resolve(directory, file)).sort(), 'Missing, duplicate or foreign Session file summary');
  for (const {file, counts} of summaries) {
    assert(counts.tests > 0 && counts.tests === counts.passed &&
      ['failed', 'cancelled', 'skipped', 'todo'].every(key => counts[key] === 0),
    'Session file did not execute every case successfully: ' + file);
  }
  return checked.counts;
}

export async function writeSessionControlOutput(result: TestResult,
  output: OutputStream = process.stdout, error: OutputStream = process.stderr) {
  // Failed verification throws synchronously. Finish both pipe writes first
  // so the original failing cases and final summaries survive that exit.
  for (const [stream, text] of [[output, result.stdout], [error, result.stderr]] as const) {
    await new Promise<void>((resolve, reject) => stream.write(text ?? '', issue => issue ? reject(issue) : resolve()));
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 2, 'Session controls do not accept narrowing arguments');
  const root = fileURLToPath(new URL('../', import.meta.url));
  const files = sessionControlFiles(root);
  const result = spawnSync(process.execPath, nodeTestArguments(files), {
    cwd: root, env: process.env, encoding: 'utf8', timeout: 59 * 60 * 1000,
    maxBuffer: 64 * 1024 * 1024, killSignal: 'SIGKILL',
  });
  await writeSessionControlOutput(result);
  const counts = verifySessionControls(root, files, result);
  console.log('ACTQL_SESSION_CONTROLS ' + JSON.stringify({files: files.length, counts}));
}
