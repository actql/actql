import {runtimeIsError} from './compiler-binding.generated.mjs';
import {rememberOriginalDispatchFailure} from './dispatch-failure-observation.mjs';
import {ledgerUsageSnapshot} from './ledger-usage.mjs';
import {checked} from './runtime-result.mjs';
import {tuplePair} from './runtime-tuple.mjs';

import type {storeCompletedRunResultSet} from './completed-run-publication.mjs';
import type {createManagedSiteTransferCoordinator} from './managed-site-transfer.mjs';
import type {SynchronousRuntimeData} from './runtime-result.mjs';

type CommonObject = Extract<SynchronousRuntimeData, object>;
type Publication = Pick<Parameters<typeof storeCompletedRunResultSet>[0]['control'], 'admit'>;
type TransferCore = Parameters<typeof createManagedSiteTransferCoordinator>[1];
type Transfer = ReturnType<TransferCore['transferBegin']>;
type Progress = ReturnType<TransferCore['transferProgressBegin']>;
type Receipt = ReturnType<TransferCore['transferComplete']>;
type DestinationAdmission = Parameters<TransferCore['transferRecordDestinationAdmission']>[1];
type Runtime = Readonly<{
  strategyHostCount(setup: unknown): number;
  strategyHostProgramDefinitionCid(setup: unknown): string;
  strategyHostHasEffects(setup: unknown): boolean;
  strategyHostResultNames(setup: unknown): readonly string[];
  strategyHostPublicationInventory(setup: unknown): unknown;
  strategyHostPublicationInventoryCount(inventory: unknown): number;
  strategyHostPublicationInventoryDefinitionJson(inventory: unknown, index: number): unknown;
  strategyHostPublicationInventoryName(inventory: unknown, index: number): unknown;
  strategyHostPublicationInventoryTask(inventory: unknown, index: number): unknown;
  strategyHostNext(setup: unknown): unknown;
  strategyHostNextTask(setup: unknown): number;
  strategyHostManagedProducer(setup: unknown): number;
  strategyHostManagedProducers(setup: unknown): readonly number[];
  strategyHostManagedOutputMatches(setup: unknown, task: number, completed: unknown): boolean;
  strategyHostCarrierManagedOutputMatches(setup: unknown, task: number, completed: unknown): boolean;
  strategyHostManagedInputMatchesMaterial(input: unknown, material: unknown): boolean;
  strategyHostSelectManagedRegistration(setup: unknown, task: number, registration: unknown): boolean;
  strategyHostTask(dispatch: unknown): number;
  strategyHostTaskCapacity(setup: unknown, task: number): unknown;
  strategyHostRegistration(dispatch: unknown): CommonObject | undefined;
  strategyHostTaskCompleted(setup: unknown, task: number): boolean;
  strategyHostFinished(setup: unknown): boolean;
  strategyHostStop(setup: unknown): void;
  strategyHostRequireActivation(setup: unknown): void;
  strategyHostCoverActivation(setup: unknown, task: number): boolean;
  strategyHostAuthorizeActivation(setup: unknown, task: number, decision: unknown): boolean;
  strategyHostCloseOutputs(setup: unknown): void;
  strategyHostOutput(setup: unknown, task: number): CommonObject | undefined;
  strategyHostTransferBegin(setup: unknown, task: number, transferred: bigint, retained: bigint, execution: bigint): unknown;
  strategyHostTransferCharge(setup: unknown, transfer: Transfer, bytes: bigint): unknown;
  strategyHostTransferSettle(setup: unknown, transfer: Transfer, confirmed: boolean): unknown;
  strategyHostTransferComplete(setup: unknown, transfer: Transfer, retained: bigint): unknown;
  strategyHostTransferAbort(setup: unknown, transfer: Transfer, confirmed: boolean): unknown;
  strategyHostTransferRelease(setup: unknown, receipt: Receipt): unknown;
  strategyHostTransferReceiptMatches(receipt: Receipt, transfer: Transfer, source: number, bytes: bigint, retained: bigint): boolean;
  strategyHostTransferPending(transfer: Transfer): boolean;
  strategyHostBeginTransferProgress(transfer: Transfer): Progress;
  strategyHostRecordTransferSourceStop(progress: Progress): boolean;
  strategyHostRecordTransferSourceSiteSettlement(progress: Progress): boolean;
  strategyHostRecordTransferDestinationCreated(progress: Progress): boolean;
  strategyHostRecordTransferDestinationAdmission(progress: Progress, distinctMaterial: boolean, distinctGeneration: boolean,
    rows: number, batches: number, maxBatchRows: number, maxBatchBytes: number, transferredBytes: bigint, retainedBytes: bigint,
    transferLimit: bigint, retentionLimit: bigint): boolean;
  strategyHostRecordTransferDestinationHolding(progress: Progress): boolean;
  strategyHostRecordTransferDestinationReclaimed(progress: Progress): boolean;
  strategyHostRecordTransferDestinationSiteSettlement(progress: Progress): boolean;
  strategyHostRecordTransferDestinationCleanupRelease(progress: Progress): boolean;
  strategyHostRecordTransferSiteHoldingRelease(progress: Progress): boolean;
  strategyHostTransferCommitAction(progress: Progress): unknown;
  strategyHostTransferCleanupAction(progress: Progress): unknown;
  strategyHostTransferReceipt(receipt: Receipt): readonly bigint[];
  strategyHostExplain(setup: unknown, maxBytes: number, maxNodes: number): unknown;
  strategyHostRun(setup: unknown): unknown;
  clientProgramPreparationBorrowUsageIsolated?(holder: unknown, run: unknown): boolean;
  strategyHostUsage(setup: unknown): readonly bigint[];
}>;

