// Actual publication/Account/Common/key/SQLite ownership. These synthetic
// installation targets do not supply provider authority, egress or funding.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteCredentialJournal} from '../site-node/sqlite-credential-journal.mjs';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {publishInstalledSourceProfile} from './installed-source.mjs';
import {createLocalAuthorizationGate, sourceReadAccountConfiguration} from './local-account-config.mjs';
import {openRowSourceCredentialSite} from './installed-row-source.mjs';

const version = 'actql-installed-metadata-site-fixture/0.1';
const now = 1_700_000_000_000;
const origin = 'https://api.example.test';
const operation = 'fixture:metadata:initial';
const dependent = 'fixture:metadata:dependent';
const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const code = value => ({code: value});

async function fixture(t, body, {outcome = 'allow', journal, authorization, input} = {}) {
  const parent = new URL('../../_build/metadata-site-fixtures/', import.meta.url);
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent.pathname, 'original-'));
  console.error(`Metadata Site original custody retained: ${root}`);
  const profilePath = join(root, 'profile.json');
  const sitePath = join(root, 'site.json');
  const accountPath = join(root, 'account.json');
  const keyPath = join(root, 'issuer.key');
  const key = generateKeyPairSync('ed25519');
  await writeFile(keyPath, key.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  const source = JSON.stringify({views: [{resource: 'records', resource_kind: 'record',
    fields: [{name: 'id', type: 'number', nullable: false}]}]});
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    'fixture', 'fixture', 'fixture/0.1', source, undefined));
  const profile = {credentialPrivateKeyPath: keyPath,
    credentialAuthorityId: 'original-authority', credentialKeyId: 'original-key',
    journalRoot: join(root, 'journal'), resourceOrigin: origin,
    namespaceId: 'original-namespace', environment: 'fixture',
    siteKey: 'original-site', siteGeneration: 1};
  const siteWire = JSON.stringify(profile);
  const profileWire = JSON.stringify({version, connection: 'fixture:records'});
  const accountWire = sourceReadAccountConfiguration({connection: 'fixture:records',
    resource: 'records', accountId: 'original-account', outcome});
  await Promise.all([writeFile(profilePath, profileWire), writeFile(sitePath, siteWire),
    writeFile(accountPath, accountWire)]);
  const originalGate = await createLocalAuthorizationGate({accountConfig: accountPath,
    principal: 'original-principal'});
  const gate = authorization?.(originalGate) ?? originalGate;
  let opens = 0, accepted = 0, closes = 0, resolutions = 0, observations = 0;
  let beforeObserve = async () => {}, afterAccept = () => {}, beforeClose = () => {};
  let siteActive = true, site;
  const target = Object.freeze({operation, path: '/v1/original'});
  const selected = Object.freeze({operation: dependent, path: '/v1/original/schema'});
  const members = new Set([target, selected]);
  const targetAuthority = {project(original, originalDeclaration) {
    assert.equal(this, targetAuthority);
    assert.equal(originalDeclaration, declaration);
    if (!members.has(original)) throw Object.assign(new Error('ForeignMetadataTarget'), code('ForeignMetadataTarget'));
    return {resource: 'records', operation: original.operation, origin,
      method: 'GET', path: original.path, bodyBytes: 0};
  }};
  const siteCurrent = {async observe() {
    assert.equal(this, siteCurrent); observations++;
    await beforeObserve();
    assert.equal(await readFile(sitePath, 'utf8'), siteWire);
  }, assertCurrent() {assert.equal(this, siteCurrent); assert.ok(siteActive, 'Original Site current');}};
  const state = {root, profilePath, sitePath, accountPath, accountWire, profile,
    declaration, target, selected, targetAuthority, siteCurrent, originalGate,
    beforeObserve: value => {beforeObserve = value;},
    afterAccept: value => {afterAccept = value;},
    beforeClose: value => {beforeClose = value;},
    deactivate: () => {siteActive = false;},
    counters: () => ({opens, accepted, closes, resolutions, observations}),
    request: (original = target, occurrence = 'original-occurrence') => ({target: original,
      metadataOccurrenceId: occurrence, useId: `${occurrence}:use`,
      expiresUnixMilliseconds: BigInt(now + 60_000), maxUses: 1}),
  };
  const resolveSecret = async () => {resolutions++; return 'fixture-only-secret';};
  const module = {check: value => Object.freeze({...value}),
    identityParts() {assert.fail('No second identity discovery');},
    load() {assert.fail('No query Source installation');},
    async publish(checkedProfile, options) {
      const installationMetadata = {publicationRequest: options.publicationRequest,
        originals: {...options, profile: checkedProfile}, declaration,
        declarationSourceCid: cid(source), operations: [operation, dependent],
        maxOperations: 2, maxSecretBytes: 128, maxIssuerKeyBytes: 4096, maxCaBytes: 4096,
        targetAuthority, siteCurrent};
      input?.(installationMetadata, state);
      state.open = async () => {
        site = await openRowSourceCredentialSite({profile, principalId: options.principalId,
          authorization: gate, connection: checkedProfile.connection,
          connectorRegistration: options.installation.registration,
          connectorRevision: options.installation.revision,
          runtimeBundleCid: options.runtimeBundleCid, commonMoon: options.moon,
          resolveSecret, now: () => now, grantLifetimeMs: 120_000, installationMetadata,
          openCredentialJournal(path, journalOptions) {
            opens++;
            const original = openSqliteCredentialJournal(path, journalOptions);
            const wrapped = {...original, acceptGrant(...args) {
              const result = original.acceptGrant(...args); accepted++; afterAccept(); return result;
            }, close() {closes++; beforeClose(); return original.close();}};
            return journal?.(wrapped, original) ?? Object.freeze(wrapped);
          }});
        state.site = site;
        return site;
      };
      try {return await body(state);}
      finally {site?.close();}
    }};
  const connectorTable = createInstalledConnectorTable([{name: 'fixture', registration: 'fixture',
    revision: 'fixture/0.1', source: {profileVersion: version, load: async () => module}}]);
  t.after(() => {site?.close(); originalGate.close();});
  return {state, run: () => publishInstalledSourceProfile(profilePath, {root,
    principalId: 'original-principal', moon, connectorTable, resolveSecret})};
}

