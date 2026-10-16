import assert from 'node:assert/strict';
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
