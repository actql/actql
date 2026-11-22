import {createPrivateKey} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {authorizationDispatchFacts} from '../host-common/authorization-gate.mjs';
import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {openSqliteCredentialJournal} from '../site-node/sqlite-credential-journal.mjs';
import {callHttpsCredentialResource} from '../site-node/https-credential-resource.mjs';
import {retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {createInstalledRowSourceCredentialCustody} from './installed-row-source-credential-custody.mjs';
import {ownCredentialAcquisitionLimits, ownCredentialSecretPresentation} from './installed-row-source-credential-options.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';
import {prepareInstallationMetadataSite} from './installed-row-source-metadata-site.mjs';
import {readBoundedConfigurationText} from './source-profile-json.mjs';

import type {installRowSourceAuthorization} from './installed-row-source-authorization.mjs';

type IssuerPorts = Parameters<typeof createInstalledRowSourceCredentialCustody>[0];
type Issuers = ReturnType<typeof createInstalledRowSourceCredentialCustody>;
type LoaderOptions = Parameters<Issuers['loadRowSourceCredentialCustody']>[0];
type Custody = ReturnType<Issuers['openRowSourceCredentialCustody']>;
type RetainSiteArgs = Parameters<IssuerPorts['retainCredentialOperationSite']>;
type Site = RetainSiteArgs[0];
type SiteIdentity = RetainSiteArgs[2];
type OriginalBind = NonNullable<RetainSiteArgs[4]>;
type RunAuthorization = ReturnType<Custody['sign']>;
type RunAcquisition = ReturnType<Custody['bindRunAcquisition']>;
type RuntimeCore = (moon: unknown) => ReturnType<IssuerPorts['runtimeCore']> &
  ReturnType<Parameters<typeof prepareInstallationMetadataSite>[1]>;
type ResourceOptions = Parameters<typeof callHttpsCredentialResource>[0];
type LocalGate = Awaited<ReturnType<typeof installRowSourceAuthorization>>;
type Decision = Awaited<ReturnType<LocalGate['authorize']>>;
type SiteAuthorization = Pick<LocalGate, 'issued' | 'configurationCid' | 'context'> &
  Parameters<typeof prepareInstallationMetadataSite>[0]['authorization'];
type ConfigurationReader = NonNullable<LoaderOptions['configurationReader']> & {readText?: unknown};
type SiteOptions = Omit<LoaderOptions, 'resolveSecret' | 'now' | 'grantLifetimeMs' | 'configurationReader'> & {
  resolveSecret: NonNullable<LoaderOptions['resolveSecret']>;
  authorization: SiteAuthorization;
  connection: string;
  admitsApprovalTarget?: (binding: unknown, resource: string) => unknown;
  admitsEffectTargetRead?: (binding: unknown, resource: string, operation: string) => unknown;
  installationMetadata?: unknown;
  configurationReader?: ConfigurationReader;
  ownAuthorization?: boolean;
  secretMaterial?: {close(): unknown};
  responseHeaders?: readonly string[];
  now?: () => number;
  grantLifetimeMs?: number;
};
type CheckpointFacts = Readonly<{
  kind?: unknown;
  principalId?: unknown;
  configurationCid?: unknown;
  contextCid?: unknown;
  readTuple?: Decision['tuple'];
  physicalBinding?: unknown;
  physicalBindings?: readonly unknown[];
  assertCurrent?: () => unknown;
  enter?: () => unknown;
}>;
type EffectReadApproval = Readonly<{
  kind: 'effect_target';
  resource: string;
  operation: string;
  binding: unknown;
  wire: string;
  assertCurrent: () => unknown;
  enter: () => unknown;
}>;
type GrantRequest = Readonly<{
  operation: string;
  decision: Decision;
  resource: string;
  runInvocationCid: string;
  dispatchRequestCid: string;
}>;
type RegisteredRunSite = SiteIdentity & Readonly<{
  site: Site;
  credential: Custody['credential'];
  callResource: typeof callHttpsCredentialResource;
  construction: Custody['construction'];
  referenceCurrent: Custody['referenceCurrent'];
  bindRunAcquisition: OriginalBind;
  authorizationPurpose: Custody['authorizationPurpose'];
  readChildCredential: Custody['readChildCredential'];
  bindReadResourceChild: Custody['bindReadResourceChild'];
  readResourceChildCredential: Custody['readResourceChildCredential'];
}>;
type RegisteredMetadataSite = Parameters<Parameters<typeof prepareInstallationMetadataSite>[2]['set']>[1];

export function createInstalledRowSourceCredentialSite({runtimeCore, text, cidPattern}: {
  runtimeCore: RuntimeCore;
  text(value: unknown): value is string;
  cidPattern: RegExp;
}) {
  // Internal operation assembly recognizes the exact credential returned by
  // this existing Site. An equal envelope cannot recover its issuer/binding.
  const operationSites = new WeakMap<object, RegisteredRunSite | RegisteredMetadataSite>();
  function installedRowCredentialOperationSite(credential: unknown) {
    const original = operationSites.get(credential as object);
    if (original === undefined) fail('ForeignInstalledCredentialOperationSite');
    if (!original.referenceCurrent()) fail('RowSourceSiteClosed');
    return original;
  }

  function retainCredentialOperationSite<Original extends Site>(site: Original, custody: RetainSiteArgs[1],
    identity: SiteIdentity, enabled: boolean, originalBind?: OriginalBind): Original {
    if (enabled) {
      const bind = originalBind ?? custody.bindRunAcquisition;
      const bindReceiver = originalBind === undefined ? custody : site;
      const purpose = custody.authorizationPurpose;
      const child = custody.readChildCredential;
      const bindResourceChild = custody.bindReadResourceChild;
      const resourceChild = custody.readResourceChildCredential;
      operationSites.set(site.credential, Object.freeze({
        ...identity, site, credential: site.credential, callResource: site.callResource,
        construction: custody.construction,
        referenceCurrent: custody.referenceCurrent,
        bindRunAcquisition: (authorization: RunAuthorization, current: unknown) =>
          Reflect.apply(bind, bindReceiver, [authorization, current]),
        authorizationPurpose: (authorization: RunAuthorization) => Reflect.apply(purpose, custody, [authorization]),
        readChildCredential: (acquisition: RunAcquisition, authorization: RunAuthorization) => Reflect.apply(child, custody, [acquisition, authorization]),
        bindReadResourceChild: bindResourceChild,
        readResourceChildCredential: resourceChild,
      }));
    }
    return site;
  }


  const {loadRowSourceCredentialCustody, openRowSourceCredentialCustody} =
    createInstalledRowSourceCredentialCustody({
      operationSites, retainCredentialOperationSite, runtimeCore, text, cidPattern,
    });

  // The credential Site of one installed row source: the credential authority
  // key, the credential journal and the secret resolver. Grants are signed
  // only for a read decision the installed gate returned as dispatch for this
  // connection and Resource, or for a Checkpoint approval of exactly this
  // installation's physical target.
  // `responseHeaders` is the installation's declared response header names
  // (its `host-bundle.json`); the Site's `callResource` refuses, before any
  // credential use, an operation that would observe any other header.
  // Optional `admitsEffectTargetRead(binding, resource, operation)` belongs to
  // the same trusted installation. It validates the driver's exact original
  // physical binding and read operation; it cannot replace Checkpoint facts or
  // current/entry authority. The returned Site accepts that original decision
  // with `admitCheckpointEffectTargetRead(decision, binding, operation)`.
  // Each such approval adds a seven-field record, the bounded canonical binding
  // String and original binding/fence aliases in this Site's existing WeakMap.
  // Canonical comparison and signing overlap the original bounded inventory;
  // these controls do not supply a numerical reservation or physical close ACK.
  async function openRowSourceCredentialSite({profile, principalId,
    authorization, connection, connectorRegistration, connectorRevision,
    runtimeBundleCid, commonMoon, resolveSecret, ca, admitsApprovalTarget,
    admitsEffectTargetRead,
    installationMetadata,
    runAcquisitionLimits, configurationReader,
    ownAuthorization = false, secretMaterial,
    responseHeaders = [],
    now = () => Date.now(), grantLifetimeMs = 15 * 60 * 1000,
    openCredentialJournal = openSqliteCredentialJournal}: SiteOptions) {
    const secretPresentation = ownCredentialSecretPresentation(arguments[0]);
    if (!text(profile?.credentialPrivateKeyPath) ||
        !isAbsolute(profile.credentialPrivateKeyPath) ||
        !text(profile.credentialAuthorityId) || !text(profile.credentialKeyId) ||
        !text(profile.journalRoot) || !isAbsolute(profile.journalRoot) ||
        !text(profile.resourceOrigin) || !text(profile.namespaceId) ||
        !text(profile.environment) || !text(profile.siteKey) ||
        !Number.isSafeInteger(profile.siteGeneration) ||
        typeof resolveSecret !== 'function' ||
        (installationMetadata === undefined && typeof admitsApprovalTarget !== 'function')) {
      fail('InvalidRowSourceCredentialSite');
    }
    if (typeof ownAuthorization !== 'boolean' ||
        (secretMaterial !== undefined && !ownAuthorization) ||
        (ownAuthorization && installationMetadata !== undefined) ||
        (admitsEffectTargetRead !== undefined && typeof admitsEffectTargetRead !== 'function') ||
        !Array.isArray(responseHeaders) ||
        responseHeaders.some(name => !text(name))) {
      fail('InvalidRowSourceCredentialSite');
    }
    const authorizationClose = ownAuthorization ?
      Object.getOwnPropertyDescriptor(authorization, 'close')?.value : undefined;
    if (ownAuthorization && typeof authorizationClose !== 'function') {
      fail('InvalidRowSourceAuthorizationInstallation');
    }
    const declaredHeaders = new Set(responseHeaders);
    const selectedAcquisitionLimits = ownCredentialAcquisitionLimits(runAcquisitionLimits);
    // Capture the SAME Source reader before metadata/current work can await.
    // The existing issuer-byte bound remains mandatory on this original read.
    let metadataKeyRead: ((path: string, limits: {maxBytes: number}) => unknown) | undefined;
    if (installationMetadata !== undefined && configurationReader !== undefined) {
      if (configurationReader === null || typeof configurationReader !== 'object' ||
          nodeTypes.isProxy(configurationReader)) fail('InvalidRowSourceCredentialSite');
      const method = Object.getOwnPropertyDescriptor(configurationReader, 'readText');
      if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function') {
        fail('InvalidRowSourceCredentialSite');
      }
      metadataKeyRead = method.value;
    }
    const metadata = installationMetadata === undefined ? undefined
      : await prepareInstallationMetadataSite({installationMetadata, profile,
        principalId, authorization, connection, connectorRegistration,
        connectorRevision, runtimeBundleCid, commonMoon, resolveSecret, ca,
        now, grantLifetimeMs, ...(secretPresentation === undefined ? {} : {secretPresentation})},
        runtimeCore, operationSites, text, cidPattern);
    const custodyOptions = {profile, principalId,
      connectorRegistration, connectorRevision, runtimeBundleCid, commonMoon,
      resolveSecret, ca, now, grantLifetimeMs, openCredentialJournal,
      configurationReader,
      runAcquisitionLimits: selectedAcquisitionLimits,
      ...(secretPresentation === undefined ? {} : {secretPresentation})};
    let custody;
    if (metadata === undefined) custody = await loadRowSourceCredentialCustody(custodyOptions);
    else {
      // This separately typed purpose retains its bounded key read and original
      // initialization/current carrier. It does not adopt legacy Run defaults.
      let privateKey;
      try {
        privateKey = createPrivateKey(await (metadataKeyRead === undefined
          ? readBoundedConfigurationText(metadata.privateKeyPath, {maxBytes: metadata.maxIssuerKeyBytes})
          : Reflect.apply(metadataKeyRead, configurationReader,
            [metadata.privateKeyPath, {maxBytes: metadata.maxIssuerKeyBytes}])) as Parameters<typeof createPrivateKey>[0]);
        if (privateKey.asymmetricKeyType !== 'ed25519') fail('InvalidRowSourceCredentialSite');
        metadata.assertInitializingCurrent();
        custody = openRowSourceCredentialCustody({...custodyOptions, privateKey});
      } catch (error) {
        // The same metadata view already exists even when no Site was returned.
        // Its existing cleanup waits for any original failed child first.
        throw await retainInstalledHostInitializationFailure(error, {sourceProfile: metadata});
      }
    }
    if (metadata !== undefined) {
      const attached = metadata.attach(custody);
      if (attached.failure !== undefined) throw await retainInstalledHostInitializationFailure(
        attached.failure, {sourceProfile: attached.site});
      return attached.site;
    }
    const {credential, ensureOpen, checkGrantRequest, sign} = custody;
    let custodyClosed = false, authorizationClosed = false;
    const custodyClose = custody.close;
    const closeOwnedAuthorization = () => {
      if (!custodyClosed) {Reflect.apply(custodyClose, custody, []); custodyClosed = true;}
      if (!authorizationClosed) {
        if (Reflect.apply(authorizationClose, authorization, []) !== true) {
          fail('RowSourceAuthorizationCleanupPending');
        }
        authorizationClosed = true;
      }
      if (secretMaterial !== undefined) secretMaterial.close();
    };
    const approvals = new WeakMap<object, string | EffectReadApproval>();
    const callResource = (options: ResourceOptions) => {
      for (const operation of (options?.operations as ReadonlyMap<string, {responseHeaders?: readonly string[]} | null> | undefined)?.values?.() ?? []) {
        for (const name of operation?.responseHeaders ?? []) {
          if (!declaredHeaders.has(name)) fail('UndeclaredResponseHeader');
        }
      }
      return callHttpsCredentialResource(options);
    };
    const bindingWire = (value: unknown) => canonicalValueJson(value, {dataKeys: true});
    function synchronous(result: unknown) {
      // Checkpoint currency/entry are synchronous Owner operations. An async
      // callback cannot finish after a credential has already been issued.
      if (result !== undefined) {
        if (typeof (result as {then?: unknown} | null)?.then === 'function') void Promise.resolve(result).catch(() => {});
        fail('RowSourceEffectTargetReadApprovalNotAdmitted');
      }
    }
    function currentEffectRead(approved: EffectReadApproval) {
      ensureOpen();
      if (bindingWire(approved.binding) !== approved.wire) {
        fail('RowSourceEffectTargetReadApprovalNotAdmitted');
      }
      const admitted = admitsEffectTargetRead!(approved.binding, approved.resource, approved.operation);
      if (admitted !== true) {
        if (typeof (admitted as {then?: unknown} | null)?.then === 'function') void Promise.resolve(admitted).catch(() => {});
        fail('RowSourceEffectTargetReadApprovalNotAdmitted');
      }
      synchronous(approved.assertCurrent());
      ensureOpen();
      if (bindingWire(approved.binding) !== approved.wire) {
        fail('RowSourceEffectTargetReadApprovalNotAdmitted');
      }
    }
    return retainCredentialOperationSite(Object.freeze({
      credential, connection, callResource,
      // Borrowed references observe this same Site's lifecycle, not a caller's
      // permission Boolean. False means closing, not physical cleanup ACK.
      referenceCurrent: custody.referenceCurrent,
      // Admit a resumed Checkpoint approval only for this installation's own
      // physical target of the same Resource.
      admitCheckpointReadApproval(decision: Decision) {
        ensureOpen();
        const facts = checkpointApprovalFacts(decision) as CheckpointFacts | undefined;
        if (facts === undefined || facts.kind === 'effect_target' || decision.action !== 'dispatch' ||
            decision.basis !== 'resumed_approval' ||
            decision.boundary !== 'acquisition' ||
            decision.tuple?.connection !== connection ||
            decision.tuple?.operation !== 'read' ||
            facts.principalId !== principalId ||
            facts.readTuple?.connection !== connection ||
            facts.readTuple?.operation !== 'read' ||
            facts.readTuple?.resource !== decision.tuple.resource ||
            !admitsApprovalTarget!(facts.physicalBinding, decision.tuple.resource)) {
          fail('RowSourceReadApprovalNotAdmitted');
        }
        approvals.set(decision, decision.tuple.resource);
        return decision;
      },
      // The existing Checkpoint continuation supplies this exact original
      // decision and its live entry/current fences. The installed driver checks
      // its own member/Site binding and read operation; matching DATA alone is
      // never admission. Keep the original decision, not a replacement grant.
      admitCheckpointEffectTargetRead(decision: Decision, physicalBinding: unknown, operation: string) {
        ensureOpen();
        const facts = checkpointApprovalFacts(decision) as CheckpointFacts | undefined;
        if (typeof admitsEffectTargetRead !== 'function' || !text(operation) ||
            facts?.kind !== 'effect_target' || decision.action !== 'dispatch' ||
            decision.boundary !== 'acquisition' || facts.principalId !== principalId ||
            !cidPattern.test(authorization.configurationCid ?? '') ||
            !cidPattern.test(authorization.context?.contextCid ?? '') ||
            facts.configurationCid !== authorization.configurationCid ||
            facts.contextCid !== authorization.context.contextCid ||
            decision.tuple?.connection !== connection || decision.tuple?.operation !== 'read' ||
            facts.readTuple?.connection !== connection || facts.readTuple?.operation !== 'read' ||
            facts.readTuple?.resource !== decision.tuple.resource ||
            typeof facts.assertCurrent !== 'function' || typeof facts.enter !== 'function' ||
            !Array.isArray(facts.physicalBindings)) {
          fail('RowSourceEffectTargetReadApprovalNotAdmitted');
        }
        const wire = bindingWire(physicalBinding);
        if (!facts.physicalBindings.some(binding => bindingWire(binding) === wire)) {
          fail('RowSourceEffectTargetReadApprovalNotAdmitted');
        }
        const approved: EffectReadApproval = Object.freeze({kind: 'effect_target', resource: decision.tuple.resource,
          operation, binding: physicalBinding, wire,
          assertCurrent: facts.assertCurrent, enter: facts.enter});
        currentEffectRead(approved);
        approvals.set(decision, approved);
        return decision;
      },
      issueReadGrant({operation, decision, resource, runInvocationCid,
        dispatchRequestCid, maxUses}: GrantRequest & {maxUses: number}) {
        ensureOpen();
        const approved = approvals.get(decision);
        if (approved !== undefined) {
          if (typeof approved === 'string') {
            if (approved !== resource) fail('RowSourceGrantNotAuthorized');
          } else {
            if (approved.resource !== resource || approved.operation !== operation) {
              fail('RowSourceGrantNotAuthorized');
            }
            // Validate before consuming the original one-shot entry. A malformed
            // request cannot spend it; journal/signing failures after entry stay
            // with the existing acquisition/capture cleanup and never reset it.
            checkGrantRequest(runInvocationCid, dispatchRequestCid, maxUses);
            currentEffectRead(approved);
            synchronous(approved.enter());
            currentEffectRead(approved);
          }
        } else if (!authorization.issued(decision) ||
            decision.action !== 'dispatch' ||
            decision.boundary !== 'acquisition' ||
            decision.contextCid !== authorization.context.contextCid ||
            decision.tuple?.connection !== connection ||
            decision.tuple?.resource !== resource ||
            decision.tuple?.operation !== 'read') {
          fail('RowSourceGrantNotAuthorized');
        }
        return sign({operation, runInvocationCid, dispatchRequestCid, maxUses,
          issuerPurpose: Object.freeze({kind: typeof approved === 'object' ? 'target-read' : 'read',
            resource, decision,
            ...(typeof approved === 'object' ? {physicalBinding: approved.binding} : {})})});
      },
      // One write grant for an Effect commit decision on `resource`, for the
      // sealed Set `subjectCid`. A commit the Host's own Checkpoint commit gate
      // decided counts only when that gate decided it for this principal under
      // this exact account configuration; the gate owns its approval's
      // currency.
      issueEffectGrant({operation, decision, resource, runInvocationCid,
        dispatchRequestCid, subjectCid}: GrantRequest & {subjectCid: string}) {
        ensureOpen();
        const facts = authorizationDispatchFacts(decision);
        const hostCommit = facts !== undefined &&
          facts.principal === principalId &&
          facts.configurationCid === authorization.configurationCid;
        if (!text(operation) || !cidPattern.test(subjectCid ?? '') ||
            !(authorization.issued(decision) || hostCommit) ||
            decision.action !== 'dispatch' ||
            decision.boundary !== 'effect_commit' ||
            (!hostCommit &&
              decision.contextCid !== authorization.context.contextCid) ||
            decision.tuple?.connection !== connection ||
            decision.tuple?.resource !== resource ||
            decision.tuple?.operation !== 'effect' ||
            decision.subjectCid !== subjectCid) {
          fail('RowSourceGrantNotAuthorized');
        }
        return sign({operation, runInvocationCid, dispatchRequestCid,
          maxUses: 1, issuerPurpose: Object.freeze({kind: 'effect', resource, decision})});
      },
      close: ownAuthorization ? closeOwnedAuthorization : custody.close,
    }), custody, {connection, principalId, connectorRegistration,
      connectorRevision, runtimeBundleCid}, selectedAcquisitionLimits !== undefined);
  }

  return {installedRowCredentialOperationSite, loadRowSourceCredentialCustody,
    openRowSourceCredentialCustody, openRowSourceCredentialSite};
}
