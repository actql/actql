// Bind an authenticated HTTP input to the installed Host's SAME Request
// preparation and pending-call registry. HTTP owns decoding/authorization;
// the existing manager owns snapshot/compiler admission and child retirement.
import {snapshotClientRequest} from '../../packages/client-wire/index.mjs';
import {freezeInput} from '../../packages/sdk/internal/private-source-preparation.mjs';

export function installHttpRequestPreparation(preparation, registry, originals, {rawInput = false} = {}) {
  const manager = preparation.requestPreparation();
  const {host, installation, generation} = originals;
  const prepare = (operation, request, raw) => {
    let settled;
    const pending = new Promise(resolve => {settled = resolve;});
    registry.retainRequest(host, installation, generation, request, pending);
    let receipt = raw?.receipt, body = request, finished = false;
    const finish = terminal => {
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
        } else manager.bindHttpRequestKind(receipt, request.kind, request.connection);
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
        beforeReply() {
          if (operation !== 'connect') preparation.assertResultPublicationCurrent();
        },
        bindRequest(derived) {
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
  Object.defineProperty(prepare, 'beforeBody', {value(operation, wireLimit) {
    const raw = {receipt: Reflect.apply(before, manager, []),
      finished: false, ending: false, prepared: false, jsonReady: false};
    const active = () => {
      if (raw.finished || raw.ending || raw.prepared) throw new Error('InvalidClientHostPreparation');
    };
    return Object.freeze({
      beforeRead(bytes, chunks, quantum) {
        active();
        if (raw.jsonReady) throw new Error('InvalidClientHostPreparation');
        Reflect.apply(reserve, manager, [raw.receipt, bytes, chunks, quantum, wireLimit]);
      },
      beforeJson(wire) {
        active();
        if (raw.jsonReady) throw new Error('InvalidClientHostPreparation');
        Reflect.apply(json, manager, [raw.receipt, wire]);
        raw.jsonReady = true;
      },
      prepareRequest(request) {
        active();
        if (!raw.jsonReady) throw new Error('InvalidClientHostPreparation');
        raw.prepared = true;
        return prepare(operation, request, raw);
      },
      finish(terminal) {
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
  return Object.freeze(prepare);
}
