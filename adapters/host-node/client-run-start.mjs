// Current Host policy is observed before the durable one-time start claim.
// The journal persists the shared MoonBit decision before physical dispatch.
const text = value => typeof value === 'string' && value.length > 0 &&
  value.length <= 256 && !/[\u0000-\u001f\u007f]/u.test(value);
const denied = () => Object.assign(new Error('ClientRunStartDenied'),
  {code: 'ClientRunStartDenied'});

export function installNodeClientRunStart({journal, requestControl,
  publicationControl, authorizeRunStart}) {
  if (typeof journal?.lookupDefinition !== 'function' ||
      typeof journal?.reserveDispatch !== 'function' ||
      typeof requestControl?.clientRunStartAction !== 'function' ||
      typeof requestControl?.clientRequestAuthorityScopeCid !== 'function' ||
      typeof requestControl?.clientRequestCallerId !== 'function' ||
      typeof publicationControl?.admit !== 'function' ||
      typeof authorizeRunStart !== 'function') {
    throw new TypeError('InvalidClientRunStartInstallation');
  }
  return async ({identity, tenantId, principalId, connection}) => {
    if (!text(tenantId) || !text(principalId) ||
        connection === null || typeof connection !== 'object') {
      throw new TypeError('InvalidClientRunStart');
    }
    const retained = journal.lookupDefinition({tenantId,
      authorityScopeCid: requestControl.clientRequestAuthorityScopeCid(identity),
      requestId: requestControl.clientRequestCallerId(identity)},
    requestControl, publicationControl);
    if (retained === undefined) throw denied();
    let authorized;
    try {
      authorized = await authorizeRunStart(Object.freeze({
        tenantId, principalId, connection,
        ref: retained.ref, runDefinition: retained.runDefinition,
      }));
    } catch { authorized = false; }
    return journal.reserveDispatch(identity, {tenantId,
      currentAuthorization: authorized === true}, requestControl,
    publicationControl);
  };
}
