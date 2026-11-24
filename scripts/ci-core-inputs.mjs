// Which tracked files can change the Wasm and Native Core results. Compiler
// inputs are always required. Every other input is recorded from the Core
// steps themselves: scripts/ci-core-inputs.json lists the tracked files those
// steps opened, and the Core inputs workflow fails when a run opens a file the
// list does not cover. Nothing here is a hand-maintained path review.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {createReadStream, mkdirSync, readFileSync, readdirSync, writeFileSync} from 'node:fs';
import {basename, dirname, join, normalize} from 'node:path';
import {createInterface} from 'node:readline';
import {fileURLToPath} from 'node:url';

const schema = 'actql-ci-core-inputs/0.1';
const inventory = fileURLToPath(new URL('./ci-core-inputs.json', import.meta.url));
const sorted = values => [...new Set(values)].sort();
const parent = path => path.includes('/') ? path.slice(0, path.lastIndexOf('/')) : '';

// Compiler, toolchain, dependency and workflow inputs, C sources and binaries,
// and the selection itself. These never depend on a recording.
export function alwaysCoreInput(path) {
  return /^(?:src|vendor|\.github)\//u.test(path)
    || /(?:^|\/)(?:moon\.mod|moon\.pkg|toolchain\.json|package(?:-lock)?\.json)$/u.test(path)
    || /\.(?:c|h|cc|cpp|inc|s|a|so|dylib|wasm)$/iu.test(path)
    || /^scripts\/ci-(?:core-inputs\.(?:mjs|json)|targets\.mjs)$/u.test(path);
}

export function validateCoreInputs(value) {
  assert.deepEqual(Object.keys(value ?? {}).sort(), ['files', 'schema']);
  assert.equal(value.schema, schema);
  assert(Array.isArray(value.files) && value.files.every(path => typeof path === 'string' && path.length > 0
    && !alwaysCoreInput(path)), 'Invalid recorded Core input');
  assert.deepEqual(value.files, sorted(value.files), 'Recorded Core inputs must be sorted and unique');
  return value;
}

export function readCoreInputs(path = inventory) {
  return validateCoreInputs(JSON.parse(readFileSync(path, 'utf8'))).files;
}

// A modified file is required when the Core steps read it. An added, deleted
// or retyped file is also required when it sits beside a recorded input: the
// reader may enumerate that directory. structural === null means unknown.
export function coreInputRequired(path, {files, structural = null}) {
  if (alwaysCoreInput(path) || files.includes(path)) return true;
  if (structural !== null && !structural.includes(path)) return false;
  return files.some(file => parent(file) === parent(path));
}

// strace -f -z -y output: one "<pid> <call>" line per successful call. A
// file opened only by git is a working-tree check, not a test input.
export async function reduceCoreTrace(lines, tracked, root) {
  const parents = new Map(), commands = new Map(), files = new Set();
  for await (const line of lines) {
    const head = /^(\d+)\s+(.*)$/u.exec(line);
    if (!head) continue;
    const [, pid, call] = head;
    if (call.startsWith('execve(')) {
      const program = /\["((?:[^"\\]|\\.)*)"/u.exec(call);
      commands.set(pid, program ? basename(program[1]) : '?');
      continue;
    }
    if (/^(?:clone3?|v?fork)\(/u.test(call)) {
      const child = /= (\d+)\s*$/u.exec(call);
      if (child) parents.set(child[1], pid);
      continue;
    }
    let owner = pid;
    while (!commands.has(owner) && parents.has(owner)) owner = parents.get(owner);
    if (commands.get(owner) === 'git') continue;
    const opened = [/= \d+<([^>]*)>\s*$/u.exec(call)?.[1], /\((?:AT_FDCWD(?:<[^>]*>)?, )?"((?:[^"\\]|\\.)*)"/u.exec(call)?.[1]];
    for (const candidate of opened) {
      if (!candidate?.startsWith(root + '/')) continue;
      const path = normalize(candidate).slice(root.length + 1);
      if (tracked.has(path)) files.add(path);
    }
  }
  return sorted(files);
}

