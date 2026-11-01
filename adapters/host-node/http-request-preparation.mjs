// Bind an authenticated HTTP input to the installed Host's SAME Request
// preparation and pending-call registry. HTTP owns decoding/authorization;
// the existing manager owns snapshot/compiler admission and child retirement.
import {snapshotClientRequest} from '../../packages/client-wire/index.mjs';
import {freezeInput} from '../../packages/sdk/internal/private-source-preparation.mjs';

export function installHttpRequestPreparation(preparation, registry, originals) {
  const manager = preparation.requestPreparation();
  const {host, installation, generation} = originals;
  return (operation, request) => {
    let settled;
    const pending = new Promise(resolve => {settled = resolve;});
    registry.retainRequest(host, installation, generation, request, pending);
    let receipt, body = request, finished = false;
    const finish = terminal => {
      if (finished) return;
      try {
        if (receipt !== undefined) manager.finishSourceProducer(receipt, terminal);
        finished = true;
      } catch (cause) {
        // The same manager/initial control retains failed producer cleanup.
        // Preserve a primary dispatch failure instead of replacing it with
        // cleanup's error, or treating either failure as an acknowledgement.
        if (terminal !== 'failed') throw cause;
      } finally {settled();}
    };
    try {
      if (operation !== 'connect') preparation.beforeResultPublicationOperation(operation);
      if (['plan', 'submit', 'submit-intent', 'submit-named-intent', 'restart-intent'].includes(operation)) {
        receipt = manager.beforeSourceSnapshot(request.kind, request.input, request, request.connection);
        body = manager.captureSourceSnapshot(receipt, request, snapshotClientRequest);
        manager.assertSourceSnapshotCurrent(receipt);
        freezeInput(body);
        manager.bindSourceSnapshot(receipt, body);
        manager.bindSourceRequest(receipt, body, request);
        // The normal submission service compares this original typed intent
        // against the supplied CID; transport does not certify equality.
        if (operation !== 'plan' && operation !== 'submit') manager.intentCid(receipt, body);
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
}
