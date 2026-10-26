import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {checkCredentialScopeBinding, credentialInvocationFields,
  credentialScopeBindingPath, renderCredentialScopeBinding} from './generate-credential-scope-binding.mjs';
import {invocationBindingsMatch} from '../adapters/host-common/owned-invocation-context.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const owner = readFileSync(join(root, 'src/remote_credential/credential.mbt'), 'utf8');
// Independent subject vector: the operation/expiry/quota belong to the
// credential-use Owner, not this original invocation binding comparison.
const subject = {issuerAuthority: 'issuer', principal: 'principal', namespaceId: 'workspace',
  environment: 'environment', siteKey: 'site', siteGeneration: 4,
  runtimeBundleCid: 'runtime', connectorRegistration: 'connector', connectorRevision: 'revision',
  resourceOrigin: 'https://original.example', runInvocationCid: 'run', taskAttempt: 2,
  dispatchRequestCid: 'request'};

test('generated subject fields match the actual credential Owner and independent scope vector', () => {
  checkCredentialScopeBinding(root);
  assert.deepEqual(credentialInvocationFields(owner), Object.keys(subject));
  assert(invocationBindingsMatch(subject, {...subject}));
});

for (const field of Object.keys(subject)) {
  test(`original invocation refuses a missing or substituted ${field}`, () => {
    const missing = {...subject}; delete missing[field];
    assert.equal(invocationBindingsMatch(missing, subject), false);
    assert.equal(invocationBindingsMatch(subject, missing), false);
    assert.equal(invocationBindingsMatch({...subject, [field]: 'foreign'}, subject), false);
  });
}

test('a new Owner field and an omitted generated comparison fail freshness independently', () => {
  const scratch = mkdtempSync(join(tmpdir(), 'credential-scope-binding-'));
  try {
    const path = join(scratch, credentialScopeBindingPath);
    mkdirSync(dirname(path), {recursive: true});
    writeFileSync(path, renderCredentialScopeBinding(owner));
    const added = owner.replace('  principal : String', '  additional_scope : String\n  principal : String');
    assert(credentialInvocationFields(added).includes('additionalScope'));
    assert.throws(() => checkCredentialScopeBinding(scratch, added), /CredentialScopeBindingStale/u);
    writeFileSync(path, renderCredentialScopeBinding(owner).replace("  'namespaceId',\n", ''));
    assert.throws(() => checkCredentialScopeBinding(scratch, owner), /CredentialScopeBindingStale/u);
  } finally { rmSync(scratch, {recursive: true, force: true}); }
});


const cli = 'scripts/generate-credential-scope-binding.mjs';
const cliInputs = [cli, 'src/remote_credential/credential.mbt',
  'src/remote_credential/installation_preparation_subject.mbt',
  'src/remote_credential/installation_preparation_grant.mbt', credentialScopeBindingPath,
  'adapters/host-common/installation-preparation-fields.generated.mjs',
  'src/connectors_builtin_node/client_installation_preparation_fields.generated.mbt'];

test('actual prepack freshness CLI preserves machine stdout and reports its diagnostic on stderr', () => {
  const before = cliInputs.map(path => readFileSync(join(root, path), 'utf8'));
  const result = spawnSync(process.execPath, [join(root, cli), '--check'], {
    cwd: join(root, 'packages/local-node'), encoding: 'utf8', timeout: 30000,
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.signal, null);
  assert.equal(result.stdout, '', 'npm pack --json owns stdout');
  assert.match(result.stderr, /^Credential invocation fields match the existing Owner$/mu);
  assert.deepEqual(cliInputs.map(path => readFileSync(join(root, path), 'utf8')), before,
    'The actual --check command must remain read-only');
});

test('actual stale freshness CLI remains nonzero and cannot emit success or rewrite its binding', () => {
  const scratch = mkdtempSync(join(tmpdir(), 'credential-scope-cli-'));
  try {
    for (const path of cliInputs) {
      const target = join(scratch, path);
      mkdirSync(dirname(target), {recursive: true});
      writeFileSync(target, readFileSync(join(root, path)));
    }
    const target = join(scratch, credentialScopeBindingPath);
    const original = readFileSync(target, 'utf8');
    const stale = original.replace("  'namespaceId',\n", '');
    assert.notEqual(stale, original, 'The independent mutation must remove its subject field');
    writeFileSync(target, stale);
    const result = spawnSync(process.execPath, [join(scratch, cli), '--check'], {
      cwd: scratch, encoding: 'utf8', timeout: 30000,
    });
    assert.notEqual(result.status, 0);
    assert.equal(result.signal, null);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /CredentialScopeBindingStale/u);
    assert.doesNotMatch(result.stderr, /Credential invocation fields match/u);
    assert.equal(readFileSync(target, 'utf8'), stale);
  } finally { rmSync(scratch, {recursive: true, force: true}); }
});
