// Small, real Git repositories keep the provenance tests independent of the
// production composer. In particular, no Git command or digest is mocked.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

export const DECLARATION_DIRECTORY = 'proofs/relation-pipeline/foundation-declarations';
export const PACKAGE = 'package.json';
export const CI = '.github/workflows/ci.yml';
export const RENAME = 'proofs/relation-pipeline/rename.mjs';
export const DISTINCT = 'proofs/relation-pipeline/distinct.mjs';
export const ADDED = 'proofs/relation-pipeline/new-evidence.mjs';
export const PROTECTED_PATHS = [PACKAGE, CI, RENAME, DISTINCT];
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

export function packageBytes(scripts = {}) {
  return `${JSON.stringify({ private: true, scripts: { 'check:base': 'node base.mjs', ...scripts } }, null, 2)}\n`;
}

export function ciBytes(commands = []) {
  return ['name: fixture', 'on: push', 'jobs:', '  proofs:', '    runs-on: ubuntu-latest',
    '    steps:', '      - run: npm run check:base',
    ...commands.map(command => `      - run: npm run ${command}`), ''].join('\n');
}

export class FoundationRepository {
  constructor(t) {
    this.root = mkdtempSync(join(tmpdir(), 'actql-foundation-git-'));
    t.after(() => rmSync(this.root, { recursive: true, force: true }));
    this.tick = 0;
    // Do not inherit a caller's Git index, author, hooks or global configuration.
    this.env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_')));
    Object.assign(this.env, { GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null',
      GIT_AUTHOR_NAME: 'Foundation Fixture', GIT_AUTHOR_EMAIL: 'foundation@example.invalid',
      GIT_COMMITTER_NAME: 'Foundation Fixture', GIT_COMMITTER_EMAIL: 'foundation@example.invalid',
      LC_ALL: 'C', TZ: 'UTC' });
    this.git('init', '--quiet', '--initial-branch=main');
    this.git('config', 'core.autocrlf', 'false');
    this.git('config', 'core.filemode', 'true');
    this.git('config', 'commit.gpgsign', 'false');
    this.git('config', 'gc.auto', '0');
    this.write(PACKAGE, packageBytes());
    this.write(CI, ciBytes());
    this.write(RENAME, 'export const rename = "baseline";\n');
    this.write(DISTINCT, 'export const distinct = "baseline";\n');
    this.checkpoint = this.commit('Immutable foundation checkpoint');
  }

  run(args, options = {}) {
    const date = new Date(Date.UTC(2025, 0, 1, 0, 0, this.tick)).toISOString();
    return spawnSync('git', args, { cwd: this.root, encoding: 'utf8',
      env: { ...this.env, GIT_AUTHOR_DATE: date, GIT_COMMITTER_DATE: date }, ...options });
  }

  git(...args) {
    const result = this.run(args);
    assert.equal(result.status, 0, `git ${args.join(' ')} failed:\n${result.stderr}\n${result.stdout}`);
    return result.stdout.trim();
  }

  write(path, bytes) {
    mkdirSync(dirname(join(this.root, path)), { recursive: true });
    writeFileSync(join(this.root, path), bytes);
  }

  remove(path) { rmSync(join(this.root, path)); }
  chmod(path, mode) { chmodSync(join(this.root, path), mode); }
  head() { return this.git('rev-parse', 'HEAD'); }
  parents(revision) { return this.git('show', '-s', '--format=%P', revision).split(' ').filter(Boolean); }
  branch(name, revision = this.head()) { this.git('branch', name, revision); }
  checkout(revision) { this.git('checkout', '--quiet', revision); }

  commit(message) {
    this.git('add', '--all');
    this.tick++;
    this.git('commit', '--quiet', '--no-verify', '-m', message);
    return this.head();
  }

  source(files, message = 'Change protected source') {
    for (const [path, bytes] of Object.entries(files)) {
      if (bytes === null) this.remove(path);
      else this.write(path, bytes);
    }
    return this.commit(message);
  }

