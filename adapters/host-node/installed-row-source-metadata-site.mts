import {types as nodeTypes} from 'node:util';
import {invocationBindingsMatch} from '../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource, openHttpsCredentialBinding, closeHttpsCredentialBinding}
  from '../site-node/https-credential-resource.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';

import type {createInstallationPreparationMetadata} from '../host-common/installation-preparation-metadata.mjs';
import type {createInstalledRowSourceCredentialCustody} from './installed-row-source-credential-custody.mjs';

type Issuers = ReturnType<typeof createInstalledRowSourceCredentialCustody>;
type Custody = ReturnType<Issuers['openRowSourceCredentialCustody']>;
type CustodyOptions = Parameters<Issuers['openRowSourceCredentialCustody']>[0];
type MetadataView = ReturnType<typeof createInstallationPreparationMetadata>;
type MetadataControl = ReturnType<MetadataView['forSubject']>;
type Scope = ReturnType<MetadataView['prepareScope']>;
type ResolveSecret = CustodyOptions['resolveSecret'];
type ResourceCall = typeof callHttpsCredentialResource;
type ResourceOptions = Parameters<ResourceCall>[0];
type ClosedMethod = (...args: unknown[]) => unknown;
type AccountMethod = 'authorize' | 'assertAccountCurrent' | 'assertConfigurationCurrent';
type AccountAuthority = Readonly<{
  configurationCid?: string;
  accountId?: unknown;
  principal?: unknown;
  assertAccountCurrent?: unknown;
  assertConfigurationCurrent?: unknown;
}>;
type MetadataOptions = Pick<CustodyOptions, 'profile' | 'principalId' | 'connectorRegistration' |
  'connectorRevision' | 'runtimeBundleCid' | 'commonMoon' | 'resolveSecret' | 'ca' | 'now' | 'grantLifetimeMs'> & {
  installationMetadata: unknown;
  authorization: AccountAuthority;
  connection: string;
};
type RuntimeCore = (moon: unknown) => {installationPreparationMetadata(): MetadataView};
type RegisteredSite = Readonly<{
  site: object;
  credential: MetadataCredential;
  referenceCurrent(): boolean;
  callResource: ResourceCall;
  authorizationPurpose(authorization: MetadataAuthorization): Readonly<{
    kind: 'installation-metadata';
    control: MetadataControl;
  }>;
  bindRunAcquisition(authorization: MetadataAuthorization, callbacks: unknown): MetadataAcquisition;
  readChildCredential(acquisition: MetadataAcquisition, authorization: MetadataAuthorization): MetadataCredential;
}>;
type OriginalMetadataInputs = Readonly<{
  publicationRequest: unknown;
  originals: unknown;
  declaration: unknown;
  declarationSourceCid?: string;
  operations: readonly string[];
  maxOperations: number;
  maxSecretBytes: number;
  maxIssuerKeyBytes: number;
  maxCaBytes: number;
  targetAuthority: unknown;
  siteCurrent: unknown;
}>;
type AuthorityProjection = Readonly<{installation?: {registration?: unknown; revision?: unknown}}>;
type MetadataTarget = Readonly<{
  resource: string;
  operation: string;
  origin: string;
  method: 'GET';
  path: string;
  bodyBytes: 0;
}>;
type AccountDecision = Readonly<{
  action: unknown;
  boundary: unknown;
  subjectCid: unknown;
  contextCid: unknown;
  tuple?: Readonly<{principal: unknown; connection: unknown; resource: unknown; operation: unknown}>;
}>;
type MetadataCredential = Readonly<{
  binding: object;
  control: MetadataControl;
  journal: Custody['credential']['journal'];
  resolveSecret: ResolveSecret;
  ca: string | undefined;
  now: () => number;
}>;
type MetadataGrantRequest = Readonly<{
  target: unknown;
  metadataOccurrenceId: string;
  useId: string;
  expiresUnixMilliseconds: bigint;
  maxUses: number;
}>;
type MetadataAuthorization = ReturnType<Custody['signInstallationMetadata']> & Readonly<{useId: string}>;
type MetadataChild = {retired: boolean};
type MetadataEntry = {
  target: unknown;
  facts: MetadataTarget;
  scope: Scope;
  decision: AccountDecision | undefined;
  failure: unknown;
  signed?: ReturnType<Custody['signInstallationMetadata']>;
  child?: MetadataChild;
};
type MetadataAcquisition = Readonly<{
  authorization: MetadataAuthorization;
  credential: MetadataCredential;
  close(): 'closed' | 'pending';
  retire(): boolean;
}>;

