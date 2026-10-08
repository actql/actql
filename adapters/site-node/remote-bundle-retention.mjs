// Opt-in custody for already installed members. This does not expose bundle
// installation, activation, draining, or arbitrary hold identifiers.
const fail = code => { throw Object.assign(new Error(code), {code}); };
const text = value => typeof value === 'string' && value.length > 0;
const scopeKey = (authority, workspace, authorityScope, environment, bundle) =>
  JSON.stringify([authority, workspace, authorityScope, environment, bundle]);

export function createRemoteBundleRetentionCustodian({
  bundleStore, bundleControl, dispatchControl, registration, scopes,
} = {}) {
  for (const name of ['retentionContext', 'retainMember', 'inspectMemberHold',
    'releaseMember', 'inspect']) {
    if (typeof bundleStore?.[name] !== 'function') fail('InvalidBundleRetentionCustodian');
  }
  for (const name of ['admitCustodyRequestJson', 'custodyRequestIdentity',
    'custodyRequestJson', 'custodyRequestScope', 'custodyRequestBinding',
    'custodyRequestOperation', 'holdScopeProjection', 'holdScopeJson',
    'prepareHoldBindingFromScope', 'prepareCustodyContextResponse',
    'prepareCustodyResponse', 'custodyResponseJson', 'custodyResponseIdentity',
    'projection']) {
    if (typeof bundleControl?.[name] !== 'function') fail('BundleRetentionUnsupported');
  }
  if (typeof dispatchControl?.managedRuntimeRegistrationScope !== 'function' ||
      registration === null || typeof registration !== 'object' ||
      !Array.isArray(scopes)) fail('InvalidBundleRetentionCustodian');
  const registered = Object.freeze([...dispatchControl.managedRuntimeRegistrationScope(
    registration.capability, registration.issuer)]);
  if (registered.length !== 8 || !registered.every(text) ||
      !/^(0|[1-9][0-9]*)$/.test(registered[1]) ||
      !Number.isSafeInteger(Number(registered[1]))) fail('InvalidBundleRetentionCustodian');
  const allowed = new Set();
  for (const value of scopes) {
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        Object.keys(value).sort().join() !== [
          'authorityScopeCid', 'coordinatorAuthority', 'environment',
          'runtimeBundleCid', 'workspaceId'].join()) {
      fail('InvalidBundleRetentionScope');
    }
    const {coordinatorAuthority, workspaceId, authorityScopeCid,
      environment, runtimeBundleCid} = value;
    if (![coordinatorAuthority, workspaceId, authorityScopeCid, environment,
      runtimeBundleCid].every(text) || runtimeBundleCid !== registered[2]) {
      fail('InvalidBundleRetentionScope');
    }
    const key = scopeKey(coordinatorAuthority, workspaceId, authorityScopeCid,
      environment, runtimeBundleCid);
    if (allowed.has(key)) fail('BundleRetentionScopeAmbiguous');
    allowed.add(key);
  }
  const verifyMember = value => {
    if (value === undefined) return;
    const member = bundleControl.projection(value.manifest);
    if (member[0] !== registered[2] || member[7] !== registered[3] ||
        member[8] !== registered[4] || member[9] !== registered[5]) {
      fail('RemoteRuntimeBundleRegistrationMismatch');
    }
  };
  return Object.freeze({
    siteKey: registered[0], siteGeneration: Number(registered[1]),
    admitRequest: bundleControl.admitCustodyRequestJson,
    responseJson: bundleControl.custodyResponseJson,
    responseIdentity: bundleControl.custodyResponseIdentity,
    async handle(coordinatorAuthority, suppliedRequest, {admissionOpen = true} = {}) {
      // Keep the accepted request independent of caller-owned opaque objects
      // throughout asynchronous verification and response construction.
      const request = bundleControl.admitCustodyRequestJson(
        bundleControl.custodyRequestJson(suppliedRequest),
        bundleControl.custodyRequestIdentity(suppliedRequest));
      const scope = bundleControl.custodyRequestScope(request);
      bundleControl.holdScopeJson(scope);
      const parts = bundleControl.holdScopeProjection(scope);
      if (parts[1] !== coordinatorAuthority || parts[8] !== registered[0] ||
          parts[9] !== registered[1] || parts[7] !== registered[2] ||
          !allowed.has(scopeKey(parts[1], parts[2], parts[3], parts[4], parts[7]))) {
        fail('BundleRetentionAuthorityRejected');
      }
      const operation = bundleControl.custodyRequestOperation(request);
      const binding = bundleControl.custodyRequestBinding(request);
      if (operation === 'retain' && !admissionOpen) fail('BundleRetentionAdmissionClosed');
      verifyMember(bundleStore.inspect(registered[2], bundleControl));
      if (binding === undefined) {
        const context = await bundleStore.retentionContext(registered[2], bundleControl);
        verifyMember(context);
        const selected = bundleControl.prepareHoldBindingFromScope(scope,
          context.catalogIncarnation, context.initialRevision);
        return bundleControl.prepareCustodyContextResponse(request, selected);
      }
      const observation = operation === 'retain'
        ? await bundleStore.retainMember(binding, bundleControl)
        : operation === 'release'
          ? await bundleStore.releaseMember(binding, bundleControl)
          : await bundleStore.inspectMemberHold(binding, bundleControl);
      return bundleControl.prepareCustodyResponse(request, observation);
    },
  });
}