  state(revision, path) {
    const tree = this.git('ls-tree', revision, '--', path);
    if (!tree) return { revision, digest: null, mode: null };
    const [, mode, type, object] = /^(\d+) (\w+) ([a-f0-9]+)\t/.exec(tree) ?? [];
    assert.equal(type, 'blob', `Fixture path ${path} must be a blob`);
    const result = this.run(['cat-file', 'blob', object], { encoding: null });
    assert.equal(result.status, 0);
    return { revision, digest: sha256(result.stdout), mode };
  }

  declaration(id, revision, paths, { kind = 'change', inputs, reason = `Rationale for ${id}` } = {}) {
    const parents = this.parents(revision);
    const declaration = { version: 'actql-foundation-declaration/0.1', id, revision, parents,
      changes: paths.map(path => {
        const after = this.state(revision, path);
        return { path, before: parents.map(parent => this.state(parent, path)),
          afterDigest: after.digest, afterMode: after.mode, reason };
      }), kind };
    if (inputs !== undefined) declaration.inputs = inputs;
    return declaration;
  }

  declarationPath(id) { return `${DECLARATION_DIRECTORY}/${id}.json`; }
  writeDeclaration(declaration, filename = declaration.id) {
    this.write(this.declarationPath(filename), `${JSON.stringify(declaration, null, 2)}\n`);
  }

  record(declaration, filename = declaration.id) {
    this.writeDeclaration(declaration, filename);
    return this.commit(`Declare ${filename}`);
  }

  merge(branch, files = {}, { ours = false } = {}) {
    const args = ['merge', '--no-ff', '--no-commit'];
    if (ours) args.push('--strategy=ours');
    args.push(branch);
    const result = this.run(args);
    // Deliberately resolve real merge conflicts with independent expected bytes.
    assert.ok(result.status === 0 || (result.status === 1 && Object.keys(files).length),
      `Unexpected merge failure:\n${result.stderr}\n${result.stdout}`);
    for (const [path, bytes] of Object.entries(files)) this.write(path, bytes);
    return this.commit(`Integrate ${branch}`);
  }
}

export function singleChange(t) {
  const repo = new FoundationRepository(t);
  const bytes = packageBytes({ 'check:rename': 'node rename.test.mjs' });
  const revision = repo.source({ [PACKAGE]: bytes });
  const declaration = repo.declaration('register-rename', revision, [PACKAGE],
    { reason: 'Register rename evidence without changing its acceptance boundary' });
  return { repo, revision, declaration, bytes };
}

export function disjointBranches(t, { ours = false, preserveDeclarations = false } = {}) {
  const repo = new FoundationRepository(t);
  repo.branch('distinct', repo.checkpoint);
  const renameBytes = 'export const rename = "new rename proof";\n';
  const renameRevision = repo.source({ [RENAME]: renameBytes }, 'Extend rename evidence');
  const rename = repo.declaration('extend-rename', renameRevision, [RENAME],
    { reason: 'Preserve rename evidence rationale' });
  repo.record(rename);
  repo.checkout('distinct');
  const distinctBytes = 'export const distinct = "new distinct proof";\n';
  const distinctRevision = repo.source({ [DISTINCT]: distinctBytes }, 'Extend distinct evidence');
  const distinct = repo.declaration('extend-distinct', distinctRevision, [DISTINCT],
    { reason: 'Preserve distinct evidence rationale' });
  repo.record(distinct);
  repo.checkout('main');
  const files = preserveDeclarations
    ? { [repo.declarationPath(distinct.id)]: `${JSON.stringify(distinct, null, 2)}\n` } : {};
  const merge = repo.merge('distinct', files, { ours });
  return { repo, rename, distinct, merge, renameBytes, distinctBytes };
}

