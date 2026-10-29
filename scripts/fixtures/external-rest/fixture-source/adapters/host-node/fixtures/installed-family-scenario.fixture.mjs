// Shared physical test setup, not another Source/Effect/Credential Owner.
// Provider fixtures supply authored Project data, routes and independent
// expectations. The installed product creates grants, capacity, journals,
// Runs, approval claims and their actual retirement.
import {generateKeyPairSync, randomBytes} from 'node:crypto';
import {mkdir, mkdtemp, realpath, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {isAbsolute, join, relative, resolve, sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import {openHttpsExchangeFixture} from '../../site-node/https-exchange-fixture.mjs';
import {ownRequestHeaders} from '../../host-common/http-exchange.mjs';

function inside(root, path) {
  const suffix = relative(root, path);
  return suffix !== '..' && !suffix.startsWith(`..${sep}`) && !isAbsolute(suffix);
}

function pem(key) {
  return key.export({format: 'pem',
    type: key.type === 'private' ? 'pkcs8' : 'spki'});
}

async function writeKeys(root, role) {
  const pair = generateKeyPairSync('ed25519');
  const privateKeyPath = join(root, `${role}.key`);
  const publicKeyPath = join(root, `${role}.pub`);
  await writeFile(privateKeyPath, pem(pair.privateKey), {mode: 0o600, flag: 'wx'});
  await writeFile(publicKeyPath, pem(pair.publicKey), {mode: 0o600, flag: 'wx'});
  return Object.freeze({privateKeyPath, publicKeyPath,
    publicKeyPem: pem(pair.publicKey)});
}

export async function createInstalledFamilyScenario(t, {scratchParent, scenario,
  accountConfigurationWire, accountConfigurationForKeys,
  routes = [], faults = [], provider, maxRequestBytes, secretPresentation = 'bearer'} = {}) {
  if (typeof scratchParent !== 'string' || !isAbsolute(scratchParent)) {
    throw new TypeError('InstalledFamilyScratchParentRequired');
  }
  if (typeof scenario?.id !== 'string' || scenario.id.length === 0) {
    throw new TypeError('InstalledFamilyScenarioRequired');
  }
  // This is an explicit test operator's normal Account input. No Allow,
  // delegation or provider permissions are synthesized as a fallback.
  if (accountConfigurationForKeys === undefined
    ? typeof accountConfigurationWire !== 'string' || accountConfigurationWire.length === 0
    : typeof accountConfigurationForKeys !== 'function' || accountConfigurationWire !== undefined) {
    throw new TypeError('InstalledFamilyExplicitAccountRequired');
  }
  if (!['bearer', 'kintone-api-token'].includes(secretPresentation) ||
      (secretPresentation === 'kintone-api-token' && provider === undefined)) {
    throw new TypeError('InstalledFamilySecretPresentationRequired');
  }
  if (provider !== undefined && (routes.length !== 0 || faults.length !== 0 ||
      !Number.isSafeInteger(maxRequestBytes) || maxRequestBytes <= 0)) {
    throw new TypeError('InstalledFamilyProviderTransportRequired');
  }
  const providerRoute = provider === undefined ? undefined
    : installedFamilyProviderRoute(provider, {secretPresentation});
  const root = await mkdtemp(join(scratchParent, 'actql-installed-family-'));
  const project = join(root, 'project');
  const home = join(root, 'home');
  const keys = join(root, 'keys');
  await Promise.all([project, home, keys].map(path => mkdir(path, {mode: 0o700})));
  const accountPath = join(root, 'operator-account.json');
  const [host, reviewer, credentialAuthority] = await Promise.all(
    ['host', 'reviewer', 'credential-authority'].map(role => writeKeys(keys, role)));
  // Render only explicitly supplied test Account DATA against fresh public
  // key DATA, before any Host exists. Never append grants or retain a signer.
  const finalAccountConfigurationWire = accountConfigurationForKeys === undefined ? accountConfigurationWire
    : await accountConfigurationForKeys(Object.freeze({hostPublicKeyPem: host.publicKeyPem,
      reviewerPublicKeyPem: reviewer.publicKeyPem,
      credentialAuthorityPublicKeyPem: credentialAuthority.publicKeyPem}));
  if (typeof finalAccountConfigurationWire !== 'string' || !finalAccountConfigurationWire) {
    throw new TypeError('InstalledFamilyExplicitAccountRequired');
  }
  await writeFile(accountPath, finalAccountConfigurationWire, {mode: 0o600, flag: 'wx'});
  // This is only a fresh physical fixture secret, not a Credential issuance,
  // grant or permission. The normal product must bind its own Credential to it.
  let providerTokenPath, expectedAuthorization, expectedKintoneApiToken;
  if (providerRoute !== undefined) {
    const token = randomBytes(32).toString('base64url');
    providerTokenPath = join(keys, 'provider-token');
    await writeFile(providerTokenPath, token, {mode: 0o600, flag: 'wx'});
    if (secretPresentation === 'kintone-api-token') expectedKintoneApiToken = token;
    else expectedAuthorization = `Bearer ${token}`;
  }
  const https = await openHttpsExchangeFixture(t, {
    routes: providerRoute === undefined ? routes : [providerRoute], faults,
    ...(secretPresentation === 'kintone-api-token' ? {expectedKintoneApiToken} : {expectedAuthorization}),
    maxRequestBytes,
    scratchParent: root, preserveScratch: true});
  const projectOriginal = await realpath(project);
  return Object.freeze({
    scenario: structuredClone(scenario),
    root,
    paths: Object.freeze({project, home, state: join(root, 'state'),
      credentialJournal: join(root, 'credential-journal'), accountPath,
      originalReference: join(root, 'original-reference.json')}),
    keys: Object.freeze({host, reviewer, credentialAuthority}),
    ...(providerTokenPath === undefined ? {} : {providerTokenPath}),
    accountConfigurationWire: finalAccountConfigurationWire,
    resourceHttps: Object.freeze({origin: https.origin,
      caPem: https.ca.toString('utf8'), caPath: https.caPath}),
    https,
    async writeProjectInput(name, bytes) {
      if (typeof name !== 'string' || name.length === 0 || isAbsolute(name)) {
        throw new TypeError('InstalledFamilyRelativeInputRequired');
      }
      const path = resolve(project, name);
      if (path === project || !inside(project, path)) {
        throw new TypeError('InstalledFamilyInputOutsideProject');
      }
      if (await realpath(project) !== projectOriginal) {
        throw new TypeError('InstalledFamilyInputOutsideProject');
      }
      const parent = resolve(path, '..');
      let current = project;
      for (const component of relative(project, parent).split(sep).filter(Boolean)) {
        current = join(current, component);
        try { await mkdir(current, {mode: 0o700}); }
        catch (cause) { if (cause.code !== 'EEXIST') throw cause; }
        if (!inside(projectOriginal, await realpath(current))) {
          throw new TypeError('InstalledFamilyInputOutsideProject');
        }
      }
      await writeFile(path, bytes, {mode: 0o600, flag: 'wx'});
      return path;
    },
  });
}

// Thin DATA adaptation only. The provider owns the independent business
// expectations and records every write. TLS owns actual authentication,
// request-byte admission and the socket loss after a successful handler.
export function installedFamilyProviderRoute(provider, {secretPresentation = 'bearer'} = {}) {
  if (!['bearer', 'kintone-api-token'].includes(secretPresentation)) {
    throw new TypeError('InstalledFamilySecretPresentationRequired');
  }
  if (typeof provider?.handle !== 'function') {
    throw new TypeError('InstalledFamilyProviderHandlerRequired');
  }
  return Object.freeze({async handle(exchange) {
    let headers;
    if (secretPresentation === 'kintone-api-token') {
      // Select only original nonsecret DATA. The existing HTTP Owner checks
      // exact spelling, visible bytes and its bound; no credential value or
      // arbitrary header collection enters the provider callback.
      const original = Object.getOwnPropertyDescriptor(exchange.headers ?? {}, 'x-http-method-override');
      if (original === undefined || !Object.hasOwn(original, 'value')) {
        throw new TypeError('InstalledFamilyMethodOverrideRequired');
      }
      headers = ownRequestHeaders([['x-http-method-override', original.value]]);
    }
    const reply = await provider.handle({method: exchange.method,
      target: exchange.path, body: exchange.body, ...(headers === undefined ? {} : {headers})});
    if (reply === null || typeof reply !== 'object' ||
        !Number.isInteger(reply.statusCode) || reply.statusCode < 200 || reply.statusCode > 599 ||
        typeof reply.body !== 'string' || reply.dropAfterApply !== undefined &&
        typeof reply.dropAfterApply !== 'boolean') {
      throw new TypeError('InstalledFamilyProviderReplyRequired');
    }
    return {status: reply.statusCode, body: reply.body,
      dropAfterApply: reply.dropAfterApply === true};
  }});
}

// Reuse the caller's already verified ordinary cohort. Resolution uses only
// its public package export; a development alias escaping node_modules is
// refused. Release/source/hash verification stays the existing producer and
// verifyPackageRelease duty and is done once per cohort, not per operation.
export async function installedFamilyNodeClient(nodeModules) {
  if (typeof nodeModules !== 'string' || !isAbsolute(nodeModules)) {
    throw new TypeError('InstalledFamilyNodeModulesRequired');
  }
  const original = await realpath(nodeModules);
  const require = createRequire(pathToFileURL(join(original, '..', 'family-consumer.cjs')));
  const entry = await realpath(require.resolve('@actql/node'));
  if (!inside(original, entry)) {
    throw new TypeError('InstalledFamilyWorkspaceAliasRefused');
  }
  return import(pathToFileURL(entry).href);
}
