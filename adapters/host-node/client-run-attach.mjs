// Reattach to one retained Run without checking or executing its Program.
// Current Host authorization is required even when a durable request exists.
const cid = value => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/u.test(value);
const text = value => typeof value === 'string' &&
  value.length > 0 && value.length <= 256 &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const denied = () => Object.assign(new Error('ClientRunAttachDenied'),
  {code: 'ClientRunAttachDenied'});

export function installNodeClientRunAttach({journal, requestControl,
  publicationControl, authorizedScope, authorizeRun}) {
  if (typeof journal?.lookupRunDefinition !== 'function' ||
      typeof requestControl?.clientRequestAdmitRecord !== 'function' ||
      typeof publicationControl?.admit !== 'function' ||
      typeof authorizedScope !== 'function' ||
      typeof authorizeRun !== 'function') {
    throw new TypeError('InvalidClientRunAttachInstallation');
  }
  return async ({principalId, connection, ref}) => {
    if (!text(principalId) || !text(ref?.namespaceId) ||
        !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid)) {
      throw new TypeError('InvalidClientRunAttach');
    }
    const requested = Object.freeze({...ref});
    let selected;
    try {
      selected = await authorizedScope(Object.freeze({
        principalId, connection, ref: requested,
      }));
    } catch { throw denied(); }
    if (selected?.namespaceId !== requested.namespaceId ||
        selected?.authorityScopeCid !== requested.authorityScopeCid) {
      throw denied();
    }
    const retained = journal.lookupRunDefinition(requested, requestControl,
      publicationControl);
    if (retained === undefined) throw denied();
    let allowed;
    try {
      allowed = await authorizeRun(Object.freeze({
        principalId, connection, ref: requested,
        runDefinition: retained.runDefinition,
      }));
    } catch { throw denied(); }
    if (allowed !== true) throw denied();
    return Object.freeze({ref: retained.ref,
      durability: retained.durability, revision: retained.revision});
  };
}