export function overlappingBranches(t, { recordResolution = true, includeRenameDeclaration = true, inputs,
  mergedPackage = packageBytes({ 'check:rename': 'node rename.test.mjs', 'check:distinct': 'node distinct.test.mjs' }) } = {}) {
  const repo = new FoundationRepository(t);
  repo.branch('distinct', repo.checkpoint);
  const renameRevision = repo.source({
    [PACKAGE]: packageBytes({ 'check:rename': 'node rename.test.mjs' }),
    [CI]: ciBytes(['check:rename']), [RENAME]: 'export const rename = "reviewed rename";\n',
  }, 'Register rename proof and CI check');
  const rename = repo.declaration('register-rename', renameRevision, [PACKAGE, CI, RENAME],
    { reason: 'Keep the rename proof and its independent CI registration' });
  if (includeRenameDeclaration) repo.record(rename);
  repo.checkout('distinct');
  const distinctRevision = repo.source({
    [PACKAGE]: packageBytes({ 'check:distinct': 'node distinct.test.mjs' }),
    [CI]: ciBytes(['check:distinct']), [DISTINCT]: 'export const distinct = "reviewed distinct";\n',
  }, 'Register distinct proof and CI check');
  const distinct = repo.declaration('register-distinct', distinctRevision, [PACKAGE, CI, DISTINCT],
    { reason: 'Keep the distinct proof and its independent CI registration' });
  repo.record(distinct);
  repo.checkout('main');
  const mergedCI = ciBytes(['check:rename', 'check:distinct']);
  const merge = repo.merge('distinct', { [PACKAGE]: mergedPackage, [CI]: mergedCI });
  const resolution = repo.declaration('resolve-registrations', merge, [PACKAGE, CI], {
    kind: 'resolution', inputs: inputs ?? ['register-distinct', 'register-rename'],
    reason: 'Retain both independent test registrations and both CI checks in the integrated bytes',
  });
  if (recordResolution) repo.record(resolution);
  return { repo, rename, distinct, resolution, merge, mergedPackage, mergedCI };
}

// Model the three independently reviewed registrations that motivated #180:
// #172 public check, #173 native release recovery, and #175 DISTINCT capacity.
// This is source-composition evidence, not execution of their product tests.
export function threePullRequestBranches(t, { omitFinalInput } = {}) {
  const repo = new FoundationRepository(t);
  const publicScripts = { 'check:distribution-client': 'node --test adapters/host-node/client-check.test.mjs' };
  const nativeScripts = { 'check:native-http-client': 'node scripts/test-native-resident-site.mjs --release-recovery-only' };
  const capacityScripts = { 'check:pipeline-capacity': 'node --test proofs/relation-pipeline/capacity.test.mjs' };
  repo.branch('pr-173-native-release');
  repo.branch('pr-175-capacity');
  const publicRevision = repo.source({ [PACKAGE]: packageBytes(publicScripts) }, 'PR 172 public check registration');
  const publicCheck = repo.declaration('pr-172-public-check', publicRevision, [PACKAGE],
    { reason: 'Register public Local and HTTP check outcome regression tests from PR 172' });
  repo.record(publicCheck);
  repo.checkout('pr-173-native-release');
  const nativeRevision = repo.source({ [PACKAGE]: packageBytes(nativeScripts) }, 'PR 173 native release registration');
  const nativeRelease = repo.declaration('pr-173-native-release', nativeRevision, [PACKAGE],
    { reason: 'Retain stopped-holder native release recovery regression tests from PR 173' });
  repo.record(nativeRelease);
  repo.checkout('pr-175-capacity');
  const capacityRevision = repo.source({ [PACKAGE]: packageBytes(capacityScripts),
    [CI]: ciBytes(['check:pipeline-capacity']), [DISTINCT]: 'export const distinct = "conditional structural and custody evidence";\n',
  }, 'PR 175 DISTINCT capacity and CI registration');
  const capacity = repo.declaration('pr-175-capacity', capacityRevision, [PACKAGE, CI, DISTINCT],
    { reason: 'Register conditional DISTINCT structure and custody evidence and its CI check from PR 175' });
  repo.record(capacity);
  repo.checkout('main');
  const firstMerge = repo.merge('pr-173-native-release', { [PACKAGE]: packageBytes({ ...publicScripts, ...nativeScripts }) });
  const firstResolution = repo.declaration('resolve-public-native', firstMerge, [PACKAGE], {
    kind: 'resolution', inputs: ['pr-172-public-check', 'pr-173-native-release'],
    reason: 'Keep public check and native release registrations in the same package',
  });
  repo.record(firstResolution);
  const scripts = { ...publicScripts, ...nativeScripts, ...capacityScripts };
  const mergedPackage = packageBytes(scripts);
  const secondMerge = repo.merge('pr-175-capacity', { [PACKAGE]: mergedPackage });
  const inputs = ['pr-172-public-check', 'pr-173-native-release', 'pr-175-capacity', 'resolve-public-native'];
  const finalResolution = repo.declaration('resolve-all-three', secondMerge, [PACKAGE], {
    kind: 'resolution', inputs: inputs.filter(id => id !== omitFinalInput),
    reason: 'Keep public check, native release and DISTINCT capacity registrations with all prior rationales',
  });
  repo.record(finalResolution);
  return { repo, publicCheck, nativeRelease, capacity, firstResolution, finalResolution,
    firstMerge, secondMerge, scripts, mergedPackage, mergedCI: ciBytes(['check:pipeline-capacity']), inputs };
}