// An operational alternative of this same installed Credential Site. Common
// owns Subject/Scope DATA; the original Host, Account, Site and issuer remain
// necessary at every action. Resource/egress admission is a separate caller
// duty, never supplied by a bounded key read or a signed metadata grant.
export async function prepareInstallationMetadataSite(options: MetadataOptions,
  runtimeCore: RuntimeCore, operationSites: {set(credential: object, site: RegisteredSite): void},
  text: (value: unknown) => value is string, cidPattern: RegExp) {
  const {installationMetadata: input, profile, principalId, authorization,
    connection, connectorRegistration, connectorRevision, runtimeBundleCid,
    commonMoon, resolveSecret, ca, now, grantLifetimeMs} = options;
  const invalid: () => never = () => fail('InvalidRowSourceInstallationMetadata');
  const positive = (value: unknown): value is number =>
    Number.isSafeInteger(value) && (value as number) > 0 && (value as number) <= 2147483647;
  const data = <Key extends string>(value: unknown, keys: readonly Key[]): Readonly<Record<Key, unknown>> => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value) ||
        Object.getPrototypeOf(value) !== Object.prototype) invalid();
    const descriptors = Object.getOwnPropertyDescriptors(value);
    const names = Reflect.ownKeys(descriptors);
    if (names.length !== keys.length || names.some(key => !keys.includes(key as Key))) invalid();
    return Object.fromEntries(keys.map(key => {
      const descriptor = descriptors[key];
      if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
      return [key, descriptor.value];
    })) as Readonly<Record<Key, unknown>>;
  };
  const original = data(input, ['publicationRequest', 'originals', 'declaration',
    'declarationSourceCid', 'operations', 'maxOperations', 'maxSecretBytes',
    'maxIssuerKeyBytes', 'maxCaBytes', 'targetAuthority', 'siteCurrent']) as OriginalMetadataInputs;
  if (original.declaration === null || typeof original.declaration !== 'object' ||
      !cidPattern.test(original.declarationSourceCid ?? '') ||
      !positive(original.maxOperations) || !positive(original.maxSecretBytes) ||
      !positive(original.maxIssuerKeyBytes) || !positive(original.maxCaBytes) ||
      !Array.isArray(original.operations) || nodeTypes.isProxy(original.operations) ||
      original.operations.length === 0 || original.operations.length > original.maxOperations ||
      original.operations.some(operation => !text(operation)) ||
      typeof authorization?.assertAccountCurrent !== 'function' ||
      typeof authorization?.assertConfigurationCurrent !== 'function' ||
      !cidPattern.test(authorization.configurationCid ?? '') ||
      !text(authorization.accountId) || authorization.principal !== principalId ||
      !positive(grantLifetimeMs) || !text(connection)) invalid();
  const operations = new Set(original.operations);
  if (operations.size !== original.operations.length) invalid();
  const targetAuthority = data(original.targetAuthority, ['project']);
  const siteCurrent = data(original.siteCurrent, ['observe', 'assertCurrent']);
  if ([targetAuthority.project, siteCurrent.observe, siteCurrent.assertCurrent]
    .some(method => typeof method !== 'function')) invalid();
  const account = Object.freeze(Object.fromEntries(['accountId', 'configurationCid',
    'principal', 'contextCid'].map(name => {
    const descriptor = Object.getOwnPropertyDescriptor(authorization, name);
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) invalid();
    return [name, descriptor.value];
  })));
  const accountMethods = Object.fromEntries(['authorize', 'assertAccountCurrent',
    'assertConfigurationCurrent'].map(name => {
    const descriptor = Object.getOwnPropertyDescriptor(authorization, name);
    if (!descriptor || !Object.hasOwn(descriptor, 'value') ||
        typeof descriptor.value !== 'function') invalid();
    return [name, descriptor.value];
  }));
  const callAccount = (name: AccountMethod, ...args: unknown[]): unknown => Reflect.apply(accountMethods[name], authorization, args);
  // Capture the actual entry pair once; accessors cannot substitute another
  // runtime, provider, resolver or checked profile across an await.
  const pairNames = ['root', 'principalId', 'moon', 'installation', 'profile',
    'resolveSecret', 'runtimeBundleCid', 'providerMoon'];
  if (original.originals === null || typeof original.originals !== 'object' ||
      nodeTypes.isProxy(original.originals)) invalid();
  const descriptors = Object.getOwnPropertyDescriptors(original.originals ?? {});
  const pair = Object.freeze(Object.fromEntries(pairNames.map(name => {
    const descriptor = descriptors[name];
    if (descriptor === undefined && name === 'providerMoon') return [name, undefined];
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) invalid();
    return [name, descriptor.value];
  })));
  if (pair.principalId !== principalId || pair.moon !== commonMoon ||
      pair.resolveSecret !== resolveSecret || pair.runtimeBundleCid !== runtimeBundleCid ||
      (pair as AuthorityProjection).installation?.registration !== connectorRegistration ||
      (pair as AuthorityProjection).installation?.revision !== connectorRevision) invalid();
  const host = await import('./installed-source.mjs');
  host.assertInstalledSourcePublicationRequest(original.publicationRequest, pair);
  const view = runtimeCore(commonMoon).installationPreparationMetadata();
  const subject = view.prepareSubject({
    accountConfigurationCid: account.configurationCid,
    accountId: account.accountId, connection, connectorRegistration,
    connectorRevision, declarationSourceCid: original.declarationSourceCid,
    installationRequestId: host.installedSourcePublicationRequestId(original.publicationRequest),
    principal: principalId, runtimeBundleCid, siteGeneration: profile.siteGeneration,
    siteKey: profile.siteKey,
  });
  const control = view.forSubject(subject);
  const subjectCid = view.subjectCid(subject);
  const profileKeys = ['credentialPrivateKeyPath', 'credentialAuthorityId',
    'credentialKeyId', 'journalRoot', 'resourceOrigin', 'namespaceId',
    'environment', 'siteKey', 'siteGeneration'] as const;
  const selectedProfile = Object.freeze(Object.fromEntries(profileKeys.map(key => {
    const descriptor = Object.getOwnPropertyDescriptor(profile, key);
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) invalid();
    return [key, descriptor.value];
  }))) as CustodyOptions['profile'];
  // The selected PEM authority is immutable in the exposed credential facts.
  // This purpose does not accept an arbitrary mutable TLS option object.
  let authority: string | undefined;
  if (ca !== undefined) {
    if (!(typeof ca === 'string' || Buffer.isBuffer(ca)) ||
        ca.length > original.maxCaBytes) invalid();
    authority = typeof ca === 'string' ? ca : ca.toString('latin1');
    if (authority.length > original.maxCaBytes || /[^\x00-\x7f]/u.test(authority)) invalid();
  }
  const synchronous = (result: unknown) => {
    if (result !== undefined) {
      if (typeof (result as {then?: unknown} | null)?.then === 'function') void Promise.resolve(result).catch(() => {});
      fail('InvalidInstallationMetadataCurrentFence');
    }
  };
  let closing = false, closed = false, binding: object | undefined, bindingClosed = false;
  let journalClosed = false, retired = false, custody: Custody | undefined,
    credential: MetadataCredential | undefined, originalFailure: unknown;
  const entries = new Map<string, MetadataEntry>(), authorizations = new WeakMap<object, MetadataEntry>(),
    children = new Set<MetadataChild>();
  const acquisitions = new WeakMap<object, MetadataChild>();
  const profileCurrent = () => profileKeys.every(key => {
    const descriptor = Object.getOwnPropertyDescriptor(profile, key);
    return descriptor !== undefined && Object.hasOwn(descriptor, 'value') &&
      descriptor.value === selectedProfile[key];
  });
  const ensureCurrent = (operation?: string) => { try {
    if (closing) fail('RowSourceSiteClosed');
    if (originalFailure !== undefined) throw originalFailure;
    host.assertInstalledSourcePublicationRequest(original.publicationRequest, pair);
    if (!profileCurrent()) {
      fail('RowSourceInstallationMetadataSiteChanged');
    }
    synchronous(Reflect.apply(siteCurrent.assertCurrent as ClosedMethod, original.siteCurrent, []));
    if (closing) fail('RowSourceSiteClosed');
    synchronous(callAccount('assertConfigurationCurrent'));
    for (const entry of entries.values()) {
      if ((operation === undefined || entry.facts.operation === operation) && entry.decision !== undefined) {
        synchronous(callAccount('assertAccountCurrent', entry.decision));
      }
    }
    if (closing) fail('RowSourceSiteClosed');
    host.assertInstalledSourcePublicationRequest(original.publicationRequest, pair);
    if (!profileCurrent()) {
      fail('RowSourceInstallationMetadataSiteChanged');
    }
  } catch (cause) { if (!closing) originalFailure ??= cause; throw cause; } };
  const factsFor = (target: unknown) => {
    const facts = data(Reflect.apply(targetAuthority.project as ClosedMethod, original.targetAuthority,
      [target, original.declaration]), ['resource', 'operation', 'origin', 'method', 'path', 'bodyBytes']);
    if (!text(facts.resource) || !operations.has(facts.operation as string) ||
        facts.origin !== selectedProfile.resourceOrigin || facts.method !== 'GET' ||
        !text(facts.path) || facts.bodyBytes !== 0) invalid();
    return Object.freeze(facts) as MetadataTarget;
  };
  const current = async (operation: string) => {
    try {
      if (!operations.has(operation)) fail('RowSourceMetadataOperationNotRegistered');
      ensureCurrent(operation);
      await host.observeInstalledSourcePublicationCurrent(original.publicationRequest, pair);
      ensureCurrent(operation);
      synchronous(await Reflect.apply(siteCurrent.observe as ClosedMethod, original.siteCurrent, []));
      ensureCurrent(operation);
    } catch (cause) { originalFailure ??= cause; throw cause; }
  };
  return Object.freeze({maxIssuerKeyBytes: original.maxIssuerKeyBytes,
    privateKeyPath: selectedProfile.credentialPrivateKeyPath,
    assertInitializingCurrent: () => ensureCurrent(),
    close() {
      // Before Journal acquisition, the existing initialization Owner may
      // retain this view behind an original bounded-key FD cleanup duty.
      if (custody !== undefined) fail('RowSourceMetadataSiteAlreadyAttached');
      closing = true;
      if (!retired) {view.retireMetadataView(); retired = true;}
    },
    attach(originalCustody: Custody) {
      custody = originalCustody;
      const retainedJournal = custody.installationMetadataJournal();
      const site = {
        connection,
        current,
        async issueMetadataGrant({target, metadataOccurrenceId, useId,
          expiresUnixMilliseconds, maxUses}: MetadataGrantRequest) {
          ensureCurrent();
          if (!text(metadataOccurrenceId) || !text(useId) ||
              typeof expiresUnixMilliseconds !== 'bigint' ||
              !Number.isSafeInteger(maxUses) || maxUses <= 0 || maxUses > 10_000) invalid();
          if (entries.has(metadataOccurrenceId)) fail('RowSourceMetadataOccurrenceAlreadyPrepared');
          if (entries.size >= original.maxOperations) fail('RowSourceMetadataOperationLimit');
          const facts = factsFor(target);
          const scope = view.prepareScope(subject, {metadataOccurrenceId,
            operation: facts.operation, resourceOrigin: facts.origin,
            requestMethod: 'GET', requestPath: facts.path,
            requestBodyCid: 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'});
          // Retain the original target and fallible outcome before the first
          // await. A failed/Unknown occurrence cannot be prepared again here.
          const entry: MetadataEntry = {target, facts, scope, decision: undefined, failure: undefined};
          entries.set(metadataOccurrenceId, entry);
          try {
            await current(facts.operation);
            const decision = await callAccount('authorize', 'acquisition', {
              connection, resource: facts.resource, operation: 'read'}, {subjectCid}) as AccountDecision;
            ensureCurrent(facts.operation);
            if (decision.action !== 'dispatch' ||
                decision.boundary !== 'acquisition' || decision.subjectCid !== subjectCid ||
                decision.contextCid !== account.contextCid ||
                decision.tuple?.principal !== principalId ||
                decision.tuple?.connection !== connection ||
                decision.tuple?.resource !== facts.resource || decision.tuple?.operation !== 'read') {
              fail('RowSourceMetadataGrantNotAuthorized');
            }
            // The Account Owner checks this exact scope's nominal dispatch;
            // an equal/copied decision cannot supply current authority.
            synchronous(callAccount('assertAccountCurrent', decision));
            entry.decision = decision;
            ensureCurrent(facts.operation);
            const observed = factsFor(target);
            if ((Object.keys(facts) as (keyof MetadataTarget)[]).some(key => facts[key] !== observed[key])) {
              fail('RowSourceMetadataTargetChanged');
            }
            const trustedNow = now();
            if (!Number.isSafeInteger(trustedNow) || trustedNow < 0 ||
                expiresUnixMilliseconds <= BigInt(trustedNow) ||
                expiresUnixMilliseconds > BigInt(trustedNow) + BigInt(grantLifetimeMs)) invalid();
            const signed = custody!.signInstallationMetadata({control, scope,
              expiresUnixMilliseconds, maxUses});
            entry.signed = signed;
            ensureCurrent(facts.operation);
            if (binding === undefined) {
              binding = openHttpsCredentialBinding({scope, control,
                journal: custody!.credential.journal, resolveSecret,
                maxSecretBytes: original.maxSecretBytes, assertCurrent: () => ensureCurrent()});
              credential = Object.freeze({binding, control,
                journal: custody!.credential.journal, resolveSecret, ca: authority, now});
              // The metadata Site retains its original Subject, binding and
              // Journal. This private operation view can lend only that SAME
              // original to the shared reader; equal envelopes do not select it.
              operationSites.set(credential, Object.freeze({site, credential,
                referenceCurrent: site.referenceCurrent, callResource: site.callResource,
                authorizationPurpose(authorization: MetadataAuthorization) {
                  const entry = authorizations.get(authorization);
                  if (entry === undefined) fail('ForeignRowSourceMetadataChild');
                  ensureCurrent(entry.facts.operation);
                  return Object.freeze({kind: 'installation-metadata', control});
                },
                bindRunAcquisition(authorization: MetadataAuthorization, callbacks: unknown) {
                  const entry = authorizations.get(authorization);
                  if (entry === undefined || entry.child !== undefined || children.size !== 0 || bindingClosed) {
                    fail('ForeignRowSourceMetadataChild');
                  }
                  const methods = data(callbacks, ['assertCurrent', 'observeCurrent']);
                  if (typeof methods.assertCurrent !== 'function' || typeof methods.observeCurrent !== 'function') invalid();
                  synchronous(Reflect.apply(methods.assertCurrent, callbacks, []));
                  ensureCurrent(entry.facts.operation);
                  // No external callback follows insertion before this original
                  // is returned. A failed current fence cannot strand a lease.
                  const record = {retired: false};
                  const acquisition: MetadataAcquisition = Object.freeze({authorization, credential: credential!,
                    close() {
                      if (this !== acquisition) fail('ForeignRowSourceMetadataChild');
                      if (!bindingClosed) bindingClosed = closeHttpsCredentialBinding(binding!) === 'closed';
                      return bindingClosed ? 'closed' : 'pending';
                    },
                    retire() {
                      if (this !== acquisition) fail('ForeignRowSourceMetadataChild');
                      if (record.retired) return true;
                      if (!bindingClosed) return false;
                      record.retired = true;children.delete(record);
                      return true;
                    }});
                  entry.child = record;children.add(record);acquisitions.set(acquisition, record);
                  return acquisition;
                },
                readChildCredential(acquisition: MetadataAcquisition, authorization: MetadataAuthorization) {
                  const record = acquisitions.get(acquisition), entry = authorizations.get(authorization);
                  if (record === undefined || record.retired || !children.has(record) || entry === undefined ||
                      entry.child !== undefined && entry.child !== record || bindingClosed) {
                    fail('ForeignRowSourceMetadataChild');
                  }
                  ensureCurrent(entry.facts.operation);
                  // The control checks both scopes against the SAME nominal
                  // metadata Subject, never a copied request/Run substitute.
                  if (!invocationBindingsMatch(authorization.scope, acquisition.authorization.scope, control)) {
                    fail('ForeignRowSourceMetadataChild');
                  }
                  entry.child = record;
                  return credential!;
                },
              }));
            }
            const authorization = Object.freeze({...signed, useId});
            authorizations.set(authorization, entry);
            return authorization;
          } catch (cause) {
            entry.failure = cause;
            originalFailure ??= cause;
            throw cause;
          }
        },
        callResource(options: ResourceOptions) {
          ensureCurrent();
          for (const operation of (options?.operations as ReadonlyMap<string, {responseHeaders?: readonly string[]}> | undefined)?.values?.() ?? []) {
            if ((operation.responseHeaders ?? []).length !== 0) fail('UndeclaredResponseHeader');
          }
          return callHttpsCredentialResource(options);
        },
        credential() {
          ensureCurrent();
          if (credential === undefined) fail('RowSourceMetadataGrantUnavailable');
          return credential;
        },
        referenceCurrent: () => !closing && originalFailure === undefined && custody!.referenceCurrent(),
        cleanupPending: () => closing && !closed,
        close() {
          closing = true;
          if (closed) return;
          if (binding !== undefined && !bindingClosed) {
            bindingClosed = closeHttpsCredentialBinding(binding!) === 'closed';
            if (!bindingClosed) fail('RowSourceMetadataCleanupPending');
          }
          // A closed socket is not retirement of the shared reader's
          // callbacks/response aliases. Keep the SAME Journal while borrowed.
          if (children.size !== 0) fail('RowSourceMetadataCleanupPending');
          if (!journalClosed) { retainedJournal.close(); journalClosed = true; }
          if (!retired) { view.retireMetadataView(); retired = true; }
          closed = true;
        },
      };
      return Object.freeze({site: Object.freeze(site), failure: retainedJournal.failure});
    },
  });
}
