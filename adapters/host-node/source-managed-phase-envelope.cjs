'use strict';

// Selected Source recipe DATA, not a startup/Source issuer or an external
// allocator. The actual early startup retains the SAME control declaration
// and adopts this additional scope before any SDK snapshot/preparation.
const freeze = Object.freeze, integer = Number.isSafeInteger;
const NativeError = Error;
const MiB = 1024 * 1024;
const unavailable = () => {throw Object.assign(new NativeError('SourceManagedEnvelopeUnavailable'),
  {code:'SourceManagedEnvelopeUnavailable'});};
const inputLimits = freeze({maxProperties: 40, maxNodes: 40, maxDepth: 3,
  maxStringCodeUnits: 65536, maxTotalStringCodeUnits: 65536 + 4096,
  maxArrayItems: 0, maxOpaqueAliases: 0, maxWork: 2 * 1024 * 1024});
const limits = freeze({installations: 1, requests: 1, sourceOccurrences: 1,
  sourceBytes: 65536, sourceNodes: 4096, sourceDepth: 64,
  sourceWork: 2 * 1024 * 1024, rows: 4096, columns: 128,
  responseBytes: MiB, responses: 128, decodedWireBytes: MiB,
  // Explicit separate external representations: original SDK input/body and
  // transport clone, serializations, UTF8/hash preimages, response/row decode
  // workspace and captured output representations. Actual external suppliers
  // must cover these BEFORE use; this calculation supplies no Buffer/FD/TLS.
  simultaneousExternalRepresentations: 16,
  requestControlRecords: 256, perResponseControlRecords: 64});

function declareSourceManagedPhaseEnvelope(controlDeclaration) {
  if (controlDeclaration === null || typeof controlDeclaration !== 'object' ||
      !integer(controlDeclaration.heapCeilingBytes) || controlDeclaration.heapCeilingBytes <= 0 ||
      !integer(controlDeclaration.bytes) || controlDeclaration.bytes < controlDeclaration.heapCeilingBytes) unavailable();
  // One shared VM/compiled-module/native domain, NOT a second whole heap or
  // spendable initial-control credit. The complete existing control total and
  // all escaped control/native/module holdings coexist with this Source.
  const responseBackingBytes = limits.responses * limits.responseBytes;
  const externalWorkspaceBytes = limits.simultaneousExternalRepresentations * limits.decodedWireBytes;
  const externalBytes = responseBackingBytes + externalWorkspaceBytes;
  const simultaneousBytes = controlDeclaration.bytes + externalBytes;
  if (!integer(simultaneousBytes)) unavailable();
  return freeze({limits,inputLimits,controlDeclaration,
    sharedManagedHeapBytes:controlDeclaration.heapCeilingBytes,
    additionalManagedHeapBytes:0,additionalWholeNativeDomainBytes:0,
    responseBackingBytes,externalWorkspaceBytes,externalBytes,simultaneousBytes,
    managedOverlap:freeze(['SDK original input/options and descriptor/path traversal',
      'frozen submission body, request identity and transport clone',
      'intent preimage/hash Promise and pending/context records',
      'Host original request, preparation and original Environment',
      'Common parse/check/compile graph, contracts and acquisition',
      'RowRun, captured row/value cursors and bounded canonical output',
      'callbacks/receivers, first/latest failures, partial cleanup and escaped aliases']),
    externalRequired:freeze(['original response ArrayBuffer allocations',
      'input/output encoding, hashing and decode workspace',
      'FD/socket/TLS and incoming transport chunks',
      'Store/Journal physical copies, commit and close uncertainty']),
    lifetime:'same-original-process-and-escaped-Source-lifetime',
    replenishedOnSourceClose:false});
}

module.exports=freeze({declareSourceManagedPhaseEnvelope});
