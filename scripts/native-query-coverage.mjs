// File-level selection only: Moon owns compilation, discovery and execution.
// New environment readers conservatively retain the old full harness suite.
import {spawn} from 'node:child_process';
import {readFileSync, readdirSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {assertTestExecution} from './test-execution.mjs';
import {tokens, readPackageTargetOptions} from './portable-core.mjs';

export const nativeQueryCoverage = JSON.parse(readFileSync(
  new URL('./native-query-coverage.json', import.meta.url), 'utf8'));
const packagePaths = ['src/query_integration', 'src/native_values_integration'];
const inHarnessPackage = path => packagePaths.some(root => path.startsWith(`${root}/`));
const owners = ['http-client', 'remote-runtime'];
const environmentReader = /\b(?:get_env_var|(?:secure_)?getenv|environ)\b|ACTQL_TEST_/u;
const queryReader = /get_env_var|native_duckdb_test_library|native_resident_test_prerequisites|native_duckdb_test_variable/u;
const testNames = source => [...source.matchAll(/^test "([^"]+)"/gmu)]
  .map(match => match[1]);
const variables = source => [...new Set([
  ...source.matchAll(/"(ACTQL_[A-Z_]+)"/gu),
  ...source.matchAll(/get_env_var\s*\(\s*"([^"]+)"/gu),
].map(match => match[1]))].sort();
const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
const identifiers = source => source.match(/\b[a-zA-Z_][a-zA-Z_0-9]*\b/gu) ?? [];

// Package-local helper reachability is conservative: comments/unused identifiers
// can trigger fallback. Function values and aliases count, not only direct calls.
function queryEnvironmentHelpers(sources) {
  const functions = new Map();
  for (const [path, source] of Object.entries(sources)) {
    if (!inHarnessPackage(path)) continue;
    const starts = [...source.matchAll(/^(?:(?:pub )?fn ([a-zA-Z_][a-zA-Z_0-9]*)\b|test\b)/gmu)];
    for (let index = 0; index < starts.length; index++) {
      if (starts[index][1]) {
        const name = starts[index][1];
        // Equal names across harness packages must not erase an environment
        // dependency. Keep the conservative union until package resolution.
        functions.set(name, (functions.get(name) ?? '') + '\n' +
          source.slice(starts[index].index, starts[index + 1]?.index));
      }
    }
  }
  const affected = new Set();
  let changed = true;
  while (changed) {
    changed = false;
    for (const [name, body] of functions) {
      if (affected.has(name)) continue;
      if (queryReader.test(body) || identifiers(body).some(name => affected.has(name))) {
        affected.add(name); changed = true;
      }
    }
  }
  return affected;
}

// Count the same positive literal target lists that Moon selects. Unfamiliar
// expressions fail closed; they never lower the required execution count.
function nativeQueryTargets(sources) {
  const targets = new Map();
  const symbol = (token, value) => token?.kind === 'symbol' && token.value === value;
  const backends = new Set(['js', 'wasm', 'wasm-gc', 'native']);
  for (const root of packagePaths) {
    const source = sources[`${root}/moon.pkg`];
    if (typeof source !== 'string') throw new Error(`Missing native package metadata: ${root}`);
    const list = tokens(source);
    let packageNative = true, clause;
    for (let index = 0; index < list.length; index++) {
      const token = list[index];
      if (token.kind === 'word' && token.value === 'supported_targets') {
        const value = list[index + 2];
        if (!symbol(list[index + 1], '=') || value?.kind !== 'string') {
          throw new Error('Malformed native package targets');
        }
        const names = value.value.startsWith('+') ? value.value.slice(1).split('+') : [value.value];
        if (!names.length || names.some(name => !backends.has(name)) || new Set(names).size !== names.length) {
          throw new Error('Unsupported native package targets');
        }
        packageNative = names.includes('native');
      }
      if (token.kind !== 'word' || token.value !== 'options' || !symbol(list[index + 1], '(')) continue;
      let round = 1, braces = 0, square = 0;
      for (let cursor = index + 2; cursor < list.length && round > 0; cursor++) {
        const item = list[cursor];
        if (round === 1 && braces === 0 && square === 0 && item.kind === 'word' && item.value === 'targets') {
          if (clause !== undefined || !symbol(list[cursor + 1], ':') || !symbol(list[cursor + 2], '{')) {
            throw new Error('Malformed or duplicate native file targets');
          }
          let end = cursor + 2, depth = 1;
          while (depth > 0 && ++end < list.length) {
            if (symbol(list[end], '{')) depth++;
            else if (symbol(list[end], '}')) depth--;
          }
          if (depth !== 0) throw new Error('Unclosed native file targets');
          // Reuse the existing literal-map reader, independently of the other
          // compiler-owned link/FFI options in this same options invocation.
          const input = [{kind: 'symbol', value: '('}, ...list.slice(cursor, end + 1), {kind: 'symbol', value: ')'}];
          let offset = 0;
          clause = readPackageTargetOptions({
            take(kind, value) {
              const next = input[offset++];
              if (!next || next.kind !== kind || value !== undefined && next.value !== value) {
                throw new Error('Malformed native file targets');
              }
              return next.value;
            },
            peek: value => input[offset]?.value === value,
          });
        }
        if (item.kind !== 'symbol') continue;
        if (item.value === '(') round++;
        else if (item.value === ')') round--;
        else if (item.value === '{') braces++;
        else if (item.value === '}') braces--;
        else if (item.value === '[') square++;
        else if (item.value === ']') square--;
        if (round < 0 || braces < 0 || square < 0) throw new Error('Malformed native target options');
      }
      if (round !== 0) throw new Error('Unclosed native target options');
    }
    targets.set(root, packageNative);
    for (const [file, names] of clause ?? []) {
      if (!/^[A-Za-z0-9_]+\.mbt$/u.test(file) || !names.length ||
          names.some(name => !backends.has(name)) || new Set(names).size !== names.length) {
        throw new Error('Unsupported native file target expression');
      }
      targets.set(`${root}/${file}`, packageNative && names.includes('native'));
    }
  }
  return path => targets.get(path) ?? targets.get(packagePaths.find(root => path.startsWith(`${root}/`)));
}

export function readNativeQuerySources(root) {
  const sources = {};
  function visit(path) {
    for (const entry of readdirSync(join(root, path), {withFileTypes: true})) {
      const name = `${path}/${entry.name}`;
      if (entry.isDirectory()) visit(name);
      else if (/\.(?:mbt|c|cc|cpp|h)$/u.test(name) ||
          entry.name === 'moon.pkg' && packagePaths.includes(path)) {
        sources[name] = readFileSync(join(root, name), 'utf8');
      }
    }
  }
  visit('src');
  return sources;
}

export function selectNativeQueryTests(owner, sources, env,
  manifest = nativeQueryCoverage) {
  if (!owners.includes(owner)) throw new Error(`Unknown native harness: ${owner}`);
  const entries = Object.entries(manifest.files ?? {});
  if (entries.length === 0) throw new Error('Missing native query ownership inventory');
  const selected = [];
  const reasons = [];
  let expected = 0;
  let total = 0;
  const helpers = queryEnvironmentHelpers(sources);
  const native = nativeQueryTargets(sources);
  for (const [file, entry] of entries) {
    if (!/^src\/(?:query_integration|native_values_integration)\/[a-z_]+_wbtest\.mbt$/u.test(file) ||
        !Array.isArray(entry.owners) || entry.owners.length === 0 ||
        new Set(entry.owners).size !== entry.owners.length ||
        entry.owners.some(value => !owners.includes(value)) ||
        !Array.isArray(entry.tests) || entry.tests.length === 0 ||
        new Set(entry.tests).size !== entry.tests.length ||
        !Array.isArray(entry.variables)) {
      throw new Error(`Malformed native query ownership: ${file}`);
    }
    const source = sources[file];
    const found = testNames(source ?? '');
    if (entry.tests.some(name => !found.includes(name))) {
      throw new Error(`Missing required native query case: ${file}`);
    }
    if (!same(found, entry.tests) || !same(variables(source), entry.variables)) {
      reasons.push(`changed native query cases or environment: ${file}`);
    }
    if (!native(file)) throw new Error(`Required native query target is excluded: ${file}`);
    if (entry.owners.includes(owner)) {
      selected.push(file);
      expected += found.length;
    }
  }
  for (const [path, source] of Object.entries(sources)) {
    if (inHarnessPackage(path)) {
      if (native(path)) total += testNames(source).length;
      const file = path;
      const readsEnvironment = environmentReader.test(source) || queryReader.test(source) ||
        identifiers(source).some(name => helpers.has(name));
      if (readsEnvironment && !manifest.files[file]) {
        reasons.push(`unowned native query environment reader: ${file}`);
      }
    } else if (!/_(?:wb|bb)?test\.mbt$/u.test(path) && environmentReader.test(source)) {
      // Reviewed production surfaces: temporary file placement, and passing
      // the unchanged environment into an executor child. Neither selects
      // query test cases. New reads keep the full suite until reviewed.
      const allowed = path === 'src/platform_native/remote_journal/inspection_stub.c'
        ? source.replace('getenv("TMPDIR")', '')
        : path === 'src/platform_native/executor_slot/executor_slot_stub.c'
          ? source.replace('extern char **environ;', '')
            .replace('posix_spawn(&pid, path, &actions, NULL, argv, environ)', '')
          : source;
      if (environmentReader.test(allowed)) reasons.push(`production environment reader: ${path}`);
    }
  }
  const required = manifest.requiredEnvironment?.[owner];
  if (!Array.isArray(required) || required.length === 0) {
    throw new Error(`Missing required native environment inventory: ${owner}`);
  }
  for (const name of required) {
    if (typeof env[name] !== 'string' || env[name].length === 0) {
      throw new Error(`Required native query prerequisite missing: ${name}`);
    }
  }
  if (owner === 'http-client' && env.ACTQL_REQUIRE_NATIVE_DUCKDB_TESTS !== '1') {
    throw new Error('Native query DuckDB execution must be required');
  }
  if (expected === 0 || total === 0) throw new Error('Empty native query selection');
  return {paths: reasons.length ? packagePaths : selected,
    expected: reasons.length ? total : expected,
    mode: reasons.length ? 'full-fallback' : 'subset', reasons};
}

export function assertNativeQueryExecution(selection, result) {
  const checked = assertTestExecution('moon', 'moon',
    ['test', ...selection.paths, '--target', 'native'], result);
  if (checked.counts.passed !== selection.expected) {
    throw new Error(`Native query coverage mismatch: expected ${selection.expected}, ` +
      `executed ${checked.counts.passed}`);
  }
  return checked.counts;
}

export async function runNativeQueryTests(moon, owner, {cwd, env}) {
  const root = cwd instanceof URL ? fileURLToPath(cwd) : cwd;
  const selection = selectNativeQueryTests(owner, readNativeQuerySources(root), env);
  console.log(`Native query ${owner}: ${selection.mode}, ${selection.expected} cases`);
  for (const reason of selection.reasons) console.log(`Full query fallback: ${reason}`);
  const child = spawn(moon, ['test', ...selection.paths, '--target', 'native'],
    {cwd, env, stdio: ['ignore', 'pipe', 'pipe']});
  // Keep bounded summary tails while forwarding normal compiler/test output.
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', chunk => {
    process.stdout.write(chunk); stdout = (stdout + chunk).slice(-65536);
  });
  child.stderr.on('data', chunk => {
    process.stderr.write(chunk); stderr = (stderr + chunk).slice(-65536);
  });
  const result = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (status, signal) => resolve({status, signal, stdout, stderr}));
  });
  assertNativeQueryExecution(selection, result);
}
