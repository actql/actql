// The Salesforce Effect cross-version acceptance: save Host state with the
// pinned previous version's product code, then resume it with this
// checkout's. Usage (from the repository root, MoonBit toolchain on PATH):
//   node adapters/connectors/salesforce/test/cross-version/run-cross-version.mjs
//
// The previous version is checked out in a temporary worktree. Only this
// checkout's test tooling (the generator, its state module, its child Host
// and the test org) is added to it, and the run refuses unless git shows no
// product path changed there. It installs its own dependencies and builds
// its own runtime. A Run captured by another standard runtime is refused by
// design, so the run refuses when the two runtimes differ: the pinned version
// must then be re-pinned to one built from the current runtime. Generation
// and resume share one temporary root, the same user and the same machine,
// as a Host's authority requires.
//
// Every failure fails the acceptance; nothing is skipped.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {cpSync, existsSync, mkdtempSync, readFileSync, rmSync, symlinkSync}
  from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

// The latest `main` before the Salesforce Effect moved to the installed row
// Effect. Re-pin it to such a `main` when the standard runtime changes; the
// runtime check below is never relaxed.
export const PREVIOUS_VERSION = '0b99f32987d6cf1622c1290c99c650913f88a51c';

const repository = fileURLToPath(new URL('../../../../../', import.meta.url));
const tooling = [
  'adapters/connectors/salesforce/test/cross-version/update-state.mjs',
  'adapters/connectors/salesforce/test/cross-version/update-state.host-child.mjs',
  'adapters/connectors/salesforce/test/cross-version/update-state.local-child.mjs',
  'adapters/connectors/salesforce/test/cross-version/generate-update-state.mjs',
  'adapters/connectors/salesforce/test/salesforce-effect-site.fixture.mjs',
];
const runtimePackages = ['src/connectors_builtin_node',
  'src/connectors/salesforce/host_node', 'src/connectors/github/host_node',
  'src/connectors/duckdb/host_node', 'src/checkpoint_runtime_node'];
const runtimeBundle = '_build/js/release/build/connectors_builtin_node/' +
  'connectors_builtin_node.js';

const run = (command, args, cwd, extra = {}) => execFileSync(command, args,
  {cwd, stdio: ['ignore', 'inherit', 'inherit'], ...extra});
const output = (command, args, cwd) => execFileSync(command, args,
  {cwd, encoding: 'utf8'}).trim();
const digest = path => `sha256:${createHash('sha256')
  .update(readFileSync(path)).digest('hex')}`;
const fail = message => {
  throw new Error(message);
};

const root = mkdtempSync(join(tmpdir(), 'actql-sf-cross-version-'));
const previous = join(root, 'previous');
const state = join(root, 'state');
let status = 1;
try {
  try { output('git', ['cat-file', '-e', `${PREVIOUS_VERSION}^{commit}`],
    repository); }
  catch {
    run('git', ['fetch', '--no-tags', 'origin', PREVIOUS_VERSION],
      repository);
  }
  run('git', ['worktree', 'add', '--detach', previous, PREVIOUS_VERSION],
    repository);
  for (const path of tooling) {
    cpSync(join(repository, path), join(previous, path));
  }
  // Each NUL-separated entry is two status characters, a space and a path.
  const changed = execFileSync('git', ['status', '--porcelain', '-z'],
    {cwd: previous, encoding: 'utf8'}).split('\0').filter(Boolean)
    .map(entry => entry.slice(3))
    .filter(path => !path.startsWith('adapters/connectors/salesforce/test/'));
  if (changed.length !== 0) {
    fail(`product paths differ from ${PREVIOUS_VERSION}: ${changed.join(', ')}`);
  }
  // The previous version's own dependencies and runtime.
  run('npm', ['ci', '--ignore-scripts'], previous);
  const duckdb = 'adapters/connectors/duckdb/node';
  if (output('git', ['rev-parse', `${PREVIOUS_VERSION}:${duckdb}/package-lock.json`], repository) ===
      output('git', ['hash-object', join(repository, duckdb,
        'package-lock.json')], repository) &&
      existsSync(join(repository, duckdb, 'node_modules'))) {
    // The same locked third-party packages; no workspace code.
    symlinkSync(join(repository, duckdb, 'node_modules'),
      join(previous, duckdb, 'node_modules'));
  } else {
    run('npm', ['ci'], join(previous, duckdb));
  }
  run('moon', ['build', '--target', 'js', '--release', ...runtimePackages],
    previous);
  run('moon', ['build', '--target', 'js', '--release', ...runtimePackages],
    repository);
  const previousRuntime = digest(join(previous, runtimeBundle));
  const currentRuntime = digest(join(repository, runtimeBundle));
  if (previousRuntime !== currentRuntime) {
    fail(`the standard runtime changed since ${PREVIOUS_VERSION} ` +
      `(${previousRuntime} -> ${currentRuntime}); a Run captured by another ` +
      'runtime is refused by design. Re-pin PREVIOUS_VERSION.');
  }
  run('node', [join(previous,
    'adapters/connectors/salesforce/test/cross-version/generate-update-state.mjs'),
  state], previous);
  run('node', ['--test', join(repository,
    'adapters/connectors/salesforce/test/cross-version/update-state.resume.test.mjs')],
  repository, {env: {...process.env,
    ACTQL_UPDATE_CROSS_VERSION_STATE: state}});
  status = 0;
} catch (error) {
  console.error(`cross-version acceptance failed: ${error?.message ?? error}`);
} finally {
  if (status === 0) {
    try { run('git', ['worktree', 'remove', '--force', previous], repository); }
    catch { /* the successful temporary root is removed below */ }
    rmSync(root, {recursive: true, force: true});
  } else {
    console.error(`Failed cross-version evidence retained: ${root}`);
  }
}
process.exit(status);