test('same publication, Account and original issuer sign two exact metadata scopes into the original Journal', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    assert.equal(site.issueReadGrant, undefined);
    assert.throws(() => site.credential(), code('RowSourceMetadataGrantUnavailable'));
    for (const [index, target] of [f.target, f.selected].entries()) {
      const signed = await site.issueMetadataGrant(f.request(target, `occurrence-${index}`));
      const {control, journal, binding} = site.credential();
      assert.equal(control.kind, 'installation-metadata'); assert.ok(binding);
      assert.equal(control.subjectFields().accountId, 'original-account');
      assert.equal(control.scopeFields(signed.scope).requestPath, target.path);
      const grantCid = control.identity(signed.grant);
      const claim = journal.claim(grantCid, signed.useId, BigInt(now), signed.scope, control);
      assert.equal(claim.replayed, false);
      assert.equal(journal.authorize(claim.use, BigInt(now), signed.scope, control).outcome, 'claimed');
      journal.finish(control.useIdentity(claim.use), 'succeeded');
      assert.throws(() => runtimeCore(moon).remoteCredentialControl.admitJson(
        control.json(signed.grant), grantCid));
    }
    assert.equal(site.credential().journal.recover().length, 2);
    assert.equal(f.counters().resolutions, 0);
    site.close(); site.close();
    assert.equal(f.counters().closes, 1);
    assert.equal(site.cleanupPending(), false);
    await assert.rejects(site.issueMetadataGrant(f.request()), code('RowSourceSiteClosed'));
  });
  await f.run();
});

test('copied Host request and mixed checked profile refuse before opening an issuer Journal', async t => {
  for (const mutate of [value => {value.publicationRequest = {...value.publicationRequest};},
    value => {value.originals.profile = {...value.originals.profile};}]) {
    const f = await fixture(t, async f => {
      await assert.rejects(f.open(), error => /ForeignInstalledSourcePublication/u.test(error.code));
      assert.equal(f.counters().opens, 0);
    }, {input: mutate});
    await f.run();
  }
});

test('actual Account deny and copied dispatch cannot issue a metadata grant', async t => {
  for (const options of [{outcome: 'deny'}, {authorization: original => ({...original,
    async authorize(...args) {return {...await original.authorize(...args)};}})}]) {
    const f = await fixture(t, async f => {
      const site = await f.open();
      await assert.rejects(site.issueMetadataGrant(f.request()));
      assert.equal(f.counters().accepted, 0); assert.equal(f.counters().resolutions, 0);
    }, options);
    await f.run();
  }
});