// Keep an in-flight branch's original supporting SHA when main advances its
// immutable checkpoint. The old main-side rationale is frozen checkpoint data;
// only the incoming post-checkpoint declaration belongs in resolution inputs.
export function olderInFlightBranch(t, { recordSide = true, recordResolution = true } = {}) {
  const repo = new FoundationRepository(t);
  const fork = repo.checkpoint;
  repo.branch('old-in-flight', fork);
  const historicalPath = 'proofs/relation-pipeline/frozen-checkpoint.json';
  const historicalReason = 'Previously accepted public check registration is preserved at the migration checkpoint';
  const publicScripts = { 'check:public': 'node public-check.test.mjs' };
  const checkpointBytes = `${JSON.stringify({ version: 'fixture-checkpoint/0.1',
    path: PACKAGE, digest: sha256(packageBytes(publicScripts)), reason: historicalReason }, null, 2)}\n`;
  repo.checkpoint = repo.source({ [PACKAGE]: packageBytes(publicScripts), [historicalPath]: checkpointBytes },
    'Advance immutable checkpoint while side branch is in flight');
  repo.write('MIGRATION.md', 'Foundation declaration migration\n');
  repo.commit('Migrate main without rewriting the in-flight branch');
  repo.checkout('old-in-flight');
  const nativeScripts = { 'check:native': 'node native-release.test.mjs' };
  const sideRevision = repo.source({ [PACKAGE]: packageBytes(nativeScripts) }, 'Original in-flight native registration');
  const side = repo.declaration('old-side-native', sideRevision, [PACKAGE],
    { reason: 'Keep the original in-flight native release registration and supporting commit' });
  if (recordSide) repo.record(side);
  repo.checkout('main');
  const mergedPackage = packageBytes({ ...publicScripts, ...nativeScripts });
  const merge = repo.merge('old-in-flight', { [PACKAGE]: mergedPackage });
  const resolution = repo.declaration('resolve-old-in-flight', merge, [PACKAGE], {
    kind: 'resolution', inputs: recordSide ? [side.id] : [],
    reason: 'Retain the frozen checkpoint registration and the independently declared old-branch registration',
  });
  if (recordResolution) repo.record(resolution);
  return { repo, fork, historicalPath, historicalReason, checkpointBytes, side, sideRevision,
    resolution, merge, mergedPackage, immutable: [{ path: historicalPath, revision: repo.checkpoint }] };
}
