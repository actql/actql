// Draft PRs run preparation checks; ready PRs retain normal required coverage.
// An exact maintenance inventory may omit whole unrelated job families.
// Selected evidence campaigns retain their complete three-target contract.
import assert from 'node:assert/strict';
import {focusedPattern, eligibleFocusedChanges, readFocusedTests, validateFocusedTests} from './ci-focused-tests.mjs';
import {actionsReader, fullCheckpointJobs, resolveMainBaseline, validateMainBaseline} from './ci-main-base.mjs';
import {appendFileSync, readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const all = ['js', 'wasm', 'native'];
const sha = /^[0-9a-f]{40}$/u;
// Reviewed callers are retained lint tests or manual reporting commands only.
// These files are not runtime/proof semantic inputs (generic checkout identity
// still changes). A new runtime/build/proof caller must remove or re-review its
// registration here before merge; a full run alone does not preserve isolation.
// README is excluded: packed acceptance executes its literal Quickstart blocks.
export const maintenanceFiles = Object.freeze([
  'docs/development.md', 'docs/ci-artifact-analysis.md', 'docs/verification-actions.md',
  // Reviewed prose only: no runtime, build, generator or proof-oracle callers.
  // Generic links, Program examples and version scans remain required in spec
  // and preflight. Adding a semantic consumer requires re-review here.
  'docs/reviews/2026-10-03-graph-host-acquired-input-handoff.md',
  'docs/reviews/2026-10-03-graph-host-owner-fixtures.md',
  'scripts/ci-evidence.mjs', 'scripts/ci-evidence.test.mjs', 'scripts/ci-review.mjs',
  'scripts/ci-timing.mjs', 'scripts/ci-artifacts.mjs', 'scripts/ci-artifacts.test.mjs',
  'scripts/verification-actions.mjs', 'scripts/verification-actions.test.mjs',
  'scripts/worktree-inventory.mjs', 'scripts/worktree-inventory.test.mjs',
]);
const maintenance = new Set(maintenanceFiles);
// Declarations interpret provenance only. Actual ancestry and protected source
// obligations are validated by mandatory preflight, never by this scheduler.
const declarationPath = /^proofs\/relation-pipeline\/foundation-declarations\/([a-z0-9]+(?:-[a-z0-9]+)*)\.json$/u;
const zero = '0'.repeat(40);
function eligibleDeclarations(paths, changes) {
  return paths.length > 0 && paths.every(path => declarationPath.test(path))
    && new Set(paths).size === paths.length && Array.isArray(changes) && changes.length === paths.length
    && changes.every((entry, index) => entry && Object.keys(entry).sort().join(',') === 'after,before,path'
      && entry.path === paths[index]
      && entry.before && Object.keys(entry.before).sort().join(',') === 'mode,object'
      && entry.before.mode === '000000' && entry.before.object === zero
      && entry.after && Object.keys(entry.after).sort().join(',') === 'mode,object'
      && entry.after.mode === '100644' && sha.test(entry.after.object) && entry.after.object !== zero);
}
// Compose only the two already bounded classes, preserving their independent
// identities and obligations. Every path must belong to exactly one inventory.
function eligibleDeclarationSelection(paths, declarations, modifications) {
  const declarationPaths = paths.filter(path => declarationPath.test(path));
  const maintenancePaths = paths.filter(path => maintenance.has(path));
  return declarationPaths.length + maintenancePaths.length === paths.length
    && new Set(paths).size === paths.length
    && eligibleDeclarations(declarationPaths, declarations)
    && (maintenancePaths.length ? eligibleMaintenance(maintenancePaths, modifications) : modifications === null);
}
function canonicalDeclaration(path, contents) {
  const value = JSON.parse(contents);
  assert.equal(contents, `${JSON.stringify(value, null, 2)}\n`, 'Noncanonical declaration JSON');
  assert.equal(value.version, 'actql-foundation-declaration/0.1', 'Unknown declaration schema');
  assert.equal(value.id, declarationPath.exec(path)?.[1], 'Declaration filename/id mismatch');
  assert(['change', 'resolution'].includes(value.kind), 'Unknown declaration kind');
}

export const gateJobs = Object.freeze(['select-targets', 'preflight', 'lint', 'core', 'host', 'client',
  'native', 'spec', 'session-evidence', 'pipeline-evidence', 'native-macos',
  'native-separated-network', 'workers', 'connector-addition', 'duckdb-node', 'focused-tests']);
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
export function pullRequestDraft(event, payload) {
  if (event !== 'pull_request') return null;
  assert(['opened', 'synchronize', 'reopened', 'ready_for_review', 'converted_to_draft'].includes(payload?.action), 'Unsupported PR lifecycle event');
  const draft = payload?.pull_request?.draft;
  assert.equal(typeof draft, 'boolean', 'Missing PR draft state');
  if (payload.action === 'ready_for_review') assert.equal(draft, false, 'Inconsistent ready event');
  if (payload.action === 'converted_to_draft') assert.equal(draft, true, 'Inconsistent draft event');
  return draft;
}
export function selectTargets(paths, {draft = null, event = 'pull_request', nativeMacos = false, failure = null,
  targetSensitiveDiff = false, maintenanceChanges = null, declarationChanges = null, focusedChanges = null, focusedTests = null, mainBaseline = null} = {}) {
  if (mainBaseline !== null) validateMainBaseline(mainBaseline);
  const validPaths = Array.isArray(paths) && paths.every(validPath);
  const full = reason => ({schema: 'actql-ci-targets/0.1', targets: [...all], macos: true, reason,
    profile: 'full', event, paths: validPaths ? [...paths] : [], maintenanceChanges: null, declarationChanges: null, focusedChanges: null, focusedTests: null, mainBaseline});
  if (event === 'pull_request' && draft !== null) {
    assert.equal(typeof draft, 'boolean', 'Invalid PR draft state');
    if (draft) {
      let focused = false;
      if (!failure && focusedTests && eligibleFocusedChanges(paths, focusedChanges)) {
        try { validateFocusedTests(paths, focusedChanges, focusedTests); focused = true; } catch {}
      }
      return {...full('Draft preparation only: normal required verification deferred until ready_for_review; not mergeable'),
        profile: focused ? 'draft-focused' : 'draft', targets: ['js'], macos: false, mainBaseline: null,
        focusedChanges: focused ? focusedChanges : null, focusedTests: focused ? focusedTests : null};
    }
  }
  if (event !== 'pull_request' && !(event === 'push' && mainBaseline)) {
    const result = full(failure ? `Full core verification: ${failure}` : `Full core verification selected for ${event}`);
    // Preserve the existing explicit opt-in for an on-demand working branch.
    if (event === 'workflow_dispatch') result.macos = nativeMacos;
    return result;
  }
  if (failure) return full(`Diff unavailable: ${failure}`);
  if (!Array.isArray(paths) || !paths.length || !paths.every(validPath)) return full('Empty or invalid change inventory');
  if (eligibleMaintenance(paths, maintenanceChanges)) return {...full('Reviewed maintenance files: lint and spec required; runtime and proof families not applicable'),
    profile: 'maintenance', targets: ['js'], macos: false, maintenanceChanges};
  if (eligibleDeclarationSelection(paths, declarationChanges, maintenanceChanges)) return {...full('Canonical declaration additions and optional reviewed maintenance: history preflight, lint and spec required; runtime and semantic proof families not applicable'),
    profile: 'declaration', targets: ['js'], macos: false, declarationChanges, maintenanceChanges};
  if (focusedTests && eligibleFocusedChanges(paths, focusedChanges)) {
    try { validateFocusedTests(paths, focusedChanges, focusedTests); }
    catch { return full('Invalid focused test family inventory'); }
    return {...full('Reviewed fixed-request tests: execute changed files and owning JS family; unrelated runtime/proof families not applicable'),
      profile: 'focused-tests', targets: ['js'], macos: false, focusedChanges, focusedTests};
  }
  if (event === 'push') return full('Main cumulative changes require full runtime target coverage');
  if (targetSensitiveDiff) return full('Target-specific syntax or runtime boundary changed');
  const path = paths.find(path => sensitive.test(path) || !reviewedPortableFiles.has(path));
  if (path) return full(`Target-sensitive or unclassified input: ${path}`);
  return {...full(''), targets: ['js'], macos: false,
    reason: 'Reviewed portable paths: PR core uses JS; full targets and optional macOS require a manual integration checkpoint'};
}
function eligibleMaintenance(paths, changes) {
  return paths.length > 0 && paths.every(path => maintenance.has(path))
    && new Set(paths).size === paths.length && Array.isArray(changes) && changes.length === paths.length
    && changes.every((entry, index) => entry && Object.keys(entry).sort().join(',') === 'after,before,path'
      && entry.path === paths[index] && [entry.before, entry.after].every(identity => identity
        && Object.keys(identity).sort().join(',') === 'mode,object'
        && identity.mode === '100644' && sha.test(identity.object) && identity.object !== '0'.repeat(40))
      && entry.before.object !== entry.after.object);
}
export function validateSelection(selection) {
  assert.deepEqual(Object.keys(selection ?? {}).sort(), ['schema', 'targets', 'macos', 'reason',
    'profile', 'event', 'paths', 'maintenanceChanges', 'declarationChanges', 'focusedChanges', 'focusedTests', 'mainBaseline'].sort(), 'Invalid selection fields');
  assert.equal(selection?.schema, 'actql-ci-targets/0.1');
  assert.deepEqual(selection.targets, selection.targets?.length === 1 ? ['js'] : all);
  assert.equal(typeof selection.macos, 'boolean');
  assert(typeof selection.reason === 'string' && selection.reason.trim());
  assert(['full', 'maintenance', 'declaration', 'focused-tests', 'draft', 'draft-focused'].includes(selection.profile), 'Invalid selection profile');
  assert(typeof selection.event === 'string' && selection.event.length, 'Missing selection event');
  assert(Array.isArray(selection.paths) && selection.paths.every(validPath), 'Invalid selection paths');
  if (selection.mainBaseline !== null) {
    assert.equal(selection.event, 'push', 'Main checkpoint belongs only to push');
    validateMainBaseline(selection.mainBaseline);
  }
  if (selection.profile !== 'full') assert(selection.event === 'pull_request' || selection.event === 'push' && selection.mainBaseline, 'Narrow main selection requires verified checkpoint');
  if (selection.profile === 'maintenance') {
    assert(eligibleMaintenance(selection.paths, selection.maintenanceChanges), 'Invalid maintenance inventory');
    assert.deepEqual(selection.targets, ['js']);
    assert.equal(selection.macos, false);
  } else if (selection.profile !== 'declaration') assert.equal(selection.maintenanceChanges, null, 'Unexpected maintenance inventory');
  if (selection.profile === 'declaration') {
    assert(eligibleDeclarationSelection(selection.paths, selection.declarationChanges, selection.maintenanceChanges), 'Invalid declaration/maintenance inventory');
    assert.deepEqual(selection.targets, ['js']);
    assert.equal(selection.macos, false);
  } else assert.equal(selection.declarationChanges, null, 'Unexpected declaration inventory');
  if (selection.profile.startsWith('draft')) {
    assert.equal(selection.event, 'pull_request', 'Draft profile requires a PR event');
    assert.equal(selection.mainBaseline, null, 'Draft cannot reuse a main checkpoint');
    assert.deepEqual(selection.targets, ['js']);
    assert.equal(selection.macos, false);
  }
  if (['focused-tests', 'draft-focused'].includes(selection.profile)) {
    validateFocusedTests(selection.paths, selection.focusedChanges, selection.focusedTests);
    assert.deepEqual(selection.targets, ['js']);
    assert.equal(selection.macos, false);
  } else {
    assert.equal(selection.focusedChanges, null, 'Unexpected focused change inventory');
    assert.equal(selection.focusedTests, null, 'Unexpected focused family');
  }
  if (selection.event !== 'pull_request' && selection.profile === 'full') {
    assert.deepEqual(selection.targets, all, 'Non-PR targets must remain full');
    if (selection.event !== 'workflow_dispatch') assert.equal(selection.macos, true);
  }
  return selection;
}
export function verifyGate(plan, needs, {event, sourceRevision, draft = null}) {
  assert.deepEqual(Object.keys(plan ?? {}).sort(), ['selection', 'sourceRevision'], 'Invalid plan envelope');
  assert(sha.test(sourceRevision) && plan.sourceRevision === sourceRevision, 'Selection belongs to another checkout');
  const selection = validateSelection(plan.selection);
  assert.equal(selection.event, event, 'Selection belongs to another event');
  assert(draft !== true && !selection.profile.startsWith('draft'),
    'Draft preparation is not merge verification: awaiting ready_for_review to execute normal required coverage');
  if (selection.mainBaseline) assert.equal(selection.mainBaseline.testedSha, sourceRevision, 'Main checkpoint belongs to another tested checkout');
  assert.deepEqual(Object.keys(needs ?? {}).sort(), [...gateJobs].sort(), 'Incomplete gate dependency inventory');
  const lines = [];
  for (const name of gateJobs) {
    const required = ['select-targets', 'preflight', 'lint', 'spec'].includes(name)
      || selection.profile === 'focused-tests' && name === 'focused-tests'
      || selection.profile === 'full' && name !== 'focused-tests' && (name !== 'native-macos' || selection.macos);
    const expected = required ? 'success' : 'skipped';
    assert.equal(needs[name]?.result, expected, `${name}: expected ${expected}`);
    lines.push(`${required ? 'PASS' : 'NOT APPLICABLE'} ${name}: ${required ? 'required job completed' : selection.reason}`);
  }
  return lines;
}
export function readChanges(payload, git = args => execFileSync('git', args,
  {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}), {baseRevision = null} = {}) {
  const base = baseRevision ?? payload?.pull_request?.base?.sha;
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
  let maintenanceChanges = null, declarationChanges = null, focusedChanges = null, focusedTests = null, structuralChange = false;
  const focusedOnly = paths.length > 0 && paths.every(path => focusedPattern.test(path));
  const lightweightOnly = paths.length > 0 && paths.every(path => declarationPath.test(path) || maintenance.has(path));
  if (focusedOnly || lightweightOnly) {
    // Exact raw Git identities distinguish ordinary edits from additions,
    // deletions, renames, symlinks and mode changes. No text/extension guess.
    const raw = git(['diff', '--no-renames', '--raw', '--no-abbrev', '-z', base, head, '--']);
    assert(raw.endsWith('\0'), 'Truncated raw change inventory');
    const records = raw.slice(0, -1).split('\0');
    assert(records.length === paths.length * 2, 'Incomplete raw change inventory');
    const changes = [];
    for (let index = 0; index < records.length; index += 2) {
      const match = /^:(\d{6}) (\d{6}) ([0-9a-f]{40}) ([0-9a-f]{40}) ([A-Z][0-9]*)$/u.exec(records[index]);
      assert(match && records[index + 1] === paths[index / 2], 'Invalid raw change inventory');
      const [, beforeMode, afterMode, beforeObject, afterObject, status] = match;
      changes.push({path: records[index + 1], before: {mode: beforeMode, object: beforeObject},
        after: {mode: afterMode, object: afterObject}});
      if (!(focusedOnly ? ['A', 'M'].includes(status) : status === (declarationPath.test(records[index + 1]) ? 'A' : 'M'))) changes[index / 2].before.mode = 'unsupported';
    }
    const declarations = changes.filter(change => declarationPath.test(change.path));
    const modifications = changes.filter(change => maintenance.has(change.path));
    if (eligibleDeclarationSelection(paths, declarations, modifications.length ? modifications : null)) {
      for (const change of declarations) canonicalDeclaration(change.path, git(['show', `${head}:${change.path}`]));
      declarationChanges = declarations;
      maintenanceChanges = modifications.length ? modifications : null;
    } else if (focusedOnly && eligibleFocusedChanges(paths, changes)) {
      focusedTests = readFocusedTests(paths, changes, git);
      if (focusedTests) focusedChanges = changes;
      else structuralChange = true;
    } else if (eligibleMaintenance(paths, changes)) maintenanceChanges = changes;
    else structuralChange = true;
  }
  const boundary = /\b(?:extern|supported_targets|targets|native-stub|unsafe|malloc|realloc|sizeof)\b|\b(?:free|release|retain|dispose|cleanup)\s*\(|#(?:cfg|external|borrow|owned)\b|\btarget\s*=|\b\w*(?:cid|sha256|canonical|preimage|hash)\w*\b/iu;
  // A registered filename must not hide a symlink, executable-mode change,
  // addition or deletion. Inspect Git headers as well as changed source text.
  let targetSensitiveDiff = structuralChange || /^(?:old mode|new mode|new file mode|deleted file mode) /mu.test(patch) || boundary.test(changedLines);
  // A body-only edit under an unchanged target/ownership annotation still
  // affects that target. Check both versions; new/deleted source is full.
  for (const path of paths.filter(path => path.startsWith('src/') && path.endsWith('.mbt'))) {
    try {
      targetSensitiveDiff ||= [base, head].some(revision => boundary.test(git(['show', `${revision}:${path}`])));
    } catch { targetSensitiveDiff = true; }
  }
  return {paths, targetSensitiveDiff, maintenanceChanges, declarationChanges, focusedChanges, focusedTests, head};
}
async function main() {
  if (process.argv[2] === 'gate') {
    const lines = verifyGate(JSON.parse(process.env.CI_PLAN), JSON.parse(process.env.RESULTS),
      {event: process.env.GITHUB_EVENT_NAME, sourceRevision: process.env.GITHUB_SHA,
        draft: pullRequestDraft(process.env.GITHUB_EVENT_NAME,
          process.env.GITHUB_EVENT_NAME === 'pull_request'
            ? JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8')) : null)});
    console.log(lines.join('\n'));
    if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, lines.join('\n') + '\n');
    return;
  }
  assert(!process.argv[2], 'Usage: ci-targets.mjs [gate]');
  const draft = pullRequestDraft(process.env.GITHUB_EVENT_NAME,
    process.env.GITHUB_EVENT_NAME === 'pull_request'
      ? JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8')) : null);
  let changes = {paths: []}, failure = null, mainBaseline = null;
  if (process.env.GITHUB_EVENT_NAME === 'pull_request') {
    try { changes = readChanges(JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'))); }
    catch (error) { failure = error.message; }
  }
  if (process.env.GITHUB_EVENT_NAME === 'push') {
    try {
      const payload = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
      assert.equal(payload.ref, 'refs/heads/main', 'Not a main push');
      const baseline = await resolveMainBaseline({testedSha: process.env.GITHUB_SHA,
        repository: process.env.GITHUB_REPOSITORY, repositoryId: payload.repository?.id,
        requiredJobs: fullCheckpointJobs(gateJobs.filter(name => name !== 'focused-tests')),
        request: actionsReader({repository: process.env.GITHUB_REPOSITORY, token: process.env.GITHUB_TOKEN})});
      if (baseline.baseSha) {
        mainBaseline = baseline;
        changes = readChanges(payload, undefined, {baseRevision: baseline.baseSha});
      } else failure = baseline.reason;
    } catch { failure = 'Main checkpoint or cumulative diff unavailable'; }
  }
  const selected = validateSelection(selectTargets(changes.paths, {event: process.env.GITHUB_EVENT_NAME, draft,
    nativeMacos: process.env.NATIVE_MACOS === 'true', failure, targetSensitiveDiff: changes.targetSensitiveDiff,
    maintenanceChanges: changes.maintenanceChanges, declarationChanges: changes.declarationChanges,
    focusedChanges: changes.focusedChanges, focusedTests: changes.focusedTests, mainBaseline}));
  const sourceRevision = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  assert(sha.test(sourceRevision) && sourceRevision === process.env.GITHUB_SHA, 'Unexpected tested checkout');
  const plan = {sourceRevision, selection: selected};
  appendFileSync(process.env.GITHUB_OUTPUT, `targets=${JSON.stringify(selected.targets)}\nmacos=${selected.macos}\nprofile=${selected.profile}\nplan=${JSON.stringify(plan)}\n`);
  console.log(JSON.stringify(selected, null, 2));
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY,
    `Job profile: ${selected.profile}\n\nCore targets when selected: ${selected.targets.join(', ')}\n\nmacOS: ${selected.macos ? 'required' : 'not applicable for this run'}\n\n${selected.reason}\n\nUnselected families produce no execution evidence. Selected proof campaigns retain all three targets.\n`);
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) await main();
