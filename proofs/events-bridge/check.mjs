import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const directory = fileURLToPath(new URL('.', import.meta.url));
const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');

export function proofInput() {
  // Explicit local source closure; no external repository, package or imports.
  const paths = ['Composition.lean', 'CompositionClaims.lean', 'Events.lean', 'Claims.lean'];
  const sources = paths.map(read);
  if (sources.some(source => /^\s*import\b/mu.test(source))) {
    throw new Error('Unknown theory dependency');
  }
  return sources.join('\n');
}

export function runLean(input) {
  return spawnSync('lean', ['-DwarningAsError=true', '--stdin'], {
    cwd: directory, input, encoding: 'utf8', timeout: 30000, maxBuffer: 4 * 1024 * 1024,
  });
}

export function checkEventsBridge() {
  const version = spawnSync('lean', ['--short-version'], {cwd: directory, encoding: 'utf8', timeout: 10000});
  if (version.status !== 0 || read('lean-toolchain').trim() !== `leanprover/lean4:v${version.stdout.trim()}`) {
    throw new Error('Unexpected Lean toolchain');
  }
  const input = proofInput();
  const code = input.replace(/\/-[\s\S]*?-\//gu, '').replace(/--[^\n]*/gu, '');
  if (/\b(sorry|admit|axiom|native_decide|unsafe)\b/u.test(code)) throw new Error('Unfinished or unchecked proof');
  const expected = ['to_events_respects', 'to_rows_respects', 'round_trip',
    'rejected_input_preserves_error', 'round_trip_schema_and_order', 'observed_round_trip'];
  const actual = [...read('Events.lean').matchAll(/^theorem (\w+)/gmu)].map(([, name]) => name);
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error('Review the instance theorem inventory');
  const commonExpected = ['observed_composition', 'failure_short_circuits', 'observed_failure',
    'observe_identity', 'sequential_associativity', 'sequential_preconditions'];
  const commonActual = [...read('Composition.lean').matchAll(/^theorem (\w+)/gmu)].map(([, name]) => name);
  if (JSON.stringify(commonActual) !== JSON.stringify(commonExpected)) {
    throw new Error('Review the common theorem inventory');
  }
  const common = commonExpected.map(name => `BridgeComposition.${name}`);
  const audit = [...common, ...expected.map(name => `EventsBridge.${name}`)]
    .map(name => `#print axioms ${name}`).join('\n');
  const result = runLean(`${input}\n${audit}\n`);
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stdout + result.stderr);
  for (const [, axioms] of result.stdout.matchAll(/depends on axioms: \[([^\]]*)\]/gu)) {
    if (axioms.split(',').some(name => !['propext', 'Quot.sound'].includes(name.trim()))) {
      throw new Error(`Unexpected proof axioms: ${axioms}`);
    }
  }
  return {theorems: [...common, ...expected.map(name => `EventsBridge.${name}`)], output: result.stdout};
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const result = checkEventsBridge();
  process.stdout.write(result.output);
  console.log(`Checked ${result.theorems.length} common/instance theorems; no implementation proof claimed`);
}
