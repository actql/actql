'use strict';

// Support for the separately selected, same-runtime no-I/O OriginalMock
// purpose. This declaration is neither an original issuer nor a backed
// numerical amount, Model permission, or a generic/async Provider facility.
const freeze = Object.freeze;
const unavailable = () => {throw Object.assign(new Error('LocalMockModelPreparationUnavailable'),
  {code: 'LocalMockModelPreparationUnavailable'});};

function declareHostLocalMockModelServiceRecipe(control, sourceCompute, result) {
  if (control === null || typeof control !== 'object' ||
      sourceCompute?.sourceDeclaration?.controlDeclaration !== control ||
      result?.sharedControl !== control || result.sourceCompute !== sourceCompute) unavailable();
  return freeze({kind: 'selected-node-local-original-mock-model-service',
    sharedControl: control, sourceCompute, result,
    installations: 1, requests: 1, inferComponents: 1,
    // These are the existing Common standard input/Model support ceilings.
    // The fixed semantic Owner derives the actual purpose's clamped limits;
    // this service does not override a Task/Host cap or give it parent credit.
    limits: freeze({items: 100, inputRows: 100, inputValueNodes: 20000,
      inputTextBytes: 500000, inputDepth: 100, mappingWorkspace: 10000,
      requestBytes: 65536, responseBytes: 65536, attempts: 100,
      planningWork: 10000, holdings: 100, transferBytes: 13107200,
      retainedBytes: 6553600, executionBytes: 6553600}),
    shared: freeze(['same selected managed runtime, compile/lazy/module/native/allocator and stack service',
      'same actual Common instance, initial/Journal/filesystem/crypto originals and process lifetime']),
    retained: freeze(['all original Project/Task/answers/profile/normalized prompt and checked-value aliases',
      'same original packet, prepared Program, request, compiled Run/Definition/graph and candidate',
      'first bootstrap and census, Source siblings and retained capture/provider input ports',
      'Model read/consumer/call Scope, prepared rows, keys, input identity and exact task contracts',
      'all prepared requests/prompts, original Mock lookup/answer values and bounded output history',
      'existing Model reservation map, purpose caps/publication borrow and original settlement records',
      'prefix/suffix generated sequences, output conversion, Result publication and escaped aliases',
      'current/clock callbacks, retained failures and partial cleanup until each original ACK']),
    active: freeze(['bounded input/identity/mapping and request construction workspace',
      'same no-I/O Mock dispatch, output validation and conversion, then bounded suffix work']),
    composition: 'shared once + every retained initial/Journal/Source/Run/Model/Result original + actual active phase + pending cleanup',
    excluded: freeze(['async/physical Provider, egress/HTTP/SDK/ModelIoAccess or quantities',
      'Account/Task/Result authorization, key/first-init authority, Effect or another backend']),
    lifetime: 'same original startup and every escaped Run/Model/module alias',
    replenishedOnClose: false, numericalBackingClaim: false, allocationSuccessGuaranteed: false});
}

module.exports = {declareHostLocalMockModelServiceRecipe};
freeze(module.exports);
