// Reattach to one retained Run without checking or executing its Program.
// Current Host authorization is required even when a durable request exists.
import type {WireRequestLookup, WireRunRef} from '../../packages/client-wire/index.js';

type RequestControlPort = Readonly<{clientRequestAdmitRecord: unknown}>;
type PublicationControlPort = Readonly<{admit: unknown}>;
type Durability = Extract<WireRequestLookup, {kind: 'found'}>['durability'];
type Retained<Definition> = Readonly<{ref: WireRunRef; durability: Durability; revision: number; runDefinition: Definition}>;
type AttachInput<Connection> = Readonly<{principalId: string; connection: Connection; ref: WireRunRef}>;
type ScopeAnswer = Readonly<{namespaceId?: unknown; authorityScopeCid?: unknown}> | undefined;
type AttachInstallation<Connection, RequestControl, PublicationControl, Definition> = Readonly<{
  journal: Readonly<{
    lookupRunDefinition(ref: WireRunRef, requestControl: RequestControl, publicationControl: PublicationControl):
      Retained<Definition> | undefined;
  }>;
  requestControl: RequestControl;
  publicationControl: PublicationControl;
  authorizedScope(input: AttachInput<Connection>): ScopeAnswer | PromiseLike<ScopeAnswer>;
  authorizeRun(input: Readonly<AttachInput<Connection> & {runDefinition: Definition}>): unknown;
}>;

const cid = (value: unknown): value is string => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/u.test(value);
const text = (value: unknown): value is string => typeof value === 'string' &&
  value.length > 0 && value.length <= 256 &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const denied = () => Object.assign(new Error('ClientRunAttachDenied'),
  {code: 'ClientRunAttachDenied'});

export function installNodeClientRunAttach<Connection, RequestControl extends RequestControlPort,
  PublicationControl extends PublicationControlPort, Definition>({journal, requestControl,
  publicationControl, authorizedScope, authorizeRun}: AttachInstallation<Connection, RequestControl, PublicationControl, Definition>) {
  if (typeof journal?.lookupRunDefinition !== 'function' ||
      typeof requestControl?.clientRequestAdmitRecord !== 'function' ||
      typeof publicationControl?.admit !== 'function' ||
      typeof authorizedScope !== 'function' ||
      typeof authorizeRun !== 'function') {
    throw new TypeError('InvalidClientRunAttachInstallation');
  }
  return async ({principalId, connection, ref}: AttachInput<Connection>) => {
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
