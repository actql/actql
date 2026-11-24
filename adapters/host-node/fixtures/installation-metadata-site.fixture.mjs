// Shared ordinary publication, Account, and original metadata Site setup.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import * as moon from '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../host-common/runtime-result.mjs';
import {openSqliteCredentialJournal} from '../../site-node/sqlite-credential-journal.mjs';
import {createInstalledConnectorTable} from '../installed-connectors.mjs';
import {publishInstalledSourceProfile} from '../installed-source.mjs';
import {createLocalAuthorizationGate, sourceReadAccountConfiguration} from '../local-account-config.mjs';
import {openRowSourceCredentialSite} from '../installed-row-source.mjs';

const version = 'actql-installed-metadata-site-fixture/0.1';
export const metadataSiteNow = 1_700_000_000_000;
const now = metadataSiteNow;
const origin = 'https://api.example.test';
const operation = 'fixture:metadata:initial';
const dependent = 'fixture:metadata:dependent';
const cid = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const code = value => ({code: value});

export async function installationMetadataSiteFixture(t, body, {outcome = 'allow', journal, authorization,
  input, openSite = openRowSourceCredentialSite, configurationReader, beforeJournal} = {}) {
  const parent = new URL('../../../_build/metadata-site-fixtures/', import.meta.url);
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent.pathname, 'original-'));
  console.error(`Metadata Site original custody retained: ${root}`);
  const profilePath = join(root, 'profile.json');
  const sitePath = join(root, 'site.json');
  const accountPath = join(root, 'account.json');
  const keyPath = join(root, 'issuer.key');
  const key = generateKeyPairSync('ed25519');
  const issuerPem = key.privateKey.export({type: 'pkcs8', format: 'pem'});
  await writeFile(keyPath, issuerPem, {mode: 0o600});
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
  const state = {root, profilePath, sitePath, accountPath, accountWire, profile, issuerPem,
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
        site = await openSite({profile, principalId: options.principalId,
          authorization: gate, connection: checkedProfile.connection,
          connectorRegistration: options.installation.registration,
          connectorRevision: options.installation.revision,
          runtimeBundleCid: options.runtimeBundleCid, commonMoon: options.moon,
          resolveSecret, now: () => now, grantLifetimeMs: 120_000, installationMetadata,
          ...(configurationReader === undefined ? {} : {configurationReader: configurationReader(state)}),
          openCredentialJournal(path, journalOptions) {
            opens++; beforeJournal?.(path, journalOptions);
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
    principalId: 'original-principal', moon, connectorTable, resolveSecret,
    runtimeUrl: new URL('../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
      import.meta.url)})};
}
