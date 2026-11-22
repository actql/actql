import {createPrivateKey, createPublicKey} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {types as nodeTypes} from 'node:util';
import {invocationBindingsMatch} from '../host-common/owned-invocation-context.mjs';
import {openSqliteCredentialJournal} from '../site-node/sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from '../site-node/remote-credential-signature.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding, retainHttpsCredentialBindingReadChild}
  from '../site-node/https-credential-resource.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';
import {ownCredentialAcquisitionLimits, ownCredentialSecretPresentation}
  from './installed-row-source-credential-options.mjs';

import type {KeyObject} from 'node:crypto';
import type {RequestOptions} from 'node:https';
import type {remoteCredentialControl} from '../host-common/remote-credential-control.mjs';
import type {createInstallationPreparationMetadata} from '../host-common/installation-preparation-metadata.mjs';
import type {callHttpsCredentialResource} from '../site-node/https-credential-resource.mjs';

type RunControl = ReturnType<typeof remoteCredentialControl>;
type RunScope = Parameters<RunControl['prepare']>[0];
type MutableRunScope = {-readonly [Field in keyof RunScope]: RunScope[Field]};
type ScopeFields = Omit<RunScope, 'operation' | 'runInvocationCid' | 'taskAttempt' |
  'dispatchRequestCid' | 'expiresUnixMilliseconds' | 'maxUses'>;
type MetadataControl = ReturnType<ReturnType<typeof createInstallationPreparationMetadata>['forSubject']>;
type Journal = ReturnType<typeof openSqliteCredentialJournal>;
type ResolveSecret = Parameters<typeof openHttpsCredentialBinding>[0]['resolveSecret'];
type ResourceCall = typeof callHttpsCredentialResource;
type OriginalRead = {readOriginalText?: unknown; readOriginalBytes?: unknown};
type CredentialProfile = {
  journalRoot: string;
  credentialAuthorityId: string;
  credentialKeyId: string;
  credentialPrivateKeyPath: string;
  namespaceId: string;
  environment: string;
  siteKey: string;
  siteGeneration: number;
  resourceOrigin: string;
};
type CustodyOptions = {
  profile: CredentialProfile;
  principalId: string;
  connectorRegistration: string;
  connectorRevision: string;
  runtimeBundleCid: string;
  commonMoon: unknown;
  privateKey: KeyObject;
  resolveSecret: ResolveSecret;
  ca?: RequestOptions['ca'];
  now: () => number;
  grantLifetimeMs: number;
  openCredentialJournal: typeof openSqliteCredentialJournal;
  credentialFacts?: Readonly<Record<string, unknown>>;
  runAcquisitionLimits?: unknown;
  secretPresentation?: unknown;
  closedCode?: string;
  grantCode?: string;
};
type LoadCustodyOptions = Omit<CustodyOptions, 'privateKey' | 'openCredentialJournal' | 'resolveSecret'> & {
  openCredentialJournal?: typeof openSqliteCredentialJournal;
  configurationReader?: OriginalRead;
  resolveSecret?: ResolveSecret;
};
type ReadCustodyOptions = {
  caPath?: string;
  prepareResolver?: () => unknown;
  invalidCode?: string;
};
type Credential = Readonly<{
  control: RunControl;
  journal: Journal;
  resolveSecret: ResolveSecret;
  ca: RequestOptions['ca'];
  now: () => number;
  binding?: object;
  currentBeforeSend?: () => unknown;
  bindingBorrow?: object;
}>;
type OriginalAuthorization = Readonly<{grant: unknown; scope: RunScope}>;
type IssuerPurpose = Readonly<{kind: string; resource?: unknown; decision?: unknown}>;
type GrantRequest = {
  operation: string;
  runInvocationCid: string;
  taskAttempt?: number;
  dispatchRequestCid: string;
  maxUses: number;
  issuerPurpose?: IssuerPurpose;
};
type MetadataRequest = {
  control: MetadataControl;
  scope: object;
  expiresUnixMilliseconds: bigint;
  maxUses: number;
};
type Current = Readonly<{assertCurrent(): void; observeCurrent(): Promise<void>}>;
type PhysicalBorrow = ReturnType<typeof retainHttpsCredentialBindingReadChild>;
type Acquisition = Readonly<{
  authorization: OriginalAuthorization;
  credential: Credential;
  close(): 'closed' | 'pending';
  retire?(): boolean;
}>;
type BindingRecord = {
  binding: object | undefined;
  closed: boolean;
  closing: boolean;
  borrow: PhysicalBorrow | undefined;
  current: Current;
  resourceParent?: Acquisition;
  parent?: undefined;
};
type ReadChildRecord = {
  parent: BindingRecord;
  borrow: PhysicalBorrow;
  current: Current;
  binding?: undefined;
  closed?: undefined;
  closing?: undefined;
  resourceParent?: undefined;
};
type IssuedAuthorization = {
  state: 'unused' | 'opening' | 'bound' | 'failed';
  issuerPurpose?: IssuerPurpose;
  acquisition?: BindingRecord;
};
type OperationSite = Readonly<{
  site: object;
  credential: object;
  referenceCurrent(): boolean;
  callResource: ResourceCall;
}>;
type SiteIdentity = Readonly<{
  connection: string;
  principalId: string;
  connectorRegistration: string;
  connectorRevision: string;
  runtimeBundleCid: string;
}>;
type BindingSite = Readonly<{credential: Credential; connection: string; callResource: ResourceCall}>;
type BindInstalledAcquisition = (authorization: OriginalAuthorization, callbacks: unknown) => Acquisition;
type IssuerSitePorts = {
  operationSites: WeakMap<object, OperationSite>;
  retainCredentialOperationSite(site: BindingSite, custody: IssuerCustody, identity: SiteIdentity,
    enabled: boolean, originalBind?: BindInstalledAcquisition): BindingSite;
  runtimeCore(original: unknown): {remoteCredentialControl: RunControl};
  text(value: unknown): value is string;
  cidPattern: RegExp;
};
type IssuerCustody = Readonly<{
  construction?: Readonly<{
    scope: ScopeFields;
    limits: NonNullable<ReturnType<typeof ownCredentialAcquisitionLimits>>;
    issuer: Readonly<{authority: string; keyId: string}>;
  }>;
  referenceCurrent(): boolean;
  bindRunAcquisition: BindInstalledAcquisition;
  authorizationPurpose(authorization: OriginalAuthorization): IssuerPurpose;
  readChildCredential(acquisition: Acquisition, authorization: OriginalAuthorization): Credential;
  bindReadResourceChild(parent: Acquisition, authorization: OriginalAuthorization, callbacks: unknown): Acquisition;
  readResourceChildCredential(parent: Acquisition, acquisition: Acquisition, authorization: OriginalAuthorization): Credential;
}>;

