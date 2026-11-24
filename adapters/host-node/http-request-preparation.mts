// Bind an authenticated HTTP input to the installed Host's SAME Request
// preparation and pending-call registry. HTTP owns decoding/authorization;
// the existing manager owns snapshot/compiler admission and child retirement.
import {snapshotClientRequest} from '../../packages/client-wire/index.mjs';
import {freezeInput} from '../../packages/sdk/internal/private-source-preparation.mjs';

import type {ClientHostOperation} from '../../packages/client-wire/index.js';
import type {captureSourcePreparation} from '../../packages/sdk/internal/private-source-preparation.mjs';
import type {createEmbeddedHostRegistry} from './embedded-local-lifecycle.mjs';

type SourcePreparation = NonNullable<ReturnType<typeof captureSourcePreparation>>;
type Manager = Pick<SourcePreparation, 'beforeSourceSnapshot' | 'captureSourceSnapshot' |
  'assertSourceSnapshotCurrent' | 'bindSourceSnapshot' | 'bindSourceRequest' | 'intentCid' | 'finishSourceProducer'> &
  Readonly<{
    beforeHttpRequestBody?(): unknown;
    reserveHttpRequestBody?(receipt: unknown, bytes: number, chunks: number, quantum: number, wireLimit: number): unknown;
    prepareHttpRequestJson?(receipt: unknown, wire: string): unknown;
    bindHttpRequestKind?(receipt: unknown, kind: unknown, connection: unknown): unknown;
  }>;
type Preparation = Readonly<{
  requestPreparation(): Manager;
  beforeResultPublicationOperation(operation: ClientHostOperation): unknown;
  assertResultPublicationCurrent(): unknown;
}>;
type Registry = Pick<ReturnType<typeof createEmbeddedHostRegistry>, 'retainRequest' | 'bindSourceRequest'>;
type Originals = Readonly<Record<'host' | 'installation' | 'generation', unknown>>;
type Request = Readonly<Record<string, unknown>>;
type Terminal = 'returned' | 'failed';
type Raw = {
  receipt: unknown;
  finished: boolean;
  ending: boolean;
  prepared: boolean;
  jsonReady: boolean;
};
type Prepared = Readonly<{
  body: unknown;
  beforeReply(): undefined;
  bindRequest(derived: unknown): undefined;
  finish(terminal: Terminal): undefined;
}>;
type BodyLifetime = Readonly<{
  beforeRead(bytes: number, chunks: number, quantum: number): undefined;
  beforeJson(wire: string): undefined;
  prepareRequest(request: Request): Prepared;
  finish(terminal: Terminal): undefined;
}>;
type Prepare = (operation: ClientHostOperation, request: Request) => Prepared;
type PrepareRaw = Prepare & Readonly<{beforeBody(operation: ClientHostOperation, wireLimit: number): BodyLifetime}>;
type Options = Readonly<{rawInput?: boolean}>;

export function installHttpRequestPreparation(
  preparation: Preparation, registry: Registry, originals: Originals, options: Readonly<{rawInput: true}>,
): PrepareRaw;
export function installHttpRequestPreparation(
  preparation: Preparation, registry: Registry, originals: Originals, options?: Options,
): Prepare | PrepareRaw;
export function installHttpRequestPreparation(
  preparation: Preparation, registry: Registry, originals: Originals, {rawInput = false}: Options = {},
) {
  const manager = preparation.requestPreparation();
  const {host, installation, generation} = originals;
  const prepare = (operation: ClientHostOperation, request: Request, raw?: Raw): Prepared => {
    let settled!: () => void;
    const pending = new Promise<void>(resolve => {settled = resolve;});
    registry.retainRequest(host, installation, generation, request, pending);
    let receipt = raw?.receipt, body: unknown = request, finished = false;
    const finish = (terminal: Terminal): undefined => {
      if (finished) return;
      try {
        if (raw !== undefined) raw.ending = true;
        if (receipt !== undefined) manager.finishSourceProducer(receipt, terminal);
        finished = true;
        if (raw !== undefined) raw.finished = true;
      } catch (cause) {
        // The same manager/initial control retains failed producer cleanup.
        // Preserve a primary dispatch failure instead of replacing it with
        // cleanup's error, or treating either failure as an acknowledgement.
        if (terminal !== 'failed') throw cause;
      } finally {settled();}
    };
    try {
      if (operation !== 'connect') preparation.beforeResultPublicationOperation(operation);
      if (['plan', 'static-explanation', 'submit', 'submit-intent', 'submit-named-intent', 'restart-intent'].includes(operation)) {
        if (raw === undefined) {
          receipt = manager.beforeSourceSnapshot(request.kind, request.input, request, request.connection);
        } else manager.bindHttpRequestKind!(receipt, request.kind, request.connection);
        body = manager.captureSourceSnapshot(receipt, request, snapshotClientRequest);
        manager.assertSourceSnapshotCurrent(receipt);
        freezeInput(body);
        manager.bindSourceSnapshot(receipt, body);
        manager.bindSourceRequest(receipt, body, request);
        // The normal submission service compares this original typed intent
        // against the supplied CID; transport does not certify equality.
        if (operation !== 'plan' && operation !== 'static-explanation' && operation !== 'submit') {
          manager.intentCid(receipt, body);
        }
      }
      return Object.freeze({body,
        beforeReply(): undefined {
          if (operation !== 'connect') preparation.assertResultPublicationCurrent();
        },
        bindRequest(derived: unknown): undefined {
          registry.bindSourceRequest(host, installation, generation, request, derived);
        }, finish});
    } catch (cause) {
      finish('failed');
      throw cause;
    }
  };
  if (!rawInput) return prepare;
  const before = manager.beforeHttpRequestBody, reserve = manager.reserveHttpRequestBody;
  const json = manager.prepareHttpRequestJson, bind = manager.bindHttpRequestKind;
  if ([before, reserve, json, bind].some(method => typeof method !== 'function')) {
    throw new TypeError('InvalidClientHostPreparation');
  }
  Object.defineProperty(prepare, 'beforeBody', {value(operation: ClientHostOperation, wireLimit: number): BodyLifetime {
    const raw: Raw = {receipt: Reflect.apply(before!, manager, []),
      finished: false, ending: false, prepared: false, jsonReady: false};
    const active = () => {
      if (raw.finished || raw.ending || raw.prepared) throw new Error('InvalidClientHostPreparation');
    };
    return Object.freeze({
      beforeRead(bytes: number, chunks: number, quantum: number): undefined {
        active();
        if (raw.jsonReady) throw new Error('InvalidClientHostPreparation');
        Reflect.apply(reserve!, manager, [raw.receipt, bytes, chunks, quantum, wireLimit]);
      },
      beforeJson(wire: string): undefined {
        active();
        if (raw.jsonReady) throw new Error('InvalidClientHostPreparation');
        Reflect.apply(json!, manager, [raw.receipt, wire]);
        raw.jsonReady = true;
      },
      prepareRequest(request: Request) {
        active();
        if (!raw.jsonReady) throw new Error('InvalidClientHostPreparation');
        raw.prepared = true;
        return prepare(operation, request, raw);
      },
      finish(terminal: Terminal): undefined {
        if (raw.finished || raw.ending) return;
        raw.ending = true;
        // A failed original remains in the manager's producer inventory.
        // This call returns no acknowledgement for an external stream owner.
        try {
          Reflect.apply(manager.finishSourceProducer, manager, [raw.receipt, terminal]);
          raw.finished = true;
        } catch (cause) {
          if (terminal !== 'failed') throw cause;
        }
      },
    });
  }});
  return Object.freeze(prepare) as PrepareRaw;
}