// The recorded commands are the Core job's own steps, so the recording cannot
// drift from what CI runs. Any expression this does not resolve is refused.
export function coreLegScript(workflow, target, partition) {
  const names = ['Check common core', 'Check independent fixed Run materials identity', 'Test common core'];
  const steps = names.map(name => workflow.jobs['core-common'].steps.find(step => step.name === name));
  assert(steps.every(step => typeof step?.run === 'string'), 'Missing Core step');
  const values = new Map([['matrix.target', target], ['matrix.partition', partition],
    ['needs.select-targets.outputs.plan', ''], ['needs.select-targets.outputs.moon_test_selection', 'false']]);
  const selected = steps.filter(step => step.name !== 'Check common core' || target !== 'native');
  return selected.map(step => {
    const run = step.run.replace(/\$\{\{\s*([^}]+?)\s*\}\}/gu, (_all, expression) => {
      assert(values.has(expression), `Unresolved Core step expression: ${expression}`);
      return values.get(expression);
    });
    return `(\n${run}\n) || status=$?`;
  }).join('\n');
}

export function uncoveredCoreInputs(recorded, files) {
  return sorted(recorded.filter(path => !alwaysCoreInput(path) && !files.includes(path)));
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  const repository = fileURLToPath(new URL('..', import.meta.url)).replace(/\/$/u, '');
  if (command === 'record') {
    const [target, partition, output] = args;
    assert(['wasm', 'native'].includes(target) && partition && output, 'Usage: record <target> <partition> <output>');
    const {parse} = createRequire(import.meta.url)('yaml');
    const workflow = parse(readFileSync(join(repository, '.github/workflows/ci.yml'), 'utf8'));
    const scratch = process.env.RUNNER_TEMP;
    assert(scratch, 'The recording runs on a hosted Linux runner');
    const script = join(scratch, 'core-leg.sh'), trace = join(scratch, 'core-leg.trace');
    writeFileSync(script, `status=0\n${coreLegScript(workflow, target, partition)}\nexit "$status"\n`);
    const env = {...process.env, CI_PLAN_PATH: '', ACTQL_TEST_NATIVE_CORE_PARTITION: '',
      ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE: '', ACTQL_TEST_NATIVE_CORE_SCOPED_JOBS: '1'};
    const result = spawnSync('strace', ['-f', '-qq', '-z', '-y', '-s', '4096',
      '-e', 'trace=open,openat,openat2,execve,clone,clone3,fork,vfork', '-o', trace, 'bash', script],
    {cwd: repository, env, stdio: 'inherit'});
    assert.equal(result.status, 0, 'The recorded Core steps must pass');
    const tracked = new Set(execFileSync('git', ['ls-files', '-z'], {cwd: repository, encoding: 'utf8',
      maxBuffer: 256 * 1024 ** 2}).split('\0').filter(Boolean));
    const files = await reduceCoreTrace(createInterface({input: createReadStream(trace)}), tracked, repository);
    mkdirSync(dirname(output), {recursive: true});
    writeFileSync(output, JSON.stringify(files.filter(path => !alwaysCoreInput(path)), null, 1) + '\n');
    console.log(`Recorded ${files.length} tracked files opened by ${target} ${partition}`);
    return;
  }
  assert(['verify', 'update'].includes(command) && args.length === 1, 'Usage: ci-core-inputs.mjs record|verify|update');
  const names = readdirSync(args[0], {recursive: true}).filter(name => name.endsWith('.json'));
  assert(names.length > 0, 'No recordings');
  const recorded = sorted(names.flatMap(name => JSON.parse(readFileSync(join(args[0], name), 'utf8'))));
  if (command === 'update') {
    writeFileSync(inventory, JSON.stringify(validateCoreInputs({schema, files: recorded}), null, 1) + '\n');
    return;
  }
  const missing = uncoveredCoreInputs(recorded, readCoreInputs());
  assert.deepEqual(missing, [], 'The Core steps read files outside scripts/ci-core-inputs.json; '
    + 'download this run\'s recordings and run: node scripts/ci-core-inputs.mjs update <directory>');
  console.log(`All ${recorded.length} recorded Core inputs are covered`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) await main();