test('Account file revoked across await remains stopped even after identical configuration returns', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    f.beforeObserve(() => writeFile(f.accountPath, sourceReadAccountConfiguration({
      connection: 'fixture:records', resource: 'records', accountId: 'original-account', outcome: 'deny'})));
    let failure;
    await assert.rejects(site.issueMetadataGrant(f.request()), error => {failure = error; return true;});
    await writeFile(f.accountPath, f.accountWire);
    await assert.rejects(site.issueMetadataGrant(f.request(f.target, 'no-revival')), error => error === failure);
    assert.equal(f.counters().accepted, 0); assert.equal(f.counters().resolutions, 0);
  });
  await f.run();
});

test('same Site profile changed during await refuses without selecting a replacement issuer', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    f.beforeObserve(async () => {f.profile.credentialKeyId = 'replacement-key';});
    await assert.rejects(site.issueMetadataGrant(f.request()), code('RowSourceInstallationMetadataSiteChanged'));
    assert.equal(f.counters().accepted, 0);
  });
  await f.run();
});

test('post-sign current fence retains the signed occurrence and performs no claim or secret resolution', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    f.afterAccept(f.deactivate);
    await assert.rejects(site.issueMetadataGrant(f.request()), {message: 'Original Site current'});
    assert.equal(f.counters().accepted, 1); assert.equal(f.counters().resolutions, 0);
    await assert.rejects(site.issueMetadataGrant(f.request()));
    assert.equal(f.counters().accepted, 1);
  });
  await f.run();
});

test('original target, method receivers and current callbacks are retained across awaits', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    const captured = f.targetAuthority.project;
    f.beforeObserve(async () => {
      f.targetAuthority.project = () => assert.fail('Replacement target projection');
      f.siteCurrent.assertCurrent = () => assert.fail('Replacement current callback');
    });
    const signed = await site.issueMetadataGrant(f.request());
    assert.equal(site.credential().control.scopeFields(signed.scope).requestPath, '/v1/original');
    assert.equal(captured.call(f.targetAuthority, f.target, f.declaration).bodyBytes, 0);
    await assert.rejects(site.issueMetadataGrant(f.request({...f.target}, 'foreign-target')),
      code('ForeignMetadataTarget'));
  });
  await f.run();
});

test('duplicate occurrence and exhausted finite operation inventory never accept another grant', async t => {
  const f = await fixture(t, async f => {
    const site = await f.open();
    await site.issueMetadataGrant(f.request());
    await assert.rejects(site.issueMetadataGrant({...f.request(), useId: 'different-use'}),
      code('RowSourceMetadataOccurrenceAlreadyPrepared'));
    await site.issueMetadataGrant(f.request(f.selected, 'second'));
    await assert.rejects(site.issueMetadataGrant(f.request(f.target, 'third')),
      code('RowSourceMetadataOperationLimit'));
    assert.equal(f.counters().accepted, 2); assert.equal(f.counters().resolutions, 0);
  });
  await f.run();
});

test('failed original Journal close keeps the same Site pending and skips a later acknowledged close', async t => {
  const failure = new Error('OriginalJournalCloseFailure');
  const f = await fixture(t, async f => {
    const site = await f.open();
    await site.issueMetadataGrant(f.request());
    f.beforeClose(() => {throw failure;});
    assert.throws(() => site.close(), error => error === failure);
    assert.equal(site.cleanupPending(), true);
    await assert.rejects(site.issueMetadataGrant(f.request()), code('RowSourceSiteClosed'));
    f.beforeClose(() => {}); site.close(); site.close();
    assert.equal(site.cleanupPending(), false); assert.equal(f.counters().closes, 2);
  });
  await f.run();
});

test('unsafe mutable Journal admission returns its existing initialization Owner and original close receiver', async t => {
  let replacement = 0;
  const f = await fixture(t, async f => {
    let failure;
    await assert.rejects(f.open(), error => {failure = error; return error.code === 'InstalledHostInitializationFailed';});
    assert.equal(failure.primaryFailure.code, 'InvalidInstallationMetadataJournal');
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.equal(f.counters().closes, 1); assert.equal(replacement, 0);
  }, {journal(wrapped) {
    const close = wrapped.close;
    Object.defineProperty(wrapped, 'close', {value: function () {
      assert.equal(this, wrapped);
      wrapped.close = () => {replacement++; return true;};
      return close();
    }, writable: true, enumerable: true, configurable: true});
    return wrapped;
  }});
  await f.run();
});