export function createRuntimeExecutionControls(moon: Runtime, publications: Publication) {
  return {
    count: moon.strategyHostCount,
    programDefinitionCid: moon.strategyHostProgramDefinitionCid,
    programHasEffects: moon.strategyHostHasEffects,
    resultInventory(value: unknown) {
      const names = moon.strategyHostResultNames(value);
      if (!Array.isArray(names)) throw new TypeError('Invalid Result inventory');
      if (names.length === 0) return Object.freeze([]);
      const inventory = checked(moon.strategyHostPublicationInventory(value));
      const count = moon.strategyHostPublicationInventoryCount(inventory);
      if (count !== names.length) {
        throw new TypeError('Invalid Result inventory projection');
      }
      return Object.freeze(Array.from({length: count}, (_, index) => {
        const definitionContract = publications.admit(
          'result_definition',
          checked(moon.strategyHostPublicationInventoryDefinitionJson(
            inventory, index,
          )) as string,
          {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64},
        );
        const definition = JSON.parse(definitionContract.wire) as Readonly<Record<string, unknown>>;
        return Object.freeze({
          name: checked(
            moon.strategyHostPublicationInventoryName(inventory, index),
          ) as string,
          task: checked(
            moon.strategyHostPublicationInventoryTask(inventory, index),
          ) as number,
          definition: Object.freeze(definition),
          definitionContract,
        });
      }));
    },
    next: (value: unknown, observeFailure: unknown) => {
      const result = moon.strategyHostNext(value);
      try { return checked(result) as CommonObject | undefined; }
      catch (original) {
        if (runtimeIsError(result) && typeof observeFailure === 'function') {
          try { rememberOriginalDispatchFailure(original, observeFailure(value)); }
          catch { /* Optional observation cannot replace this original failure. */ }
        }
        throw original;
      }
    },
    nextTask: moon.strategyHostNextTask,
    managedProducer: moon.strategyHostManagedProducer,
    managedProducers: moon.strategyHostManagedProducers,
    managedMatches: moon.strategyHostManagedOutputMatches,
    managedCarrierMatches: moon.strategyHostCarrierManagedOutputMatches,
    managedInputMatches: moon.strategyHostManagedInputMatchesMaterial,
    selectManaged: moon.strategyHostSelectManagedRegistration,
    task: moon.strategyHostTask,
    taskCapacity: (value: unknown, task: number) => tuplePair(checked(
      moon.strategyHostTaskCapacity(value, task),
    )),
    registration: moon.strategyHostRegistration,
    completed: moon.strategyHostTaskCompleted,
    finished: moon.strategyHostFinished,
    stop: moon.strategyHostStop,
    requireActivation: moon.strategyHostRequireActivation,
    coverActivation: moon.strategyHostCoverActivation,
    authorizeActivation: moon.strategyHostAuthorizeActivation,
    closeOutputs: moon.strategyHostCloseOutputs,
    output: moon.strategyHostOutput,
    transferBegin: (value: unknown, source: number, transfer: bigint, retained: bigint, execution: bigint) => checked(
      moon.strategyHostTransferBegin(
        value, source, transfer, retained, execution,
      ),
    ) as Transfer,
    transferCharge: (value: unknown, transfer: Transfer, bytes: bigint) => checked(
      moon.strategyHostTransferCharge(value, transfer, bytes),
    ) as ReturnType<TransferCore['transferCharge']>,
    transferSettle: (value: unknown, transfer: Transfer, confirmed: boolean) => checked(
      moon.strategyHostTransferSettle(value, transfer, confirmed),
    ) as undefined,
    transferComplete: (value: unknown, transfer: Transfer, retained: bigint) => checked(
      moon.strategyHostTransferComplete(value, transfer, retained),
    ) as Receipt,
    transferAbort: (value: unknown, transfer: Transfer, confirmed: boolean) => checked(
      moon.strategyHostTransferAbort(value, transfer, confirmed),
    ) as undefined,
    transferRelease: (value: unknown, receipt: Receipt) => checked(
      moon.strategyHostTransferRelease(value, receipt),
    ) as boolean,
    transferReceiptMatches: (receipt: Receipt, transfer: Transfer, source: number, bytes: bigint, retained: bigint) =>
      moon.strategyHostTransferReceiptMatches(
        receipt, transfer, source, bytes, retained,
      ),
    transferPending: moon.strategyHostTransferPending as Runtime['strategyHostTransferPending'],
    transferProgressBegin: (transfer: Transfer): Progress =>
      moon.strategyHostBeginTransferProgress(transfer),
    transferRecordSourceStop: (progress: Progress) =>
      moon.strategyHostRecordTransferSourceStop(progress),
    transferRecordSourceSiteSettlement: (progress: Progress) =>
      moon.strategyHostRecordTransferSourceSiteSettlement(progress),
    transferRecordDestinationCreated: (progress: Progress) =>
      moon.strategyHostRecordTransferDestinationCreated(progress),
    transferRecordDestinationAdmission: (progress: Progress, value: DestinationAdmission) =>
      moon.strategyHostRecordTransferDestinationAdmission(
        progress,
        value.distinctMaterial,
        value.distinctGeneration,
        value.rows,
        value.batches,
        value.maxBatchRows,
        value.maxBatchBytes,
        value.transferredBytes,
        value.retainedBytes,
        value.transferLimit,
        value.retentionLimit,
      ),
    transferRecordDestinationHolding: (progress: Progress) =>
      moon.strategyHostRecordTransferDestinationHolding(progress),
    transferRecordDestinationReclaimed: (progress: Progress) =>
      moon.strategyHostRecordTransferDestinationReclaimed(progress),
    transferRecordDestinationSiteSettlement: (progress: Progress) =>
      moon.strategyHostRecordTransferDestinationSiteSettlement(progress),
    transferRecordDestinationCleanupRelease: (progress: Progress) =>
      moon.strategyHostRecordTransferDestinationCleanupRelease(progress),
    transferRecordSiteHoldingRelease: (progress: Progress) =>
      moon.strategyHostRecordTransferSiteHoldingRelease(progress),
    transferCommitAction: (progress: Progress) => checked(
      moon.strategyHostTransferCommitAction(progress),
    ) as number,
    transferCleanupAction: (progress: Progress) => checked(
      moon.strategyHostTransferCleanupAction(progress),
    ) as number,
    transferReceipt: moon.strategyHostTransferReceipt as Runtime['strategyHostTransferReceipt'],
    explain: (value: unknown, bytes: number, nodes: number) => JSON.parse(checked(moon.strategyHostExplain(value, bytes, nodes)) as string) as unknown,
    preparationUsageIsolated: (value: unknown, holder: unknown) =>
      typeof moon.clientProgramPreparationBorrowUsageIsolated === 'function' &&
      moon.clientProgramPreparationBorrowUsageIsolated(holder, moon.strategyHostRun(value)) === true,
    usage: (value: unknown) => ledgerUsageSnapshot(moon.strategyHostUsage(value)),
  };
}
