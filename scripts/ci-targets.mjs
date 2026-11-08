// Main integration uses full coverage; PRs select their applicable checks.
// An exact maintenance inventory may omit whole unrelated job families.
// Selected evidence campaigns retain their complete three-target contract.
import assert from 'node:assert/strict';
import {snapshotDirectories, snapshotFiles} from '../proofs/relation-pipeline/inventory.mjs';
import {focusedPattern, eligibleFocusedChanges, readFocusedTests, validateFocusedTests} from './ci-focused-tests.mjs';
import {appendFileSync, readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {moonGraphCandidate, readMoonTestPlan, validateMoonTestPlan, nonMoonRequirements} from './ci-moon-test-plan.mjs';
import {readmeQuickstart} from './readme-quickstart.mjs';

const all = ['js', 'wasm', 'native'];
const sha = /^[0-9a-f]{40}$/u;
// Reviewed callers are retained lint tests or manual reporting commands only.
// These files are not runtime/proof semantic inputs (generic checkout identity
// still changes). A new runtime/build/proof caller must remove or re-review its
// registration here before merge; a full run alone does not preserve isolation.
// README is excluded: packed acceptance executes its literal Quickstart blocks.
export const maintenanceFiles = Object.freeze([
  // Prose-only contribution/CI guidance. Generic links/examples remain in spec.
  'CONTRIBUTING.md', 'docs/contributing/README.md', 'docs/ci-client.md',
  'docs/development.md', 'docs/ci-artifact-analysis.md', 'docs/verification-actions.md',
  // Reviewed prose only: no runtime, build, generator or proof-oracle callers.
  // Generic links, Program examples and version scans remain required in spec
  // and preflight. Adding a semantic consumer requires re-review here.
  'docs/reviews/2026-10-03-graph-host-acquired-input-handoff.md',
  'docs/reviews/2026-10-03-graph-host-owner-fixtures.md',
  'scripts/ci-evidence.mjs', 'scripts/ci-evidence.test.mjs', 'scripts/ci-review.mjs',
  'scripts/ci-timing.mjs', 'scripts/ci-artifacts.mjs', 'scripts/ci-artifacts.test.mjs',
  // Offline cost display is consumed only by the existing artifact reporter;
  // proof producers and final acceptance do not import this projection.
  'scripts/ci-session-costs.mjs', 'scripts/ci-session-costs.test.mjs',
  'scripts/verification-actions.mjs', 'scripts/verification-actions.test.mjs',
  'scripts/worktree-inventory.mjs', 'scripts/worktree-inventory.test.mjs',
  // Reviewed callback-only units. Their implementation helpers are also used
  // by packed/public consumers and deliberately remain full-coverage inputs.
  'examples/infer-evaluation/evaluate.test.mjs',
  'examples/infer-evaluation/compare-source-instructions.test.mjs',
  // Pure report assessment and synthetic oracle tests, all owned by lint.
  // No runtime, compiler, normal producer or proof imports this implementation.
  'scripts/operation-performance.mjs', 'scripts/operation-performance.test.mjs',
  'scripts/operation-performance-policy.test.mjs',
]);
const maintenance = new Set(maintenanceFiles);
export const gateJobs = Object.freeze(['select-targets', 'preflight', 'lint', 'core', 'host', 'client',
  'native-cli-installed', 'native-cli-linux-local', 'native', 'spec', 'session-evidence', 'pipeline-evidence', 'pipeline-validation', 'native-macos', 'python-wheels',
  'native-separated-network', 'workers', 'connector-addition', 'duckdb-node', 'focused-tests', 'main-performance', 'health-quick']);
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
// Deep campaigns use their real source snapshot plus orchestration and safety
// boundaries. The snapshot currently includes ALL Core source and vendor code;
// narrowing that closure requires a separate proof-input review. Unknown roots
// remain deep. This is scheduling, not evidence reuse or a passed proof claim.
export function deepProofRequired(selection) {
  validateSelection(selection);
  if (selection.profile !== 'full') return false;
  if (['workflow_dispatch', 'schedule'].includes(selection.event) || !selection.paths.length) return true;
  return selection.paths.some(path => {
    if (snapshotFiles.includes(path) || snapshotDirectories.some(root => path === root || path.startsWith(`${root}/`))) return true;
    if (sensitive.test(path) || /^(?:scripts|proofs|spec|portability|\.github)\//u.test(path)) return true;
    // Integration paths can still own resources, build configuration or proof
    // inputs. Only an exact reviewed nondependency may omit deep campaigns.
    return !reviewedPortableFiles.has(path) && !maintenance.has(path);
  });
}
export function gateJobRequired(selection, name) {
  if (['select-targets', 'preflight', 'lint', 'spec'].includes(name)) return true;
  if (['main-performance', 'health-quick'].includes(name)) return selection.event === 'push';
  if (name === 'focused-tests') return ['focused-tests', 'draft-focused'].includes(selection.profile);
  if (name === 'python-wheels') return pythonWheelAcceptanceRequired(selection);
  if (['session-evidence', 'pipeline-evidence'].includes(name)) return deepProofRequired(selection);
  return selection.profile === 'full' && (name !== 'native-macos' || selection.macos);
}

// A targeted Draft acceptance lane, not a claim of complete Draft product coverage.
// Shared core changes still receive full applicable verification when Ready/main.
const pythonWheelInputs = new Set([
  '.github/workflows/ci.yml', '.github/actions/setup-toolchain/action.yml',
  'scripts/ci-targets.mjs', 'scripts/ci-targets.test.mjs', 'scripts/ci-preflight.mjs',
  'scripts/ci-preflight.test.mjs', 'scripts/ci-focused-tests.mjs',
  'scripts/ci-python-wheels.py', 'scripts/test_ci_python_wheels.py',
  'scripts/fixtures/ci-python-installed-audit.py', 'scripts/fixtures/ci-python-installed-health.py',
  'scripts/fixtures/ci-python-installed-run.py',
  'scripts/fixtures/python-product-installed.py', 'scripts/fixtures/python-local-duckdb-physical.py',
  'scripts/fixtures/python-local-platform-vm-original.py',
  'scripts/build-python-product-wheels.py', 'scripts/produce-python-local-runtime.py',
  'scripts/compile-python-local-image.py', 'scripts/python_release_cohort.py',
  'scripts/prepare-python-local-runtime.py', 'scripts/generate-local-wasm-abi.py',
  'scripts/python_interface_inventory.py', 'scripts/release-version.mjs',
  'scripts/setup-moonbit.mjs', 'toolchain.json', 'moon.mod', 'package.json', 'package-lock.json',
]);
export function pythonWheelAcceptanceRequired(selection) {
  validateSelection(selection);
  if (selection.profile === 'full') return true;
  if (!selection.profile.startsWith('draft')) return false;
  // Failed/unavailable diff cannot silently omit the lane. --no-renames keeps
  // deleted old paths and added new paths in this same source-bound inventory.
  return selection.paths.length === 0 || selection.paths.some(path => pythonWheelInputs.has(path)
    || /^packages\/python-(?:product|sdk|local-runtime)\//u.test(path));
}
export function pullRequestDraft(event, payload) {
  if (event !== 'pull_request') return null;
  assert(['opened', 'synchronize', 'reopened', 'ready_for_review', 'converted_to_draft'].includes(payload?.action), 'Unsupported PR lifecycle event');
  const draft = payload?.pull_request?.draft;
  assert.equal(typeof draft, 'boolean', 'Missing PR draft state');
  if (payload.action === 'ready_for_review') assert.equal(draft, false, 'Inconsistent ready event');
  if (payload.action === 'converted_to_draft') assert.equal(draft, true, 'Inconsistent draft event');
  return draft;
}
export function selectTargets(paths, {draft = null, event = 'pull_request', mainIntegration = event === 'push', nativeMacos = false, failure = null,
  targetSensitiveDiff = false, maintenanceChanges = null, focusedChanges = null, focusedTests = null,
  moonTests = null, moonGraphFailure = null} = {}) {
  const validPaths = Array.isArray(paths) && paths.every(validPath);
  const focusedPaths = validPaths ? partitionFocusedPaths(paths, maintenanceChanges) : null;
  const full = reason => ({schema: 'actql-ci-targets/0.1', targets: [...all], macos: true, reason,
    profile: 'full', event, paths: validPaths && !failure ? [...paths] : [], maintenanceChanges: null, focusedChanges: null, focusedTests: null});
  // Main runtime integration is unconditional; only deep campaigns use the
  // current push diff. No previous-success lookup or ancestry search is used.
  if (mainIntegration) {
    assert(['push', 'workflow_dispatch'].includes(event), 'Invalid main integration event');
    const result = full('Main integration requires every runtime family; deep campaigns follow their inputs');
    if (event === 'workflow_dispatch') result.macos = nativeMacos;
    return result;
  }
  if (event === 'pull_request' && draft !== null) {
    assert.equal(typeof draft, 'boolean', 'Invalid PR draft state');
    if (draft) {
      let focused = false;
      if (!failure && focusedTests && focusedPaths && eligibleFocusedChanges(focusedPaths, focusedChanges)) {
        try { validateFocusedTests(focusedPaths, focusedChanges, focusedTests); focused = true; } catch {}
      }
      return {...full('Draft preparation with targeted Python acceptance when applicable; full verification deferred until ready_for_review; not mergeable'),
        profile: focused ? 'draft-focused' : 'draft', targets: ['js'], macos: false,
        maintenanceChanges: focused ? maintenanceChanges : null,
        focusedChanges: focused ? focusedChanges : null, focusedTests: focused ? focusedTests : null};
    }
  }
  if (event !== 'pull_request') {
    const result = full(failure ? `Full core verification: ${failure}` : `Full core verification selected for ${event}`);
    // Preserve the existing explicit opt-in for an on-demand working branch.
    if (event === 'workflow_dispatch') result.macos = nativeMacos;
    return result;
  }
  if (failure) return full(`Diff unavailable: ${failure}`);
  if (!Array.isArray(paths) || !paths.length || !paths.every(validPath)) return full('Empty or invalid change inventory');
  if (eligibleMaintenance(paths, maintenanceChanges)) return {...full('Reviewed maintenance files: lint and spec required; runtime and proof families not applicable'),
    profile: 'maintenance', targets: ['js'], macos: false, maintenanceChanges};
  if (focusedTests && focusedPaths && eligibleFocusedChanges(focusedPaths, focusedChanges)) {
    try { validateFocusedTests(focusedPaths, focusedChanges, focusedTests); }
    catch { return full('Invalid focused test family inventory'); }
    return {...full('Reviewed fixed-request tests: execute changed files and owning JS family; unrelated runtime/proof families not applicable'),
      profile: 'focused-tests', targets: ['js'], macos: false, maintenanceChanges, focusedChanges, focusedTests};
  }
  if (targetSensitiveDiff) return full('Target-specific syntax or runtime boundary changed');
  if (moonTests && moonGraphCandidate(paths)) {
    try { validateMoonTestPlan(moonTests); }
    catch { return full('Invalid compiler-owned Moon test plan'); }
    return {...full('Compiler package reverse dependencies select test execution; whole checks and original Native profiles/product/proof owners remain required'), moonTests};
  }
  if (moonGraphFailure) return full(`Moon dependency discovery unavailable: ${moonGraphFailure}`);
  const path = paths.find(path => sensitive.test(path) || !reviewedPortableFiles.has(path));
  if (path) {
    const owners = nonMoonRequirements(paths).map(owner => owner.name);
    return full(`Target-sensitive or unclassified input: ${path}${owners.length ? `; retained owners: ${owners.join(', ')}` : ''}`);
  }
  return {...full(''), targets: ['js'], macos: false,
    reason: 'Reviewed portable paths: PR core uses JS; full targets run on main integration; optional macOS can be requested manually'};
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
// Existing reviewed profiles compose by union: lint/spec plus the owning
// focused family. Every path and original Git identity must be accounted for;
// an unknown path or structural maintenance edit still falls back to full.
function partitionFocusedPaths(paths, maintenanceChanges) {
  const focused = paths.filter(path => focusedPattern.test(path));
  const lightweight = paths.filter(path => maintenance.has(path));
  if (!focused.length || focused.length + lightweight.length !== paths.length ||
      (lightweight.length ? !eligibleMaintenance(lightweight, maintenanceChanges) : maintenanceChanges !== null)) return null;
  return focused;
}

export function validateSelection(selection) {
  assert.deepEqual(Object.keys(selection ?? {}).sort(), ['schema', 'targets', 'macos', 'reason',
    'profile', 'event', 'paths', 'maintenanceChanges', 'focusedChanges', 'focusedTests',
    ...(Object.hasOwn(selection ?? {}, 'moonTests') ? ['moonTests'] : [])].sort(), 'Invalid selection fields');
  assert.equal(selection?.schema, 'actql-ci-targets/0.1');
  assert.deepEqual(selection.targets, selection.targets?.length === 1 ? ['js'] : all);
  assert.equal(typeof selection.macos, 'boolean');
  assert(typeof selection.reason === 'string' && selection.reason.trim());
  assert(['full', 'maintenance', 'focused-tests', 'draft', 'draft-focused'].includes(selection.profile), 'Invalid selection profile');
  assert(typeof selection.event === 'string' && selection.event.length, 'Missing selection event');
  assert(Array.isArray(selection.paths) && selection.paths.every(validPath), 'Invalid selection paths');
  if (Object.hasOwn(selection, 'moonTests')) {
    assert.equal(selection.profile, 'full'); assert.equal(selection.event, 'pull_request');
    assert.deepEqual(selection.targets, all); assert.equal(selection.macos, true);
    assert(moonGraphCandidate(selection.paths)); validateMoonTestPlan(selection.moonTests);
  }
  if (selection.profile !== 'full') assert.equal(selection.event, 'pull_request', 'Narrow selection requires a PR event');
  const focused = ['focused-tests', 'draft-focused'].includes(selection.profile);
  if (selection.profile === 'maintenance') {
    assert(eligibleMaintenance(selection.paths, selection.maintenanceChanges), 'Invalid maintenance inventory');
    assert.deepEqual(selection.targets, ['js']);
    assert.equal(selection.macos, false);
  } else if (!focused) assert.equal(selection.maintenanceChanges, null, 'Unexpected maintenance inventory');
  if (selection.profile.startsWith('draft')) {
    assert.equal(selection.event, 'pull_request', 'Draft profile requires a PR event');
    assert.deepEqual(selection.targets, ['js']);
    assert.equal(selection.macos, false);
  }
  if (focused) {
    const focusedPaths = partitionFocusedPaths(selection.paths, selection.maintenanceChanges);
    assert(focusedPaths, 'Invalid focused/maintenance path inventory');
    validateFocusedTests(focusedPaths, selection.focusedChanges, selection.focusedTests);
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
  assert.deepEqual(Object.keys(needs ?? {}).sort(), [...gateJobs].sort(), 'Incomplete gate dependency inventory');
  const lines = [];
  for (const name of gateJobs) {
    const required = gateJobRequired(selection, name);
    const expected = required ? 'success' : 'skipped';
    assert.equal(needs[name]?.result, expected, `${name}: expected ${expected}`);
    lines.push(`${required ? 'PASS' : 'NOT APPLICABLE'} ${name}: ${required ? 'required job completed' : selection.reason}`);
  }
  assert(draft !== true && !selection.profile.startsWith('draft'),
    'Draft preparation is not merge verification: awaiting ready_for_review to execute normal required coverage');
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
  let maintenanceChanges = null, focusedChanges = null, focusedTests = null, structuralChange = false;
  const focusedPaths = paths.filter(path => focusedPattern.test(path));
  const lightweightPaths = paths.filter(path => maintenance.has(path));
  const reviewedOnly = paths.length > 0 && focusedPaths.length + lightweightPaths.length === paths.length;
  if (reviewedOnly) {
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
      if (!(focusedPattern.test(records[index + 1]) ? ['A', 'M'].includes(status) : status === 'M')) changes[index / 2].before.mode = 'unsupported';
      // Packed consumers execute this exact Quickstart. Prose is independent;
      // changed/removed executable blocks require their normal product owners.
      if (records[index + 1] === 'docs/development.md' && status === 'M') {
        try {
          assert.deepEqual(readmeQuickstart(git(['show', beforeObject])),
            readmeQuickstart(git(['show', afterObject])));
        } catch { changes[index / 2].before.mode = 'unsupported'; }
      }
    }
    const focused = changes.filter(change => focusedPattern.test(change.path));
    const lightweight = changes.filter(change => maintenance.has(change.path));
    if (focusedPaths.length && eligibleFocusedChanges(focusedPaths, focused) &&
        (!lightweightPaths.length || eligibleMaintenance(lightweightPaths, lightweight))) {
      focusedTests = readFocusedTests(focusedPaths, focused, git);
      if (focusedTests) {
        focusedChanges = focused;
        maintenanceChanges = lightweightPaths.length ? lightweight : null;
      } else structuralChange = true;
    } else if (!focusedPaths.length && eligibleMaintenance(paths, changes)) maintenanceChanges = changes;
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
  return {paths, targetSensitiveDiff, maintenanceChanges, focusedChanges, focusedTests, head};
}
// Exactly the event's endpoints, never a previous successful run or ancestor.
// --no-renames retains both sides of renames and deletions. Failure is handled
// by the caller as an unknown diff, which requires the complete deep campaign.
export function readPushChanges(payload, testedRevision, git = args => execFileSync('git', args,
  {encoding: 'utf8', maxBuffer: 32 * 1024 * 1024})) {
  assert.equal(payload.ref, 'refs/heads/main', 'Not a main push');
  assert(sha.test(testedRevision), 'Missing tested revision');
  assert.equal(payload.after, testedRevision, 'Different pushed revision');
  assert(sha.test(payload.before ?? '') && !/^0+$/u.test(payload.before), 'Unavailable push base');
  assert.equal(git(['rev-parse', 'HEAD']).trim(), testedRevision, 'Different tested checkout');
  const output = git(['diff', '--no-renames', '--name-only', '-z', payload.before, testedRevision, '--']);
  assert(output === '' || output.endsWith('\0'), 'Truncated push change inventory');
  const paths = output.split('\0').filter(Boolean);
  assert(paths.every(validPath), 'Malformed push change inventory');
  return {paths};
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
  assert(!process.argv[2] || process.argv[2] === 'moon-graph-candidate', 'Usage: ci-targets.mjs [gate|moon-graph-candidate]');
  const draft = pullRequestDraft(process.env.GITHUB_EVENT_NAME,
    process.env.GITHUB_EVENT_NAME === 'pull_request'
      ? JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8')) : null);
  let changes = {paths: []}, failure = null;
  if (process.env.GITHUB_EVENT_NAME === 'pull_request') {
    try { changes = readChanges(JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'))); }
    catch (error) { failure = error.message; }
  }
  if (process.env.GITHUB_EVENT_NAME === 'push') {
    const payload = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
    assert.equal(payload.ref, 'refs/heads/main', 'Not a main push');
    assert.equal(payload.after, process.env.GITHUB_SHA, 'Different pushed revision');
    try { changes = readPushChanges(payload, process.env.GITHUB_SHA); }
    catch (error) { failure = error.message; changes = {paths: []}; }
  }
  const candidate = process.env.GITHUB_EVENT_NAME === 'pull_request' && draft === false && !failure &&
    !changes.targetSensitiveDiff && moonGraphCandidate(changes.paths);
  if (process.argv[2] === 'moon-graph-candidate') {
    appendFileSync(process.env.GITHUB_OUTPUT, `required=${candidate}\n`);
    return;
  }
  let moonTests = null, moonGraphFailure = null;
  if (candidate) {
    try {
      const payload = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
      moonTests = readMoonTestPlan(changes.paths, payload.pull_request.base.sha);
    } catch (error) { moonGraphFailure = error.message; }
  }
  const selected = validateSelection(selectTargets(changes.paths, {event: process.env.GITHUB_EVENT_NAME, draft,
    mainIntegration: process.env.GITHUB_EVENT_NAME === 'push' ||
      process.env.GITHUB_EVENT_NAME === 'workflow_dispatch' && process.env.GITHUB_REF === 'refs/heads/main',
    nativeMacos: process.env.NATIVE_MACOS === 'true', failure, targetSensitiveDiff: changes.targetSensitiveDiff,
    maintenanceChanges: changes.maintenanceChanges,
    focusedChanges: changes.focusedChanges, focusedTests: changes.focusedTests, moonTests, moonGraphFailure}));
  const sourceRevision = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  assert(sha.test(sourceRevision) && sourceRevision === process.env.GITHUB_SHA, 'Unexpected tested checkout');
  const plan = {sourceRevision, selection: selected};
  appendFileSync(process.env.GITHUB_OUTPUT, `targets=${JSON.stringify(selected.targets)}\nmacos=${selected.macos}\nprofile=${selected.profile}\nmoon_test_selection=${Boolean(selected.moonTests)}\ndeep_proofs=${deepProofRequired(selected)}\npython_wheels=${pythonWheelAcceptanceRequired(selected)}\nplan=${JSON.stringify(plan)}\n`);
  console.log(JSON.stringify(selected, null, 2));
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY,
    `Job profile: ${selected.profile}\n\nCore targets when selected: ${selected.targets.join(', ')}\n\nNative macOS diagnostic: ${selected.macos ? 'required' : 'not applicable for this run'}\n\nPython wheel acceptance: ${pythonWheelAcceptanceRequired(selected) ? "required" : "not selected"}\n\n${selected.reason}\n\nDeep proof campaigns: ${deepProofRequired(selected) ? "required" : "not applicable to changed inputs"}.\n\nUnselected families produce no execution evidence. Selected proof campaigns retain all three targets.\n`);
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) await main();
