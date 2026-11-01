import assert from 'node:assert/strict';
import test from 'node:test';
import {parse} from 'acorn';
import {readFile,mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {generateKeyPairSync,randomUUID} from 'node:crypto';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {signRemoteCredentialGrant} from '../site-node/remote-credential-signature.mjs';
import {openSqliteCredentialJournal} from '../site-node/sqlite-credential-journal.mjs';

const runtimeUrl = process.env.ACTQL_SOURCE_CREDENTIAL_RUNTIME_URL ??
  new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href;
const moon = await import(runtimeUrl);
const control = runtimeCore(moon).remoteCredentialControl;
const cid = digit => 'sha256:' + digit.repeat(64);

async function originalSourceSigner(t) {
  const source = await readFile(new URL('./installed-row-source.mjs', import.meta.url), 'utf8');
  const checkStart = source.indexOf('  function checkGrantRequest(runInvocationCid, dispatchRequestCid, maxUses,');
  const signStart = source.indexOf('  function sign({operation, runInvocationCid, taskAttempt = 1,');
  const signEnd = source.indexOf('  function authorizationPurpose(authorization)', signStart);
  assert(checkStart > 0 && signStart > checkStart && signEnd > signStart);
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const custody = tree.body.find(node => node.type === 'ExportNamedDeclaration' &&
    node.declaration?.id?.name === 'openRowSourceCredentialCustody').declaration;
  const scopeFields = custody.body.body.find(node => node.type === 'VariableDeclaration' &&
    node.declarations.some(value => value.id.name === 'originalScopeFields'));
  assert(scopeFields);
  const root = await mkdtemp(join(process.env.ACTQL_SOURCE_CREDENTIAL_SCRATCH ?? tmpdir(), 'source-original-grant-'));
  const keys = generateKeyPairSync('ed25519');
  const profile = Object.freeze({credentialAuthorityId: 'source-authority', credentialKeyId: 'source-key',
    namespaceId: 'source-constructor-test', environment: 'test', siteKey: 'source-site',
    siteGeneration: 1, resourceOrigin: 'https://resource.example'});
  const journal = openSqliteCredentialJournal(root, {credentialAuthorities:
    new Map([[profile.credentialAuthorityId, new Map([[profile.credentialKeyId, keys.publicKey]])]])});
  t.after(() => {journal.close();t.diagnostic('Fresh original Credential journal KEEP: ' + root);});
  const issued = new WeakMap();
  const bindings = {control, profile, principalId: 'source-principal', runtimeBundleCid: cid('a'),
    connectorRegistration: 'rest-acme', connectorRevision: 'acme/0.1', privateKey: keys.privateKey,
    now: () => 1_999_999_999_000, grantLifetimeMs: 1000, journal, randomUUID,
    signRemoteCredentialGrant, issuedRunAuthorizations: issued, grantCode: 'InvalidRowSourceGrantRequest',
    cidPattern: /^sha256:[0-9a-f]{64}$/u,
    ensureOpen() {}, fail(code) {throw Object.assign(new Error(code), {code});}};
  // This original signer fixture selects the unchanged legacy purpose. Its
  // scope fields still come from the SAME actual issuer declaration above.
  const sign = new Function(...Object.keys(bindings), source.slice(scopeFields.start, scopeFields.end) +
    ';const scopeDefinition=undefined,construction=undefined;' + source.slice(checkStart, signEnd) +
    ';return sign;')(...Object.values(bindings));
  const purpose = Object.freeze({kind: 'read', resource: 'customers', decision: Object.freeze({})});
  const input = Object.freeze({operation: 'read', runInvocationCid: cid('b'),
    dispatchRequestCid: cid('c'), maxUses: 2, issuerPurpose: purpose});
  return {sign, input, journal, issued, purpose, profile};
}

test('Source signer uses the original existing native grant constructor and signed scope', async t => {
  const f = await originalSourceSigner(t);
  assert.equal(control.issue, undefined, 'The selected original control has no second issue API');
  const authorization = f.sign(f.input);
  assert(Object.isFrozen(authorization));assert(Object.isFrozen(authorization.scope));
  assert.equal(f.issued.get(authorization).issuerPurpose, f.purpose);
  const grantCid = control.identity(authorization.grant);
  const body = JSON.parse(control.json(authorization.grant));
  assert.deepEqual(body, {version: 'actql-remote-credential-grant/0.1',
    issuer_authority: 'source-authority', principal: 'source-principal',
    namespace_id: 'source-constructor-test', environment: 'test', site_key: 'source-site', site_generation: 1,
    runtime_bundle_cid: cid('a'), connector_registration: 'rest-acme', connector_revision: 'acme/0.1',
    resource_origin: 'https://resource.example', operation: 'read', run_invocation_cid: cid('b'),
    task_attempt: 1, dispatch_request_cid: cid('c'), expires_unix_ms: '2000000000000', max_uses: 2});
  const first = f.journal.claim(grantCid, 'original-use', 1_999_999_999_999n, authorization.scope, control);
  assert.equal(first.replayed, false);assert.equal(first.record.useOrdinal, 1);
  f.journal.finish(first.record.useCid, 'unknown');
});

test('Source signer re-admission keeps the original signed-scope durable use budget', async t => {
  const f = await originalSourceSigner(t), first = f.sign(f.input);
  const id = control.identity(first.grant);
  const used = f.journal.claim(id, 'first-use', 1_999_999_999_999n, first.scope, control);
  f.journal.finish(used.record.useCid, 'unknown');
  const repeated = f.sign(f.input);
  assert.equal(control.identity(repeated.grant), id);
  const second = f.journal.claim(id, 'second-use', 1_999_999_999_999n, repeated.scope, control);
  assert.equal(second.record.useOrdinal, 2);
  f.journal.finish(second.record.useCid, 'unknown');
  assert.throws(() => f.journal.claim(id, 'third-use', 1_999_999_999_999n, repeated.scope, control));
  assert.throws(() => control.prepareUse(first.grant, {useId: 'foreign-operation',
    trustedNowMilliseconds: 1_999_999_999_999n, usedCount: 0, revoked: false,
    scope: {...first.scope, operation: 'other'}}));
});
