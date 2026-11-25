// Current Host policy is observed before the durable one-time start claim.
// The journal persists the shared MoonBit decision before physical dispatch.
import type {WireRunRef} from '../../packages/client-wire/index.js';
import type {admission} from './client-request-journal-records.mjs';

type RequestControlPort<Identity> = Readonly<{
  clientRunStartAction: unknown;
  clientRequestAuthorityScopeCid(identity: Identity): string;
  clientRequestCallerId(identity: Identity): string;
}>;
type PublicationControlPort = Readonly<{admit: unknown}>;
type StartKey = Readonly<Pick<WireRunRef, 'namespaceId' | 'authorityScopeCid'> & {requestId: string}>;
type Retained<Definition> = Readonly<{ref: WireRunRef; runDefinition: Definition}>;
type Reservation = Readonly<ReturnType<typeof admission> & {kind: 'reserved' | 'reconcile'}>;
type StartInput<Identity, Connection> = Readonly<{
  identity: Identity; namespaceId: string; principalId: string; connection: Connection;
}>;
type StartInstallation<Identity, Connection, RequestControl, PublicationControl, Definition> = Readonly<{
  journal: Readonly<{
    lookupDefinition(key: StartKey, requestControl: RequestControl, publicationControl: PublicationControl):
      Retained<Definition> | undefined;
    reserveDispatch(identity: Identity, admission: Readonly<{namespaceId: string; currentAuthorization: boolean}>,
      requestControl: RequestControl, publicationControl: PublicationControl): Reservation;
  }>;
  requestControl: RequestControl;
  publicationControl: PublicationControl;
  authorizeRunStart(input: Readonly<Retained<Definition> & {
    namespaceId: string; principalId: string; connection: Connection;
  }>): unknown;
}>;

const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0 &&
  value.length <= 256 && !/[\u0000-\u001f\u007f]/u.test(value);
const denied = () => Object.assign(new Error('ClientRunStartDenied'),
  {code: 'ClientRunStartDenied'});

export function installNodeClientRunStart<Identity, Connection extends object, RequestControl extends RequestControlPort<Identity>,
  PublicationControl extends PublicationControlPort, Definition>({journal, requestControl,
  publicationControl, authorizeRunStart}: StartInstallation<Identity, Connection, RequestControl, PublicationControl, Definition>) {
  if (typeof journal?.lookupDefinition !== 'function' ||
      typeof journal?.reserveDispatch !== 'function' ||
      typeof requestControl?.clientRunStartAction !== 'function' ||
      typeof requestControl?.clientRequestAuthorityScopeCid !== 'function' ||
      typeof requestControl?.clientRequestCallerId !== 'function' ||
      typeof publicationControl?.admit !== 'function' ||
      typeof authorizeRunStart !== 'function') {
    throw new TypeError('InvalidClientRunStartInstallation');
  }
  return async ({identity, namespaceId, principalId, connection}: StartInput<Identity, Connection>) => {
    if (!text(namespaceId) || !text(principalId) ||
        connection === null || typeof connection !== 'object') {
      throw new TypeError('InvalidClientRunStart');
    }
    const retained = journal.lookupDefinition({namespaceId,
      authorityScopeCid: requestControl.clientRequestAuthorityScopeCid(identity),
      requestId: requestControl.clientRequestCallerId(identity)},
    requestControl, publicationControl);
    if (retained === undefined) throw denied();
    let authorized;
    try {
      authorized = await authorizeRunStart(Object.freeze({
        namespaceId, principalId, connection,
        ref: retained.ref, runDefinition: retained.runDefinition,
      }));
    } catch { authorized = false; }
    return journal.reserveDispatch(identity, {namespaceId,
      currentAuthorization: authorized === true}, requestControl,
    publicationControl);
  };
}
