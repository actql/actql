import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {hash} from './inputs.mjs';

const names = ['checker_sound', 'checker_complete', 'scope_and_kind_preserved',
  'required_obligations_preserved', 'identical_inputs_preserve_observation'];
const model = readFileSync(new URL('Reuse.lean', import.meta.url), 'utf8');
const claims = readFileSync(new URL('Claims.lean', import.meta.url), 'utf8');
const pin = readFileSync(new URL('../bounded-session/lean-toolchain', import.meta.url), 'utf8').trim();
const cwd = fileURLToPath(new URL('.', import.meta.url));
const tokens = `${model}\n${claims}`.replace(/\/-[\s\S]*?-\//gu, '').replace(/--[^\n]*/gu, '');
assert(!/\b(sorry|admit|axiom|native_decide|unsafe)\b/u.test(tokens), 'Unproved/unchecked Lean source');
assert.deepEqual([...tokens.matchAll(/^theorem\s+(\w+)/gmu)].map(match => match[1]), names, 'Changed theorem inventory');
const audit = names.map(name => `#print axioms IncrementalEvidence.${name}`).join('\n');
const requirementFields = ['action', 'candidate', 'kind', 'target', 'scope', 'premises', 'inputs', 'minimumUnits'];
const applicationFields = ['action', 'origin', 'kind', 'target', 'scope', 'premises', 'inputs', 'units',
  'authenticated', 'successful', 'reused', 'closed', 'mainOrigin'];

function record(value, fields) {
  assert.deepEqual(Object.keys(value ?? {}).sort(), [...fields].sort(), 'Unknown/missing checker data');
  return `{ ${fields.map(key => {
    const data = value[key];
    if (typeof data === 'boolean') return `${key} := ${data}`;
    if (typeof data === 'number') {
      assert(Number.isSafeInteger(data) && data >= 0, 'Invalid checker count');
      return `${key} := ${data}`;
    }
    // Only identities reach generated Lean source, never labels/messages or
    // source code from an archive. This excludes all quotation/code injection.
    assert(typeof data === 'string' && /^[a-z0-9-]+$/u.test(data), 'Invalid checker identity');
    return `${key} := "${data}"`;
  }).join(', ')} }`;
}

export function leanInput(required, applications) {
  assert(Array.isArray(required) && Array.isArray(applications));
  assert(required.length > 0 && required.length <= 256 && applications.length <= 256, 'Unbounded/empty checker input');
  return `${model}\n${claims}\n${audit}\n` +
    `def submittedRequirements : List IncrementalEvidence.Requirement := [${required.map(value => record(value, requirementFields)).join(',')}]\n` +
    `def submittedApplications : List IncrementalEvidence.Application := [${applications.map(value => record(value, applicationFields)).join(',')}]\n` +
    'example : IncrementalEvidence.check submittedRequirements submittedApplications = true := by decide\n';
}

export function checkPlan(required, applications, {lean = 'lean', timeout = 30000, onOutput = () => {}} = {}) {
  const source = leanInput(required, applications);
  const version = spawnSync(lean, ['--short-version'], {cwd, encoding: 'utf8', timeout});
  assert.equal(version.status, 0, 'Lean runtime unavailable');
  assert.equal(version.stdout.trim(), pin.split(':v')[1], 'Wrong Lean pin');
  const result = spawnSync(lean, ['-DwarningAsError=true', '--stdin'], {
    cwd, input: source, encoding: 'utf8', timeout, maxBuffer: 4 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `Lean rejected action plan: ${result.stdout}${result.stderr}`);
  assert(!/sorryAx/u.test(result.stdout), 'Unproved checker result');
  for (const [, axioms] of result.stdout.matchAll(/depends on axioms: \[([^\]]*)\]/gu)) {
    assert(axioms.split(',').every(name => ['propext', 'Quot.sound'].includes(name.trim())), 'Unreviewed proof axiom');
  }
  onOutput(result.stdout);
  return {accepted: true, inputDigest: hash(source), outputDigest: hash(result.stdout),
    theoremCount: names.length, toolchain: pin};
}
