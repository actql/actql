// PRs use JS for ordinary portable changes. main retains every target.
// This selects only the core matrix and macOS job; evidence campaigns retain
// their complete, same-attempt JS/wasm/native acceptance contract.
import assert from 'node:assert/strict';
import {appendFileSync, readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const all = ['js', 'wasm', 'native'];
const validPath = path => typeof path === 'string' && path.length > 0 && !/[\0\r\n]/u.test(path)
  && !path.startsWith('/') && !path.split('/').some(part => ['', '.', '..'].includes(part));
// Canonical identity, runtime ownership, platform/FFI and build changes keep
// every core target and macOS. New/unclassified areas also default to full.
const sensitive = /^(?:\.github\/|vendor\/|proofs\/|spec\/|portability\/|docs\/(?:spec|reviews)\/)|^(?:toolchain\.json|moon\.mod|package(?:-lock)?\.json)$|(?:^|\/)(?:moon\.pkg|package(?:-lock)?\.json|[^/]*(?:build|link)[^/]*|[^/]*(?:native|wasm|_js\.|ffi|identity|canonical|custody|ownership|owner|owned|publication|lifetime|recovery|capacity|resource|memory|allocation|cleanup|retained|scratch|sqlite|sha256)[^/]*)|^src\/(?:cmd\/|platform_native\/|managed_[^/]+\/|bounded_[^/]+\/|execution_relation\/|connectors\/local\/|(?:encode|decode)_[^/]+\/|value_(?:contract|admission)\/)|\.(?:c|h|cc|cpp|a|so|dylib|wasm)$/iu;
// Eligibility is an exact, reviewed inventory, never a directory or extension
// heuristic. New files and configuration files stay full until reviewed here.
// source_span/span.mbt is the portable Span data declaration; its manifest
// enables all three targets without imports or target-specific source.
// worktree-inventory.mjs is standalone, read-only metadata reporting.
const reviewedPortableFiles = new Set([
  'README.md', 'LICENSE', 'CONTRIBUTING.md', 'AGENTS.md', 'CLAUDE.md',
  'src/source_span/span.mbt',
  'scripts/worktree-inventory.mjs',
]);
export function selectTargets(paths, {event = 'pull_request', nativeMacos = false, failure = null,
  targetSensitiveDiff = false} = {}) {
  const full = reason => ({schema: 'actql-ci-targets/1', targets: [...all], macos: true, reason});
  if (event !== 'pull_request') {
    const result = full(`Full core verification selected for ${event}`);
    // Preserve the existing explicit opt-in for an on-demand working branch.
    if (event === 'workflow_dispatch') result.macos = nativeMacos;
    return result;
  }
  if (failure) return full(`Diff unavailable: ${failure}`);
  if (!Array.isArray(paths) || !paths.length || !paths.every(validPath)) return full('Empty or invalid change inventory');
  if (targetSensitiveDiff) return full('Target-specific syntax or runtime boundary changed');
  const path = paths.find(path => sensitive.test(path) || !reviewedPortableFiles.has(path));
  if (path) return full(`Target-sensitive or unclassified input: ${path}`);
  return {schema: 'actql-ci-targets/1', targets: ['js'], macos: false,
    reason: 'Reviewed portable paths: PR core uses JS; full targets and macOS selected on main'};
}
export function validateSelection(selection) {
  assert.equal(selection?.schema, 'actql-ci-targets/1');
  assert.deepEqual(selection.targets, selection.targets?.length === 1 ? ['js'] : all);
  assert.equal(typeof selection.macos, 'boolean');
  assert(typeof selection.reason === 'string' && selection.reason.trim());
  return selection;
}
export function readChanges(payload, git = args => execFileSync('git', args,
  {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024})) {
  const base = payload?.pull_request?.base?.sha;
  assert.match(base ?? '', /^[0-9a-f]{40}$/u, 'Missing PR base SHA');
  const head = git(['rev-parse', 'HEAD']).trim();
  assert.match(head, /^[0-9a-f]{40}$/u, 'Missing tested checkout SHA');
  // No rename detection: both deleted old and added new paths stay visible.
  // Local Git has no REST changed-files cap. The checkout is the PR merge tree.
  const output = git(['diff', '--no-renames', '--name-only', '-z', base, head, '--']);
  assert(output === '' || output.endsWith('\0'), 'Truncated change inventory');
  const patch = git(['diff', '--no-renames', '--unified=0', base, head, '--']);
  const changedLines = patch.split('\n').filter(line => /^[+-](?![+-])/u.test(line)).join('\n');
  const paths = output.split('\0').filter(Boolean);
  const boundary = /\b(?:extern|supported_targets|targets|native-stub|unsafe|malloc|realloc|sizeof)\b|\b(?:free|release|retain|dispose|cleanup)\s*\(|#(?:cfg|external|borrow|owned)\b|\btarget\s*=|\b\w*(?:cid|sha256|canonical|preimage|hash)\w*\b/iu;
  // A registered filename must not hide a symlink, executable-mode change,
  // addition or deletion. Inspect Git headers as well as changed source text.
  let targetSensitiveDiff = /^(?:old mode|new mode|new file mode|deleted file mode) /mu.test(patch) || boundary.test(changedLines);
  // A body-only edit under an unchanged target/ownership annotation still
  // affects that target. Check both versions; new/deleted source is full.
  for (const path of paths.filter(path => path.startsWith('src/') && path.endsWith('.mbt'))) {
    try {
      targetSensitiveDiff ||= [base, head].some(revision => boundary.test(git(['show', `${revision}:${path}`])));
    } catch { targetSensitiveDiff = true; }
  }
  return {paths, targetSensitiveDiff};
}
function main() {
  let changes = {paths: []}, failure = null;
  if (process.env.GITHUB_EVENT_NAME === 'pull_request') {
    try { changes = readChanges(JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'))); }
    catch (error) { failure = error.message; }
  }
  const selected = validateSelection(selectTargets(changes.paths, {event: process.env.GITHUB_EVENT_NAME,
    nativeMacos: process.env.NATIVE_MACOS === 'true', failure, targetSensitiveDiff: changes.targetSensitiveDiff}));
  appendFileSync(process.env.GITHUB_OUTPUT, `targets=${JSON.stringify(selected.targets)}\nmacos=${selected.macos}\n`);
  console.log(JSON.stringify(selected, null, 2));
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY,
    `Core targets: ${selected.targets.join(', ')}\n\nmacOS: ${selected.macos ? 'required' : 'not applicable for this run'}\n\n${selected.reason}\n\nProof campaigns retain all three targets when they run.\n`);
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
