// Read-only generation checks remain with their existing owners. The approved
// compiler representation targets come from that generator, never from a new
// handwritten list or a declaration's self-reported verification flag.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync, realpathSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {compilerBindingTargets, generateCompilerBindings} from './generate-js-compiler-bindings.mjs';
import {generateActionBindings} from './generate-js-action-bindings.mjs';
import {checkCredentialScopeBinding, checkInstallationPreparationBinding, checkInstallationPreparationBridge} from './generate-credential-scope-binding.mjs';

// In-process evidence from this existing checker, not serialized sidecar data.
// Retain original-root identity and immutable output records after checks run.
const checkedBindings = new WeakMap();
export function trustedCompilerBindingOutputs(root, generated) {
  if (generated === undefined || generated === null || Array.isArray(generated) && generated.length === 0) return [];
  assert(checkedBindings.has(generated), 'Untrusted generated interface qualification');
  assert.equal(checkedBindings.get(generated), realpathSync(root), 'Generated interface qualification belongs to another source root');
  return generated;
}

export function interfaceGenerationFreshness(root) {
  const url = pathToFileURL(join(root, '/'));
  generateCompilerBindings(url, false);
  generateActionBindings(url, false);
  checkCredentialScopeBinding(root);
  checkInstallationPreparationBinding(root);
  checkInstallationPreparationBridge(root);
  const generators = ['generate-client-host-wire.mjs', 'generate-client-publication-wire.mjs',
    'generate-interactive-run-control-wire.mjs', 'generate-python-client-wire.mjs',
    'lowering-registry-vectors.mjs', 'native-cli-default-assets.mjs',
    'catalog-body-dependencies.mjs', 'check-stage-semantics.mjs', 'mock-churn-risk-catalogue.mjs',
    'compilation-manifests.mjs', 'current-timestamp-expression-contract.mjs', 'query-acquisition-contract.mjs',
    'query-process-evidence.mjs', 'query-two-receipt.mjs',
    'query-resource-scopes.mjs', 'check-query-evidence-fixtures.mjs',
    'fixed-compute-capacity.mjs', 'managed-runtime-vectors.mjs'];
  assert.equal(new Set(generators).size, generators.length, 'Duplicate generation freshness check');
  for (const name of generators) execFileSync(process.execPath, [join(root, 'scripts', name), '--check',
    ...(name === 'check-stage-semantics.mjs' ? ['--root', root] : [])], {
    cwd: root, timeout: 15000, maxBuffer: 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe']});
  const localGenerators = ['generate-local-wasm-abi.py', 'generate-local-native-runtime-binding.py',
    'generate-local-native-shim-bindings.py', 'generate-local-native-memory-binding.py',
    'generate-local-duckdb-binding.py'];
  for (const name of localGenerators) execFileSync('python3', ['-B', join(root, 'scripts', name), '--check'], {
    cwd: root, timeout: 15000, maxBuffer: 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe']});
  const assemblies = ['check-duckdb-environment-contract.mjs', 'connector-node-bundles.mjs', 'workers-composition.mjs'];
  for (const name of assemblies) execFileSync(process.execPath, [join(root, 'scripts', name)], {
    cwd: root, timeout: 15000, maxBuffer: 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe']});
  const generated = compilerBindingTargets.map(module => ({module,
    sha256: createHash('sha256').update(readFileSync(join(root, module))).digest('hex'),
    generator: {path: 'scripts/generate-js-compiler-bindings.mjs', anchor: 'generateCompilerBindings'},
    freshness: {path: 'scripts/generate-js-compiler-bindings.mjs', anchor: "['--check', '--write']"}}));
  assert.equal(generated.length, new Set(generated.map(value => value.module)).size, 'Duplicate generated compiler binding');
  for (const proof of generated) {
    Object.freeze(proof.generator); Object.freeze(proof.freshness); Object.freeze(proof);
  }
  Object.freeze(generated);
  checkedBindings.set(generated, realpathSync(root));
  return {qualification: 'read-only-generation-freshness; not-target-or-artifact-admission', generated,
    checked: ['compiler-bindings', 'action-bindings', 'credential-fields', 'installation-preparation-fields', 'installation-preparation-bridge', ...generators, ...localGenerators, ...assemblies]};
}
