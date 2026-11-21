// Project the durable request journal into the public lookup operation. The
// installed Host supplies the current authorized scope; the caller supplies
// only the request ID. Lookup never opens a Run or starts Compute.
import type {WireRequestLookup, WireRunRef} from '../../packages/client-wire/index.js';

type LookupKey = Readonly<Pick<WireRunRef, 'namespaceId' | 'authorityScopeCid'> & {requestId: string}>;
type Found = Pick<Extract<WireRequestLookup, {kind: 'found'}>, 'ref' | 'durability' | 'lookupExpiresAt'>;
type ControlPort = Readonly<{clientRequestAdmitRecord: unknown}>;
type LookupInput<Connection> = Readonly<{principalId: string; connection: Connection; requestId: string}>;
type ScopeAnswer = Readonly<{namespaceId?: unknown; authorityScopeCid?: unknown}> | undefined;
type LookupInstallation<Control, Connection> = Readonly<{
  journal: Readonly<{lookup(key: LookupKey, control: Control): Found | undefined}>;
  control: Control;
  authorizedScope(input: LookupInput<Connection>): ScopeAnswer | PromiseLike<ScopeAnswer>;
}>;

const cid = (value: unknown): value is string => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/u.test(value);
const text = (value: unknown): value is string => typeof value === 'string' &&
  value.length > 0 && value.length <= 256 &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const denied = () => Object.assign(new Error('ClientRequestLookupDenied'),
  {code: 'ClientRequestLookupDenied'});

export function installNodeClientRequestLookup<Control extends ControlPort, Connection>({journal, control,
  authorizedScope}: LookupInstallation<Control, Connection>) {
  if (typeof journal?.lookup !== 'function' ||
      typeof control?.clientRequestAdmitRecord !== 'function' ||
      typeof authorizedScope !== 'function') {
    throw new TypeError('InvalidClientRequestLookupInstallation');
  }
  return async ({principalId, connection, requestId}: LookupInput<Connection>): Promise<WireRequestLookup> => {
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
    const namespaceId = selected?.namespaceId;
    const authorityScopeCid = selected?.authorityScopeCid;
    if (!text(namespaceId) || !cid(authorityScopeCid)) {
      throw denied();
    }
    let found;
    try {
      found = journal.lookup({namespaceId, authorityScopeCid, requestId},
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