export function createInstalledRowSourceCredentialCustody({
  operationSites, retainCredentialOperationSite, runtimeCore, text, cidPattern,
}: IssuerSitePorts) {
  // Load the selected installed issuer into the same credential custody. A
  // compatibility installer keeps its own profile and refusal names; neither
  // the key nor a second journal/signing implementation leaves this Owner.
  async function loadRowSourceCredentialCustody({
    openCredentialJournal = openSqliteCredentialJournal, ...options}: LoadCustodyOptions, {
    caPath, prepareResolver, invalidCode = 'InvalidRowSourceCredentialSite'}: ReadCustodyOptions = {}) {
    let privateKey;
    let ca = options.ca;
    try {
      const reader = options.configurationReader;
      let read: ((path: string) => unknown) | undefined;
      if (reader !== undefined) {
        if (nodeTypes.isProxy(reader)) fail(invalidCode);
        const field = Object.getOwnPropertyDescriptor(reader, 'readOriginalText');
        if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') fail(invalidCode);
        read = field.value;
      }
      privateKey = createPrivateKey(await (reader === undefined
        ? readFile(options.profile.credentialPrivateKeyPath, 'utf8')
        : Reflect.apply(read!, reader, [options.profile.credentialPrivateKeyPath])) as Parameters<typeof createPrivateKey>[0]);
      if (caPath !== undefined) {
        if (reader === undefined) ca = await readFile(caPath);
        else {
          const bytes = Object.getOwnPropertyDescriptor(reader, 'readOriginalBytes');
          if (!bytes || !Object.hasOwn(bytes, 'value') || typeof bytes.value !== 'function') fail(invalidCode);
          ca = await Reflect.apply(bytes.value, reader, [caPath]);
        }
      }
    } catch (cause) {
      const failure = Object.assign(new Error(invalidCode, {cause}), {code: invalidCode});
      // Preserve the existing same-FD cleanup Owner through the old Site error
      // wrapper. A failed key read must not become an unowned Source abort.
      const cleanup = Object.getOwnPropertyDescriptor(Object(cause), 'cleanupHandle');
      if (cleanup && Object.hasOwn(cleanup, 'value')) {
        Object.defineProperty(failure, 'cleanupHandle', {value: cleanup.value});
      }
      throw failure;
    }
    if (privateKey.asymmetricKeyType !== 'ed25519') fail(invalidCode);
    // The existing installer can construct its default resolver only after the
    // original key/CA admission. It receives no private key or provider secret.
    const resolveSecret = prepareResolver === undefined
      ? options.resolveSecret : prepareResolver();
    if (typeof resolveSecret !== 'function') {
      if (typeof (resolveSecret as {then?: unknown} | null | undefined)?.then === 'function') {
        void Promise.resolve(resolveSecret).catch(() => {});
      }
      fail(invalidCode);
    }
    return openRowSourceCredentialCustody({...options,
      privateKey, ca, resolveSecret: resolveSecret as ResolveSecret, openCredentialJournal});
  }

  function openRowSourceCredentialCustody({profile, principalId,
    connectorRegistration, connectorRevision, runtimeBundleCid, commonMoon,
    privateKey, resolveSecret, ca, now, grantLifetimeMs,
    openCredentialJournal, credentialFacts, runAcquisitionLimits,
    closedCode = 'RowSourceSiteClosed',
    grantCode = 'InvalidRowSourceGrantRequest'}: CustodyOptions) {
    const secretPresentation = ownCredentialSecretPresentation(arguments[0]);
    const acquisitionLimits = ownCredentialAcquisitionLimits(runAcquisitionLimits);
    if (acquisitionLimits !== undefined) {
      if (profile === null || typeof profile !== 'object' || nodeTypes.isProxy(profile) ||
          !Object.isFrozen(profile) || Object.values(Object.getOwnPropertyDescriptors(profile))
            .some(field => !Object.hasOwn(field, 'value'))) fail('InvalidRowSourceCredentialAcquisitionProfile');
    }
    const control = runtimeCore(commonMoon).remoteCredentialControl;
    const journalRoot = profile.journalRoot;
    const credentialAuthorities = new Map([[profile.credentialAuthorityId,
      new Map([[profile.credentialKeyId, createPublicKey(privateKey)]])]]);
    const [authority, originalKeys] = credentialAuthorities.entries().next().value!;
    const metadataIssuer = Object.freeze({authority, keyId: originalKeys.keys().next().value!});
    // Define the immutable managed scope once in the SAME issuer that consumes
    // it. These original strings/limits are constructor DATA, not a grant,
    // current observation, copied credential or another policy selection.
    const originalScopeFields = (): ScopeFields => ({
      issuerAuthority: profile.credentialAuthorityId, principal: principalId,
      namespaceId: profile.namespaceId, environment: profile.environment,
      siteKey: profile.siteKey, siteGeneration: profile.siteGeneration,
      runtimeBundleCid, connectorRegistration, connectorRevision,
      resourceOrigin: profile.resourceOrigin,
    });
    const scopeDefinition = acquisitionLimits === undefined ? undefined
      : Object.freeze(originalScopeFields());
    const construction = scopeDefinition === undefined ? undefined
      : Object.freeze({scope: scopeDefinition, limits: acquisitionLimits!, issuer: metadataIssuer});
    const journal = openCredentialJournal(journalRoot, {credentialAuthorities});
    let closing = false;
    let released = false;
    const runBindings = acquisitionLimits === undefined ? undefined : new Set<BindingRecord>();
    let runBindingAttempts = 0;
    const runAcquisitions = new WeakMap<object, BindingRecord | ReadChildRecord>();
    const issuedRunAuthorizations = acquisitionLimits === undefined ? undefined : new WeakMap<object, IssuedAuthorization>();
    let runJournalClose: (() => unknown) | undefined;
    let runJournalFailure: unknown, runJournalCloseObservation: unknown;
    if (runBindings !== undefined) {
      // Capture before returning a borrow. A substituted method cannot retire
      // this original Journal, and capture failure remains with this custody.
      try {
        if (nodeTypes.isProxy(journal) || !Object.isFrozen(journal) ||
            ['acceptGrant', 'claim', 'authorize', 'finish', 'checkGrant', 'inspect', 'recover', 'close']
              .some(name => {
                const method = Object.getOwnPropertyDescriptor(journal, name);
                return !method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function';
              })) fail('InvalidRowSourceCredentialAcquisitionJournal');
        runJournalClose = Object.getOwnPropertyDescriptor(journal, 'close')!.value;
      } catch (cause) { runJournalFailure = cause; }
    }
    // The metadata alternative uses this same original issuer/key/Journal.
    // Legacy Run signing below deliberately retains its existing profile rules.
    const credential: Credential = Object.freeze({...credentialFacts,
      control, journal, resolveSecret, ca, now});
    const ensureOpen = () => {
      if (closing) fail(closedCode);
    };
    function checkGrantRequest(runInvocationCid: string, dispatchRequestCid: string, maxUses: number,
      taskAttempt = 1) {
      if (!cidPattern.test(runInvocationCid ?? '') ||
          !cidPattern.test(dispatchRequestCid ?? '') ||
          !Number.isSafeInteger(taskAttempt) || taskAttempt < 1 ||
          !Number.isSafeInteger(maxUses) || maxUses < 1 || maxUses > 10_000) {
        fail(grantCode);
      }
    }
    function sign({operation, runInvocationCid, taskAttempt = 1,
      dispatchRequestCid, maxUses, issuerPurpose}: GrantRequest) {
      ensureOpen();
      checkGrantRequest(runInvocationCid, dispatchRequestCid, maxUses, taskAttempt);
      // The legacy branch fills its original one scope record directly; it
      // does not allocate a temporary field record only to spread it again.
      const scope = (scopeDefinition === undefined ? originalScopeFields() : {...scopeDefinition}) as MutableRunScope;
      scope.operation = operation;
      scope.runInvocationCid = runInvocationCid;
      scope.taskAttempt = taskAttempt;
      scope.dispatchRequestCid = dispatchRequestCid;
      scope.expiresUnixMilliseconds = BigInt(now() + grantLifetimeMs);
      scope.maxUses = maxUses;
      Object.freeze(scope);
      // Re-admitting this signed scope never refills its durable use inventory.
      const grant = control.prepare(scope);
      journal.acceptGrant(signRemoteCredentialGrant(grant, control, {
        keyId: construction === undefined ? profile.credentialKeyId : construction.issuer.keyId, privateKey}), control);
      const authorization = Object.freeze({grant, scope});
      issuedRunAuthorizations?.set(authorization, {state: 'unused', issuerPurpose});
      return authorization;
    }
    function authorizationPurpose(authorization: OriginalAuthorization) {
      ensureOpen();
      const original = issuedRunAuthorizations?.get(authorization)?.issuerPurpose;
      if (original === undefined) fail('RowSourceAuthorizationPurposeUnavailable');
      // This is the original issuance branch, not a new Allow or a substitute
      // for current Account/Checkpoint, Journal use, claim or Run admission.
      return original;
    }
    function closeRunBindings() {
      let pending = false;
      for (const original of runBindings ?? []) {
        if (!original.closed && original.binding === undefined) {
          pending = true;
          continue;
        }
        if (!original.closed) {
          original.closing = true;
          original.closed = closeHttpsCredentialBinding(original.binding!) === 'closed';
        }
        if (!original.closed) pending = true;
        else {original.binding = undefined; runBindings!.delete(original);}
      }
      if (pending) fail('RowSourceCredentialAcquisitionCleanupPending');
    }
    function close() {
      closing = true;
      if (runBindings === undefined) journal.close();
      else {
        if (released) return;
        closeRunBindings();
        if (runJournalFailure !== undefined) throw runJournalFailure;
        const acknowledged = Reflect.apply(runJournalClose!, journal, []);
        if (typeof acknowledged !== 'boolean') {
          runJournalCloseObservation = acknowledged;
          runJournalFailure = Object.assign(new Error('RowSourceCredentialJournalCleanupUnconfirmed'),
            {code: 'RowSourceCredentialJournalCleanupUnconfirmed'});
          const failure = runJournalFailure as Error;
          try {
            if (typeof (runJournalCloseObservation as {then?: unknown} | null | undefined)?.then === 'function') {
              void Promise.resolve(runJournalCloseObservation).catch(cause => { failure.cause = cause; });
            }
          } catch (cause) { failure.cause = cause; }
          throw failure;
        }
      }
      released = true;
    }
    function openRunAcquisition(request: unknown, callbacks: unknown) {
      ensureOpen();
      if (acquisitionLimits === undefined) fail('RowSourceCredentialAcquisitionUnavailable');
      if (runJournalFailure !== undefined) throw runJournalFailure;
      if (runBindingAttempts >= acquisitionLimits.maxBindings) fail('RowSourceCredentialAcquisitionLimit');
      if (callbacks === null || typeof callbacks !== 'object' || nodeTypes.isProxy(callbacks)) {
        fail('InvalidRowSourceCredentialAcquisitionCurrent');
      }
      if (request === null || typeof request !== 'object' || nodeTypes.isProxy(request)) {
        fail('InvalidRowSourceCredentialAcquisitionRequest');
      }
      const fields = Object.getOwnPropertyDescriptors(request);
      const names = ['operation', 'runInvocationCid', 'taskAttempt', 'dispatchRequestCid', 'maxUses'];
      if (Reflect.ownKeys(fields).some(name => !names.includes(name as string)) ||
          names.some(name => name !== 'taskAttempt' && !fields[name]) ||
          Object.values(fields).some(field => !Object.hasOwn(field, 'value'))) {
        fail('InvalidRowSourceCredentialAcquisitionRequest');
      }
      const originalRequest = Object.freeze(Object.fromEntries(names.map(name =>
        [name, name === 'taskAttempt' && !Object.hasOwn(fields, name) ? 1 : fields[name].value]))) as GrantRequest;
      const {assertCurrent, observeCurrent} = captureRunCurrent(callbacks);
      assertCurrent();
      // Preserve the existing issue-and-bind caller. A Site that has already
      // authorized and issued its grant uses bindRunAcquisition instead.
      const authorization = sign(originalRequest);
      return retainRunBinding(authorization, {assertCurrent, observeCurrent});
    }
    function captureRunCurrent(callbacks: unknown): Current {
      if (callbacks === null || typeof callbacks !== 'object' || nodeTypes.isProxy(callbacks)) {
        fail('InvalidRowSourceCredentialAcquisitionCurrent');
      }
      const methods = Object.getOwnPropertyDescriptors(callbacks);
      if (Reflect.ownKeys(methods).length !== 2 || ['assertCurrent', 'observeCurrent'].some(name =>
        !methods[name] || !Object.hasOwn(methods[name], 'value') || typeof methods[name].value !== 'function')) {
        fail('InvalidRowSourceCredentialAcquisitionCurrent');
      }
      const originalAssert = methods.assertCurrent.value;
      const originalObserve = methods.observeCurrent.value;
      const assertCurrent = () => {
        ensureOpen();
        const result = Reflect.apply(originalAssert, undefined, []);
        if (result !== undefined) {
          if (typeof (result as {then?: unknown} | null)?.then === 'function') void Promise.resolve(result).catch(() => {});
          fail('InvalidRemoteCredentialCurrentFence');
        }
        ensureOpen();
      };
      const observeCurrent = async () => {
        assertCurrent();
        await Reflect.apply(originalObserve, undefined, []);
        assertCurrent();
      };
      return {assertCurrent, observeCurrent};
    }
    function retainRunBinding(authorization: OriginalAuthorization, current: Current, resourceParent?: Acquisition): Acquisition {
      const {assertCurrent, observeCurrent} = current;
      ensureOpen();
      if (acquisitionLimits === undefined) fail('RowSourceCredentialAcquisitionUnavailable');
      if (runJournalFailure !== undefined) throw runJournalFailure;
      const issued = issuedRunAuthorizations!.get(authorization);
      if (issued === undefined) fail('ForeignRowSourceCredentialAcquisitionAuthorization');
      if (issued.state !== 'unused') fail('RowSourceCredentialAcquisitionAuthorizationConsumed');
      if (runBindingAttempts >= acquisitionLimits.maxBindings) fail('RowSourceCredentialAcquisitionLimit');
      // Retain the opening child before invoking a current callback. Reentrant
      // close cannot ACK the Journal while this original binding is opening.
      const original: BindingRecord = {binding: undefined, closed: false, closing: false, borrow: undefined, current};
      if (resourceParent !== undefined) original.resourceParent = resourceParent;
      issued.state = 'opening';
      runBindingAttempts++;
      runBindings!.add(original);
      try {
        assertCurrent();
        original.binding = openHttpsCredentialBinding({scope: authorization.scope,
          control, journal, resolveSecret, maxSecretBytes: acquisitionLimits.maxSecretBytes,
          assertCurrent, ...(secretPresentation === undefined ? {} : {secretPresentation}),
          ...(resourceParent === undefined ? {} : {originalSecretBinding: resourceParent.credential.binding})});
        issued.state = 'bound';issued.acquisition = original;
      } catch (cause) {
        // No physical binding was returned. Keep the original grant with its
        // Journal and refuse another binding attempt under this authorization.
        original.closed = true;
        runBindings!.delete(original);
        issued.state = 'failed';
        throw cause;
      }
      const boundCredential = Object.freeze({...credential, binding: original.binding,
        currentBeforeSend: observeCurrent});
      const acquisition: Acquisition = Object.freeze({authorization, credential: boundCredential,
        close() {
          original.closing = true;
          if (!original.closed) original.closed = closeHttpsCredentialBinding(original.binding!) === 'closed';
          if (original.closed) {original.binding = undefined; runBindings!.delete(original);}
          return original.closed ? 'closed' : 'pending';
        }});
      runAcquisitions.set(acquisition, original);
      const originalSite = operationSites.get(credential);
      if (originalSite !== undefined && issued.issuerPurpose?.kind === 'read') {
        // Recognize only this SAME already-open Run credential. No copied
        // envelope, scope/CID or fresh binding can construct this parent view.
        operationSites.set(boundCredential, Object.freeze({...originalSite, credential: boundCredential,
          referenceCurrent() {
            return !original.closing && !original.closed && original.binding !== undefined &&
              originalSite.referenceCurrent() && (original.borrow === undefined || original.borrow.available());
          },
          bindRunAcquisition(childAuthorization: OriginalAuthorization, callbacks: unknown) {
            const childCurrent = captureRunCurrent(callbacks);
            childCurrent.assertCurrent();assertCurrent();
            // Existing issuer/purpose/resource/invocation checks retain their
            // original grant. Sharing the binding does not authorize a use.
            readChildCredential(acquisition, childAuthorization);
            const physical = retainHttpsCredentialBindingReadChild(original.binding!);
            original.borrow = physical;
            const childCredential = Object.freeze({...boundCredential, bindingBorrow: physical});
            let retired = false;
            const childAcquisition: Acquisition = Object.freeze({authorization: childAuthorization, credential: childCredential,
              close() {
                if (this !== childAcquisition) fail('ForeignRowSourceCredentialReadChild');
                return physical.close();
              },
              retire() {
                if (this !== childAcquisition) fail('ForeignRowSourceCredentialReadChild');
                if (retired) return true;
                if (!physical.retire()) return false;
                retired = true;if (original.borrow === physical) original.borrow = undefined;
                return true;
              }});
            runAcquisitions.set(childAcquisition, {parent: original, borrow: physical, current: childCurrent});
            return childAcquisition;
          },
          callResource(input: Parameters<ResourceCall>[0]) {
            const beforeSend = input.currentBeforeSend;
            if (typeof beforeSend !== 'function') fail('InvalidRemoteCredentialCurrentFence');
            return Reflect.apply(originalSite.callResource, originalSite.site, [{...input,
              currentBeforeSend: async () => {
                // Both original parent and child current duties stay with the
                // Host. Neither is reconstructed from a credential envelope.
                await observeCurrent();await Reflect.apply(beforeSend, undefined, []);
              }}]);
          },
        }));
      }
      return acquisition;
    }
    function readChildCredential(acquisition: Acquisition, authorization: OriginalAuthorization) {
      ensureOpen();
      const retained = runAcquisitions.get(acquisition);
      const parent = (retained?.parent ?? retained) as BindingRecord | undefined;
      const issued = issuedRunAuthorizations?.get(authorization);
      if (retained?.borrow !== undefined && !retained.borrow.available()) fail('ForeignRowSourceCredentialReadChild');
      if (parent === undefined || parent.closing || parent.closed || parent.binding === undefined || issued === undefined ||
          issued.state !== 'unused' && (issued.state !== 'bound' || issued.acquisition !== parent)) {
        fail('ForeignRowSourceCredentialReadChild');
      }
      const purpose = issued.issuerPurpose;
      const originalPurpose = issuedRunAuthorizations!.get(acquisition.authorization)?.issuerPurpose;
      if (purpose?.kind !== 'read' || originalPurpose?.kind !== 'read' ||
          purpose.resource !== originalPurpose.resource || purpose.decision === undefined || originalPurpose.decision === undefined ||
          !invocationBindingsMatch(authorization.scope, acquisition.authorization.scope)) {
        fail('ForeignRowSourceCredentialReadChild');
      }
      // This exact Site issuer has already authorized the child's own original
      // read decision. A current observation can yield a fresh decision object;
      // it need not reuse the parent's earlier decision to share this binding.
      // Associate it with
      // the parent's existing binding; do not sign, open, or own another one.
      issued.state = 'bound';issued.acquisition = parent;
      return acquisition.credential;
    }
    // A separately authorized Resource gets its own real binding, never an
    // exemption from readChildCredential's strict same-Resource sharing rule.
    // Its SAME parent Credential owns the original static-secret pin; separate
    // grants, current callbacks and child retirement remain mandatory.
    function readResourceParent(acquisition: Acquisition) {
      ensureOpen();
      const retained = runAcquisitions.get(acquisition);
      if (retained === undefined) fail('ForeignRowSourceCredentialResourceChild');
      const original = (retained.parent ?? retained) as BindingRecord;
      const issued = issuedRunAuthorizations?.get(acquisition.authorization);
      if (original === undefined || original.resourceParent !== undefined || original.closing || original.closed || original.binding === undefined ||
          retained.borrow !== undefined && !retained.borrow.available() ||
          issued?.state !== 'bound' || issued.acquisition !== original ||
          issued.issuerPurpose?.kind !== 'read' || issued.issuerPurpose.decision === undefined ||
          !text(issued.issuerPurpose.resource)) fail('ForeignRowSourceCredentialResourceChild');
      return {retained, original, purpose: issued.issuerPurpose};
    }
    function bindReadResourceChild(parent: Acquisition, authorization: OriginalAuthorization, callbacks: unknown) {
      const owner = readResourceParent(parent);
      const issued = issuedRunAuthorizations?.get(authorization);
      if (issued === undefined || issued.state !== 'unused' || issued.issuerPurpose?.kind !== 'read' ||
          issued.issuerPurpose.decision === undefined || !text(issued.issuerPurpose.resource) ||
          issued.issuerPurpose.resource === owner.purpose.resource ||
          !invocationBindingsMatch(authorization.scope, parent.authorization.scope)) {
        fail('ForeignRowSourceCredentialResourceChild');
      }
      const childCurrent = captureRunCurrent(callbacks);
      const parentCurrent = owner.original.current;
      const borrowedCurrent = owner.retained === owner.original ? undefined : owner.retained.current;
      const assertParent = () => {
        const selected = readResourceParent(parent);
        if (selected.retained !== owner.retained || selected.original !== owner.original) {
          fail('ForeignRowSourceCredentialResourceChild');
        }
      };
      const assertCurrent = () => {
        assertParent();parentCurrent.assertCurrent();assertParent();
        if (borrowedCurrent !== undefined) {borrowedCurrent.assertCurrent();assertParent();}
        childCurrent.assertCurrent();assertParent();
      };
      const observeCurrent = async () => {
        assertCurrent();await parentCurrent.observeCurrent();assertCurrent();
        if (borrowedCurrent !== undefined) {await borrowedCurrent.observeCurrent();assertCurrent();}
        await childCurrent.observeCurrent();assertCurrent();
      };
      // retainRunBinding spends this original authorization and retains the
      // opening duty before invoking either parent's or child's current fence.
      // Its failure path remains consumed; no replacement child is returned.
      return retainRunBinding(authorization, {assertCurrent, observeCurrent}, parent);
    }
    function readResourceChildCredential(parent: Acquisition, acquisition: Acquisition, authorization: OriginalAuthorization) {
      const owner = readResourceParent(parent);
      const child = runAcquisitions.get(acquisition);
      const issued = issuedRunAuthorizations?.get(authorization);
      if (child === undefined || child.resourceParent !== parent || child.closing || child.closed ||
          child.binding === undefined || acquisition.authorization !== authorization ||
          issued?.state !== 'bound' || issued.acquisition !== child ||
          issued.issuerPurpose?.kind !== 'read' || issued.issuerPurpose.decision === undefined ||
          issued.issuerPurpose.resource === owner.purpose.resource ||
          !invocationBindingsMatch(authorization.scope, parent.authorization.scope)) {
        fail('ForeignRowSourceCredentialResourceChild');
      }
      child.current.assertCurrent();
      readResourceParent(parent);
      if (child.closing || child.closed || child.binding === undefined) fail('ForeignRowSourceCredentialResourceChild');
      return acquisition.credential;
    }
    function bindRunAcquisition(authorization: OriginalAuthorization, callbacks: unknown) {
      ensureOpen();
      if (acquisitionLimits === undefined) fail('RowSourceCredentialAcquisitionUnavailable');
      // Membership is the exact authorization returned by this existing issuer,
      // not a re-admitted grant, equal CID, reconstructed scope or caller copy.
      if (!issuedRunAuthorizations!.has(authorization)) {
        fail('ForeignRowSourceCredentialAcquisitionAuthorization');
      }
      return retainRunBinding(authorization, captureRunCurrent(callbacks));
    }
    function signInstallationMetadata({control: metadataControl, scope,
      expiresUnixMilliseconds, maxUses}: MetadataRequest) {
      ensureOpen();
      if (metadataControl?.kind !== 'installation-metadata') fail(grantCode);
      metadataControl.scopeFields(scope);
      const prepared = metadataControl.prepare({issuerAuthority: metadataIssuer.authority,
        scope, expiresUnixMilliseconds, maxUses});
      const grant = journal.acceptGrant(signRemoteCredentialGrant(prepared,
        metadataControl, {keyId: metadataIssuer.keyId, privateKey}), metadataControl);
      return Object.freeze({grant, scope});
    }
    function installationMetadataJournal() {
      // New-purpose admission captures the original close/receiver before any
      // method substitution. A missing/accessor method keeps this same custody
      // pending; it must not escape before the Site can return its cleanup duty.
      let originalClose: (() => unknown) | undefined, failure: unknown;
      try {
        if (nodeTypes.isProxy(journal)) fail('InvalidInstallationMetadataJournal');
        const descriptor = Object.getOwnPropertyDescriptor(journal, 'close');
        if (!descriptor || !Object.hasOwn(descriptor, 'value') ||
            typeof descriptor.value !== 'function') fail('InstallationMetadataJournalCleanupUnavailable');
        originalClose = descriptor.value;
        if (!Object.isFrozen(journal) || ['acceptGrant', 'claim', 'authorize',
          'finish', 'checkGrant', 'inspect', 'recover'].some(name => {
          const method = Object.getOwnPropertyDescriptor(journal, name);
          return !method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function';
        })) fail('InvalidInstallationMetadataJournal');
      } catch (cause) { failure = cause; }
      return Object.freeze({journal, failure, close() {
        closing = true;
        if (released) return;
        closeRunBindings();
        if (originalClose === undefined) throw failure;
        const acknowledged = Reflect.apply(originalClose, journal, []);
        if (typeof acknowledged !== 'boolean') fail('InstallationMetadataJournalCleanupUnconfirmed');
        released = true;
      }});
    }
    const custody = Object.freeze({credential, sign, signInstallationMetadata,
      ...(construction === undefined ? {} : {construction}),
      ...(construction === undefined ? {} : {retainOperationSite(site: BindingSite, originalBind?: BindInstalledAcquisition): BindingSite {
        ensureOpen();
        if (this !== custody || site === null || typeof site !== 'object' ||
            nodeTypes.isProxy(site) || !Object.isFrozen(site) || originalBind !== undefined &&
            (typeof originalBind !== 'function' || nodeTypes.isProxy(originalBind) || nodeTypes.isAsyncFunction(originalBind))) {
          fail('ForeignInstalledCredentialOperationSite');
        }
        const fields = Object.getOwnPropertyDescriptors(site);
        if (!Object.hasOwn(fields.credential ?? {}, 'value') || fields.credential.value !== credential ||
            !Object.hasOwn(fields.callResource ?? {}, 'value') || typeof fields.callResource.value !== 'function' ||
            !Object.hasOwn(fields.connection ?? {}, 'value') || !text(fields.connection.value)) {
          fail('ForeignInstalledCredentialOperationSite');
        }
        const retained = operationSites.get(credential);
        if (retained !== undefined) {
          if (retained.site !== site) fail('ForeignInstalledCredentialOperationSite');
          return site;
        }
        // This same private issuer binds its own original Site. No caller may
        // replace the custody, credential, principal or immutable runtime facts.
        return retainCredentialOperationSite(site, custody,
          {connection: fields.connection.value, principalId, connectorRegistration,
            connectorRevision, runtimeBundleCid}, true, originalBind);
      }}),
      installationMetadataJournal, openRunAcquisition, bindRunAcquisition, authorizationPurpose, readChildCredential,
      bindReadResourceChild, readResourceChildCredential,
      checkGrantRequest, ensureOpen,
      referenceCurrent: () => !closing,
      // The existing generic entry calls its original journal close on every
      // close call. The Salesforce entry already skips an acknowledged close.
      // Both paths share this same physical close and never infer an ACK.
      close,
      closeOnce() { if (!released) close(); },
      cleanupPending: () => closing && !released,
    });
    return custody;
  }

  return {loadRowSourceCredentialCustody, openRowSourceCredentialCustody};
}
