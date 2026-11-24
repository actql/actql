import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';

import type {installRunKeyedContentCapture} from './installed-keyed-content-capture.mjs';
import type {createInstalledRowSource} from './installed-row-source.mjs';

type CaptureSetup = Parameters<typeof installRunKeyedContentCapture>[0];
type CaptureOptions = Pick<CaptureSetup, 'preparedProgram' | 'plan' | 'acquisition' | 'ledger' |
  'maxBytes' | 'maxWork' | 'store' | 'principalId' | 'signal' | 'inputAvailable' | 'sourceBinding' | 'retainExecution'>;
type CaptureFrame = ReturnType<typeof installRunKeyedContentCapture>;
type Execution = Parameters<CaptureSetup['retainExecution']>[0];
type Source = Awaited<ReturnType<typeof createInstalledRowSource>>;
type Adapter = Required<Pick<Source, 'verifyKeyedRead' | 'keyedRecoveryBinding' | 'keyedLedgerCapacity'>>;
type VerifyRead = Parameters<Adapter['verifyKeyedRead']>[0];
type RecoveryPorts = Readonly<{
  publications: Pick<CaptureSetup['publications'], 'checkClientCompiledRunOwner'>;
  run: Readonly<{captureKeyed(options: CaptureOptions): CaptureFrame}>;
}>;
type RecoveryInputs = Pick<CaptureSetup, 'preparedProgram' | 'plan' | 'store' | 'principalId' |
  'signal' | 'ledger'> & Readonly<{
  modelController: Readonly<{
    capturedContent(token: unknown, runDefinitionCid: string): unknown;
    capturedContentBinding(token: unknown, runDefinitionCid: string): CaptureSetup['sourceBinding'];
  }>;
  inputToken: unknown;
  keyedSource: Readonly<{
    adapter: Adapter;
    acquisition: VerifyRead['keyedAcquisition'];
    prepared: VerifyRead['preparedKeyed'];
    sourceAccess: VerifyRead['sourceAccess'];
  }>;
  retainExecution(execution: Execution & Readonly<{
    recoveryFrame: CaptureFrame | undefined;
    retryRecovery(): Promise<void>;
  }>): unknown;
}>;

// The caller retains this original frame on its existing Model/input owner
// before allocation. Authentication supplies metadata only; the original
// Source gate and physical Store must independently confirm current access
// and every holding. This never opens a Source request or a payload writer.
export function createKeyedContentRunRecovery({publications, run}: RecoveryPorts) {
  return async ({preparedProgram, plan, store, principalId, signal, ledger,
    modelController, inputToken, keyedSource, retainExecution}: RecoveryInputs) => {
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    const original = modelController.capturedContent(inputToken, plan.runDefinition.identity);
    if (original === undefined || typeof keyedSource?.adapter?.verifyKeyedRead !== 'function') {
      throw new TypeError('InstalledCapturedContentRecoveryUnavailable');
    }
    const originalBinding = modelController.capturedContentBinding(inputToken, plan.runDefinition.identity);
    const currentBinding = () => keyedSource.adapter.keyedRecoveryBinding(keyedSource.prepared);
    const recheckBinding = () => {
      if (originalBinding === undefined ||
          canonicalValueJson(originalBinding) !== canonicalValueJson(currentBinding())) {
        throw new TypeError('InstalledCapturedContentBindingMismatch');
      }
    };
    recheckBinding();
    const inputAvailable = () => {
      try { return modelController.capturedContent(inputToken, plan.runDefinition.identity) === original; }
      catch { return false; }
    };
    const verifyRead = async () => {
      signal?.throwIfAborted();
      recheckBinding();
      if (!inputAvailable()) throw new Error('InstalledContentAuthorityUnavailable');
      await keyedSource.adapter.verifyKeyedRead({preparedProgram,
        keyedAcquisition: keyedSource.acquisition, preparedKeyed: keyedSource.prepared,
        sourceAccess: keyedSource.sourceAccess, signal});
      signal?.throwIfAborted();
      recheckBinding();
      if (!inputAvailable()) throw new Error('InstalledContentAuthorityUnavailable');
    };
    // The caller supplies its declared shared Run Ledger. No parallel Ledger
    // or sampled-row capacity is introduced for restoring captured references.
    const capacity = keyedSource.adapter.keyedLedgerCapacity(keyedSource.acquisition);
    let frame: CaptureFrame | undefined;
    frame = run.captureKeyed({preparedProgram, plan, acquisition: keyedSource.acquisition,
      ledger, maxBytes: capacity.maxBytes, maxWork: capacity.maxWork, store, principalId,
      signal, inputAvailable, sourceBinding: originalBinding,
      retainExecution: child => retainExecution(Object.freeze({...child,
        // Allocation/confirmation can fail after the owner is retained. Keep
        // the exact receiver with that same cleanup responsibility for retry.
        get recoveryFrame() { return frame; },
        retryRecovery: () => frame!.recoverInventory({keyedAcquisition: keyedSource.acquisition,
          inventory: original, verifyRead}),
      }))});
    await frame.recoverInventory({keyedAcquisition: keyedSource.acquisition,
      inventory: original, verifyRead});
    return frame;
  };
}
