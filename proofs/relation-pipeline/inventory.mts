import { readFileSync, readdirSync, lstatSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import { createHash } from 'node:crypto';
import type { BinaryLike } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import type { TranspileOutput, TranspileOptions } from 'typescript';
import {checkProofRunnerExtension} from './proof-runner-extension.mjs';
import type {ProofRunnerExtension} from './proof-runner-extension.mjs';

type AuthoredInputs = { entries: { has(path: string): boolean }; read(path: string): Buffer };
type EmitScope = 'pipeline' | 'inventory';
type DerivedOutput = { path: string; mode: number; bytes: Buffer };
type ReadInput = (path: string) => Buffer | string;
type Snapshot = { sources: Record<string, string>; digest: string };
type Baseline = {
  revision: string;
  modelExtension?: {
    revision: string; checker: string; priorDigest: string; files: Record<string, string>;
    observation: { session: number; chain: number; stopAndPause: number; total: number };
  };
  unchangedCommon: Record<string, string>;
  runnerExtension?: ProofRunnerExtension;
  existingGroup: { path: string; test: string }[];
};

export const hash = (value: BinaryLike): string => createHash('sha256').update(value).digest('hex');
export const snapshotDirectories: readonly string[] = Object.freeze(['src', 'vendor', 'proofs/bounded-session', 'proofs/relation-chain', 'proofs/relation-capacity', 'proofs/relation-pipeline']);
export const scratchRuntime = 'scripts/owned-scratch.mjs';
export const scratchOriginal = 'scripts/owned-scratch.mts';
export const scratchCompilerConfigs: readonly string[] = Object.freeze(['tsconfig.base.json', 'tsconfig.tooling.json']);
export const resourceRuntime = 'adapters/host-node/ordinary-node-resource-runtime.cjs';
export const resourceOriginal = 'adapters/host-node/ordinary-node-resource-runtime.cts';
const inventoryTypeScriptStems = ['inventory', 'proof-runner-extension'];
const pipelineTypeScriptStems = [
  'proof-parts', 'execution-names', 'execution-names.test',
  'workspaces', 'workspaces.test', 'fixtures/execution-driver',
  'execute', 'execute.test', 'execution-original', 'executor-close.test', 'fixture', 'fixture.test',
  'inventory.test', 'current-source.test', 'proof-runner-extension.test', ...inventoryTypeScriptStems,
];
function selectedPipelineTypeScript(has: AuthoredInputs['entries']['has'], scope: EmitScope = 'pipeline') {
  const stems = (scope === 'inventory' ? inventoryTypeScriptStems : pipelineTypeScriptStems)
    .map(name => `proofs/relation-pipeline/${name}`);
  return stems.filter(stem => has(stem + '.mts')).map(stem => {
    const source = stem + '.mts', runtime = stem + '.mjs', declaration = stem + '.d.mts';
    assert(!has(runtime) && !has(declaration), `Ambiguous authored pipeline TypeScript input: ${source}`);
    return {source, runtime, declaration};
  });
}
const sharedSnapshotFiles = ['scripts/native-cxx-link-driver.sh', 'scripts/ar', 'toolchain.json', 'moon.mod', 'package.json', 'package-lock.json', '.github/workflows/ci.yml', 'docs/spec/language.md', 'docs/spec/execution.md'];
// Applicability sees both authored profiles, including removal of a legacy
// path. A snapshot binds only the members selected for its actual source.
export const snapshotFiles: readonly string[] = Object.freeze([...sharedSnapshotFiles, scratchRuntime, scratchOriginal, resourceRuntime, resourceOriginal, ...scratchCompilerConfigs]);
export function snapshotFilePaths(has: AuthoredInputs['entries']['has']): string[] {
  const scratch = has(scratchOriginal), resource = has(resourceOriginal);
  return [...sharedSnapshotFiles, scratch ? scratchOriginal : scratchRuntime,
    resource ? resourceOriginal : resourceRuntime,
    ...(scratch || resource || pipelineTypeScriptStems.some(stem => has(`proofs/relation-pipeline/${stem}.mts`)) ? scratchCompilerConfigs : [])];
}
function proofCompiler(tree: AuthoredInputs) {
  const ts: typeof import('typescript') = createRequire(import.meta.url)('typescript');
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const inputs = new Map(scratchCompilerConfigs.map(path => [resolve(root, path), tree.read(path).toString('utf8')]));
  const lock = JSON.parse(tree.read('package-lock.json').toString('utf8'));
  assert.equal(ts.version, lock.packages['node_modules/typescript'].version, 'Wrong locked proof compiler');
  const file = resolve(root, 'tsconfig.tooling.json'), readFile = (path: string) => inputs.get(resolve(path));
  const settings = ts.readConfigFile(file, readFile);
  assert(!settings.error, 'Invalid proof compiler configuration');
  const config = ts.parseJsonConfigFileContent(settings.config, {...ts.sys, readFile}, root, undefined, file);
  assert(!config.errors.length && config.options.noEmitOnError &&
    !config.options.noEmit && !config.options.emitDeclarationOnly && !config.options.outDir && !config.options.outFile,
  'Expected the canonical in-place proof compiler configuration');
  return {ts, input(original: string): {source: string; options: TranspileOptions} {
    const fileName = resolve(root, original);
    assert(config.fileNames.includes(fileName), `Unselected proof compiler input: ${original}`);
    return {source: tree.read(original).toString('utf8'),
      options: {fileName, compilerOptions: config.options, reportDiagnostics: true}};
  }};
}
function derivedOutput(ts: typeof import('typescript'), result: TranspileOutput, path: string): DerivedOutput {
  assert(!result.diagnostics!.some(item => item.category === ts.DiagnosticCategory.Error), 'Cannot emit selected original proof input');
  return {path, mode: 0o644, bytes: Buffer.from(result.outputText)};
}
// Compile only the selected pair from exact supplied bytes. The caller
// records the derived runtime separately from the Git input inventory.
export function runtimeEmit(tree: AuthoredInputs, original: string, runtime: string): DerivedOutput {
  const {ts, input} = proofCompiler(tree);
  const {source, options} = input(original);
  return derivedOutput(ts, ts.transpileModule(source, options), runtime);
}
export function pipelineTypeScriptEmits(tree: AuthoredInputs, scope: EmitScope = 'pipeline'): DerivedOutput[] {
  const selected = selectedPipelineTypeScript(path => tree.entries.has(path), scope);
  if (!selected.length) return [];
  const {ts, input} = proofCompiler(tree);
  return selected.flatMap(({source: original, runtime, declaration}) => {
    const {source, options} = input(original);
    assert(options.compilerOptions!.declaration, 'Missing pipeline declaration configuration');
    return [
      derivedOutput(ts, ts.transpileModule(source, options), runtime),
      derivedOutput(ts, ts.transpileDeclaration(source, options), declaration),
    ];
  });
}
function files(path: string): string[] {
  return readdirSync(path, { withFileTypes: true }).flatMap(e => e.isDirectory()
    ? files(join(path, e.name)) : e.isFile() ? [join(path, e.name)] : []);
}
function snapshotPaths(root: string, allowMissing = false): string[] {
  const present = (path: string) => !allowMissing || lstatSync(path, {throwIfNoEntry: false}) !== undefined;
  const has = (path: string) => lstatSync(join(root, path), {throwIfNoEntry: false}) !== undefined;
  const extras = snapshotFilePaths(has);
  if (has(resourceOriginal)) extras.push(resourceRuntime);
  return snapshotDirectories.map(p => join(root, p)).filter(present).flatMap(files)
    .concat(extras
      .map(p => join(root, p)).filter(present))
    .filter(p => relative(root, p) !== 'src/query_integration/relation_pipeline_batch_wbtest.mbt').sort();
}
export function snapshot(root: string): Snapshot {
  const paths = snapshotPaths(root);
  const sources = Object.fromEntries(paths.map(p => [relative(root, p), hash(readFileSync(p))]));
  return { sources, digest: hash(JSON.stringify(sources)) };
}
// Bind current evidence to actual tracked HEAD inputs. No ancestor walk or
// per-commit declaration is needed; shallow checkouts are sufficient.
export function checkCurrentSource(root: string): string {
  const git = (args: string[]) => spawnSync('git', ['--no-replace-objects', ...args],
    {cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  const head = git(['rev-parse', '--verify', 'HEAD^{commit}']);
  assert.equal(head.status, 0, 'Missing current source commit');
  const tree = git(['ls-tree', '-rtz', head.stdout.trim()]);
  assert.equal(tree.status, 0, 'Cannot inspect current source tree');
  const entries = tree.stdout.split('\0').filter(Boolean);
  const tracked = new Set(entries.map(entry => entry.slice(entry.indexOf('\t') + 1)));
  assert(!(tracked.has(scratchOriginal) && tracked.has(scratchRuntime)), 'Ambiguous authored pipeline scratch input');
  assert(!(tracked.has(resourceOriginal) && tracked.has(resourceRuntime)), 'Ambiguous authored Node Resource bridge');
  const allowedEmits = new Set(selectedPipelineTypeScript(path => tracked.has(path))
    .flatMap(({runtime, declaration}) => [runtime, declaration]));
  const selectedFiles = snapshotFilePaths(path => tracked.has(path));
  const inputs = [...snapshotDirectories, ...selectedFiles,
    ':(exclude)src/query_integration/relation_pipeline_batch_wbtest.mbt'];
  const difference = git(['diff', '--quiet', 'HEAD', '--', ...inputs, scratchRuntime, scratchOriginal, resourceRuntime, resourceOriginal]);
  assert.equal(difference.status, 0, 'Current proof inputs differ from tested HEAD');
  const untracked = git(['ls-files', '--others', '-z', '--', ...inputs]);
  assert.equal(untracked.status, 0, 'Cannot inspect current source inputs');
  const unexpected = untracked.stdout.split('\0').filter(path => path && !allowedEmits.has(path));
  assert.deepEqual(unexpected, [], 'Untracked current proof inputs');
  // Index flags cannot establish the bytes that the runner actually reads.
  // Bind only this HEAD's regular inputs; no historical declarations are used.
  const selected = [...snapshotDirectories, ...selectedFiles];
  const checkedFiles = new Set();
  for (const entry of entries) {
    const match = /^(\d+) (\S+) ([0-9a-f]+)\t([\s\S]+)$/.exec(entry);
    assert(match, 'Invalid current source tree entry');
    const [, mode, type, object, path] = match;
    if (path === 'src/query_integration/relation_pipeline_batch_wbtest.mbt') continue;
    if (!selected.some(input => path === input || path.startsWith(input + '/') ||
        input.startsWith(path + '/'))) continue;
    const file = join(root, path), stat = lstatSync(file);
    if (type === 'tree') {
      assert(!selectedFiles.includes(path) && stat.isDirectory() && !stat.isSymbolicLink(),
        `Non-regular current proof input directory: ${path}`);
      continue;
    }
    assert(!snapshotDirectories.includes(path) &&
      !selected.some(input => input.startsWith(path + '/')),
    `Non-regular current proof input directory: ${path}`);
    assert(type === 'blob' && ['100644', '100755'].includes(mode),
      `Non-regular current proof input: ${path}`);
    assert(stat.isFile() && !stat.isSymbolicLink(), `Non-regular current proof input: ${path}`);
    assert.equal(Boolean(stat.mode & 0o111), mode === '100755', `Current proof input mode: ${path}`);
    const bytes = readFileSync(file);
    const actual = createHash(object.length === 40 ? 'sha1' : 'sha256')
      .update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
    assert.equal(actual, object, `Current proof inputs differ from tested HEAD: ${path}`);
    checkedFiles.add(path);
  }
  const gitBytes: AuthoredInputs = {entries: tracked, read(path) {
    assert(checkedFiles.has(path), `Missing selected compiler input: ${path}`);
    const read = git(['show', head.stdout.trim() + ':' + path]);
    assert.equal(read.status, 0, 'Missing selected compiler input');
    return Buffer.from(read.stdout);
  }};
  if (tracked.has(resourceOriginal)) {
    const derived = runtimeEmit(gitBytes, resourceOriginal, resourceRuntime);
    const path = join(root, resourceRuntime), stat = lstatSync(path);
    assert(stat.isFile() && (stat.mode & 0o777) === derived.mode, 'Non-regular derived Node Resource bridge');
    assert(readFileSync(path).equals(derived.bytes), 'Derived Node Resource bridge differs from tested HEAD');
    checkedFiles.add(resourceRuntime);
  }
  for (const {path, mode, bytes} of pipelineTypeScriptEmits(gitBytes)) {
    const file = join(root, path), stat = lstatSync(file, {throwIfNoEntry: false});
    assert(stat?.isFile() && (stat.mode & 0o777) === mode, `Missing/nonregular derived pipeline output: ${path}`);
    assert(readFileSync(file).equals(bytes), `Derived pipeline output differs from tested HEAD: ${path}`);
    checkedFiles.add(path);
  }
  for (const path of snapshotPaths(root, true)) assert(checkedFiles.has(relative(root, path)),
    `Untracked current proof inputs: ${relative(root, path)}`);
  return head.stdout.trim();
}
export function checkBaseline(root: string, {read = path => readFileSync(join(root, path))}: {read?: ReadInput} = {}): Baseline {
  const baseline: Baseline = JSON.parse(read('proofs/relation-pipeline/baseline.json').toString());
  const extension = baseline.modelExtension;
  const checker = 'proofs/relation-chain/check.mjs';
  assert(extension && extension.checker === checker, 'Missing reviewed model extension');
  assert.deepEqual(Object.keys(baseline.unchangedCommon).sort(), [
    'proofs/bounded-session/Session.lean', 'proofs/bounded-session/Claims.lean',
    'proofs/bounded-session/check.mjs', 'proofs/relation-chain/Chain.lean',
    'proofs/relation-chain/Claims.lean', checker,
    'src/bounded_execution/session_contract_wbtest.mbt',
    'src/connectors/local/bounded_session_contract_wbtest.mbt',
  ].sort(), 'Incomplete original common model inputs');
  assert.deepEqual(Object.keys(extension.files).sort(), [checker,
    'proofs/relation-chain/StopAccounting.lean', 'proofs/relation-chain/StopClaims.lean'].sort(),
    'Incomplete or unrelated model extension');
  assert.deepEqual(extension.observation, {session: 14, chain: 22, stopAndPause: 18, total: 54},
    'Unreviewed model extension inventory');
  assert.equal(extension.priorDigest, baseline.unchangedCommon[checker], 'Changed historical checker binding');
  const blob = (revision: string, path: string) => {
    const result = spawnSync('git', ['show', `${revision}:${path}`], {cwd: root});
    assert.equal(result.status, 0, 'Missing reviewed model history');
    return result.stdout;
  };
  assert.equal(hash(blob(baseline.revision, checker)), extension.priorDigest, 'Changed historical checker bytes');
  for (const [path, expected] of Object.entries(extension.files)) {
    assert.equal(hash(blob(extension.revision, path)), expected, 'Unrelated model extension history');
    const currentExpected = path === checker && baseline.runnerExtension
      ? baseline.runnerExtension.files[checker] : expected;
    assert.equal(hash(read(path)), currentExpected, `Changed reviewed model extension: ${path}`);
  }
  for (const [path, expected] of Object.entries(baseline.unchangedCommon)) {
    assert.equal(hash(blob(baseline.revision, path)), expected, `Changed original common model history: ${path}`);
    if (path !== checker && hash(read(path)) !== expected) throw new Error(`Changed common proof/history: ${path}`);
  }
  if (baseline.runnerExtension) checkProofRunnerExtension(root, baseline.runnerExtension, read);
  for (const item of baseline.existingGroup) {
    if (!read(item.path).toString('utf8').includes(`test "${item.test}"`)) throw new Error(`Missing retained fixture ${item.test}`);
  }
  return baseline;
}
