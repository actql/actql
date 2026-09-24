// Project the durable request journal into the public lookup operation. The
// installed Host supplies the current authorized scope; the caller supplies
// only the request ID. Lookup never opens a Run or starts Compute.
const cid = value => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/u.test(value);
const text = value => typeof value === 'string' &&
  value.length > 0 && value.length <= 256 &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const denied = () => Object.assign(new Error('ClientRequestLookupDenied'),
  {code: 'ClientRequestLookupDenied'});

export function installNodeClientRequestLookup({journal, control,
  authorizedScope}) {
  if (typeof journal?.lookup !== 'function' ||
      typeof control?.clientRequestAdmitRecord !== 'function' ||
      typeof authorizedScope !== 'function') {
    throw new TypeError('InvalidClientRequestLookupInstallation');
  }
  return async ({principalId, connection, requestId}) => {
    if (!text(principalId) || !text(requestId)) {
      throw new TypeError('InvalidClientRequestLookup');
    }
    // The callback may consult a changing grant store. Its owned answer is
    // copied before physical lookup so an async caller cannot retarget it.
    let selected;
    try {
      selected = await authorizedScope(Object.freeze({
        principalId, connection, requestId,
      }));
    } catch {
      throw denied();
    }
    const tenantId = selected?.tenantId;
    const authorityScopeCid = selected?.authorityScopeCid;
    if (!text(tenantId) || !cid(authorityScopeCid)) {
      throw denied();
    }
    let found;
    try {
      found = journal.lookup({tenantId, authorityScopeCid, requestId},
        control);
    } catch {
      return Object.freeze({kind: 'unknown',
        reason: 'request_store_unavailable'});
    }
    if (found === undefined) return Object.freeze({kind: 'not_found'});
    return Object.freeze({
      kind: 'found', requestId, ref: found.ref,
      durability: found.durability,
      lookupExpiresAt: found.lookupExpiresAt,
    });
  };
}
