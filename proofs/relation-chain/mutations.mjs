// Mutate production sources, execute ONLY the replacement correspondence tests,
// and restore every file even on failure. Compile errors do not count as kills.
import { mkdirSync, readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import {runRestoredMutation, requireMutationDetection} from '../bounded-session/mutation-command.mjs';
import { snapshot, artifacts } from './evidence.mjs';
import {retirementCases, selectCases, retirementWitness, requireRetirementDetection, requireNormalLifetime} from './mutation-retirement.mjs';
import {createHash} from 'node:crypto';
import {performance} from 'node:perf_hooks';

const root = fileURLToPath(new URL('../../', import.meta.url));
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json')));
const home = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
const env = { ...process.env, MOON_HOME: home, PATH: `${home}/bin:${process.env.PATH}` };
const chain = 'src/connectors/local/selected_relation_provider.mbt';
const tea = 'src/local_tea_provider/time_series.mbt';
const suite = 'src/query_integration/relation_chain_evidence_wbtest.mbt';
const cases = [
  ['reset-consumed-budget', chain,
    'let start_next = fn(\n    next_inputs : Array[ManagedProviderInput],\n  ) -> Result[Unit, @connector.FixedComputeIssue] {',
    'let start_next = fn(\n    next_inputs : Array[ManagedProviderInput],\n  ) -> Result[Unit, @connector.FixedComputeIssue] {\n    used.val = 0L'],
  ['omit-handoff-accounting', chain,
    'used.val += 1L\n          let next_inputs = if state.input_preparation is Some(cursor) {',
    'used.val += 0L\n          let next_inputs = if state.input_preparation is Some(cursor) {'],
  ['fresh-budget-for-next-child', chain,
    'let remaining = execution.max_work.to_int64() - used.val\n    if remaining < 1L',
    'let remaining = execution.max_work.to_int64()\n    if remaining < 1L'],
  ['cleanup-reenters-advance', chain,
    'fn() {\n        if reclaimed.val {\n          return Ok(true)',
    'fn() {\n        if state.current is Some(active) { advance_managed_provider(active, 1) |> ignore }\n        if reclaimed.val {\n          return Ok(true)'],
  ['handoff-failure-drops-children', chain,
    'Ok(Some(selected)) =>\n              match start_next(selected) {\n                Ok(_) => return Ok(managed_provider_continue(0L, 1L))\n                Err(issue) => {\n                  terminal.val = true',
    'Ok(Some(selected)) =>\n              match start_next(selected) {\n                Ok(_) => return Ok(managed_provider_continue(0L, 1L))\n                Err(issue) => {\n                  state.children = []\n                  terminal.val = true'],
  ['pending-cleanup-reported-complete', chain,
    'Ok(false) => return Ok(false)', 'Ok(false) => return Ok(true)'],
  ['cancel-not-forwarded-to-session', tea,
    'fn() { @bounded.request_cancel(control) }', 'fn() { false }'],
  ['row-adapter-cumulative-as-delta', chain,
    'let work_delta = next_work - work.val', 'let work_delta = next_work'],
  ['premature-chain-terminal', chain,
    'let terminal = Ref(false)', 'let terminal = Ref(true)'],
].map(([id, path, original, changed]) => [id, path, original, changed, suite, 'chain evidence*']).concat(retirementCases);
const selected = selectCases(cases, process.argv.slice(2));
// Refuse every missing/ambiguous site before compiling the first mutant.
// This is recipe correspondence, not successful fault detection.
for (const [id, path, original] of cases) {
  const source = readFileSync(join(root, path), 'utf8');
  if (source.split(original).length !== 2) throw new Error(`Mutation site not unique: ${id}`);
}
const compiler = spawnSync(join(home, 'bin/moonc'), ['-v'], {env, encoding: 'utf8'});
if (compiler.status !== 0 || compiler.stdout.trim() !== pin.moonc) throw new Error('Wrong MoonBit toolchain');
const before = snapshot(root);
const directory = join(root, '.artifacts/relation-chain');
mkdirSync(directory, { recursive: true });
const results = [];
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const revision = spawnSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).stdout.trim();
const worktreeDirty = spawnSync('git', ['status', '--porcelain'], {cwd: root, encoding: 'utf8'}).stdout.trim().length > 0;
const hasRetirement = selected.some(row => retirementCases.some(candidate => candidate[0] === row[0]));
const normals = [];
function capture(id) {
  const observed = artifacts(root, 'js', 'connectors/local');
  const saved = join(directory, 'retirement-artifacts', id);
  mkdirSync(saved, {recursive: true});
  return Object.entries(observed).map(([path, digest]) => {
    const archivePath = join(saved, basename(path));
    copyFileSync(join(root, path), archivePath);
    if (hash(readFileSync(archivePath)) !== digest) throw new Error('Captured artifact changed');
    return {path, archivePath: archivePath.slice(root.length), digest, bytes: readFileSync(archivePath).length};
  });
}
function normal(phase) {
  const start = performance.now();
  const args = ['test', retirementCases[0][4], '--target', 'js', '--deny-warn'];
  const result = spawnSync(join(home, 'bin/moon'), args, {cwd: root, env, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024});
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  writeFileSync(join(directory, `mutation-retirement-normal-${phase}.log`), output);
  const count = requireNormalLifetime(result, output, readFileSync(join(root, retirementCases[0][4]), 'utf8'));
  if (snapshot(root).digest !== before.digest) throw new Error('Normal observation source changed');
  normals.push({phase, command: ['moon', ...args], count, milliseconds: performance.now() - start, sourceDigest: before.digest, artifacts: capture(`normal-${phase}`)});
}
if (hasRetirement) normal('before');
for (const recipe of selected) {
  const [id, path, original, changed, suite, filter] = recipe;
  const file = join(root, path);
  const source = readFileSync(file, 'utf8');
  if (source.split(original).length !== 2) throw new Error(`Mutation site not unique: ${id}`);
  const witness = retirementCases.some(row => row[0] === id) ? retirementWitness(recipe, readFileSync(join(root, suite), 'utf8')) : null;
  const start = performance.now();
  const mutant = source.replace(original, changed);
  let mutantSourceDigest;
  const result = await runRestoredMutation(file, source, mutant, join(home, 'bin/moon'),
    ['test', suite, '--target', 'js', '--deny-warn', '--filter', filter], {
      cwd: root, env, maxBuffer: 4 * 1024 * 1024,
    }, () => { mutantSourceDigest = snapshot(root).digest; });
  if (hash(readFileSync(file)) !== hash(source)) throw new Error('Mutation source bytes were not restored');
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  writeFileSync(join(directory, `mutation-${id}.log`), output);
  let count;
  try { count = requireMutationDetection(result, output); }
  catch (cause) { throw new Error(`Mutation ${id} was not killed by a running assertion: ${output}`, {cause}); }
  if (witness) requireRetirementDetection(result, output, witness);
  results.push({ id, path, suite, target: 'js', filter, killed: true, failureCount: count, witness,
    originalDigest: hash(source), mutantDigest: hash(mutant), restoredDigest: hash(readFileSync(file)),
    milliseconds: performance.now() - start, exit: result.status, mutantSourceDigest,
    artifacts: witness ? capture(id) : [] });
  console.log(`${id}: detected by replacement tests`);
}
if (snapshot(root).digest !== before.digest) throw new Error('Mutation runner did not restore the source tree');
if (hasRetirement) normal('after');
const filename = process.argv[2] === 'retirement' ? 'mutations-retirement.json' : 'mutations.json';
writeFileSync(join(directory, filename), `${JSON.stringify({ revision, worktreeDirty, source: before, selection: process.argv[2] ?? 'all', normals, results }, null, 2)}\n`);
