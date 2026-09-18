import {checked} from './runtime-result.mjs';

const usageKeys = ['planningWork', 'attempts', 'holdings', 'transferredBytes',
  'reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes', 'reservedExecutionBytes'];
const tuplePair = value => Array.isArray(value)
  ? value
  : value !== null && typeof value === 'object'
    ? [value._0, value._1]
    : undefined;
const siteControls = new WeakMap();
const publicationControls = new WeakMap();

function siteControl(moon) {
  let control = siteControls.get(moon);
  if (control !== undefined) return control;
  control = Object.freeze({
    create: configuration => moon.strategySiteCreate(
      configuration.key,
      configuration.generation,
      configuration.runtimeRevision,
      configuration.maxConcurrentOperations,
      configuration.maxConcurrentTransfers,
      configuration.maxRetainedBytes,
      configuration.maxExecutionBytes,
    ),
    available: moon.strategySiteAvailable,
    revoked: moon.strategySiteRevoked,
    capacitySupports: moon.strategySiteCapacitySupports,
    bindingCurrent: moon.strategySiteBindingCurrent,
    startOperation: moon.strategySiteStartOperation,
    operationAvailable: moon.strategySiteOperationAvailable,
    settleOperation: moon.strategySiteSettleOperation,
    retainOperationHolding: moon.strategySiteRetainOperationHolding,
    startTransfer: moon.strategySiteStartTransfer,
    transferAvailable: moon.strategySiteTransferAvailable,
    settleTransferSource: moon.strategySiteSettleTransferSource,
    settleTransferDestination: moon.strategySiteSettleTransferDestination,
    retainTransferHolding: moon.strategySiteRetainTransferHolding,
    retainHolding: moon.strategySiteRetainHolding,
    releaseHolding: moon.strategySiteReleaseHolding,
    retainCleanup: moon.strategySiteRetainCleanup,
    releaseCleanup: moon.strategySiteReleaseCleanup,
    beginTeardown: moon.strategySiteBeginTeardown,
    revoke: moon.strategySiteRevoke,
    status: moon.strategySiteStatus,
  });
  siteControls.set(moon, control);
  return control;
}

function publicationControl(moon) {
  let control = publicationControls.get(moon);
  if (control !== undefined) return control;
  const tokens = new WeakMap();
  const inspect = contract => {
    const value = Object.freeze({
      name: moon.strategyPublicationContractName(contract),
      identityField: moon.strategyPublicationContractIdentityField(contract),
      identity: moon.strategyPublicationContractIdentity(contract),
      wire: moon.strategyPublicationContractJson(contract),
    });
    tokens.set(value, contract);
    return value;
  };
  const token = value => {
    const result = tokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign publication contract');
    }
    return result;
  };
  control = Object.freeze({
    seal(name, bodyWire, limits) {
      return inspect(checked(moon.strategyPublicationSeal(
        name,
        bodyWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admit(name, completeWire, limits) {
      return inspect(checked(moon.strategyPublicationAdmit(
        name,
        completeWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    recordTransition(previous, next, uncommittedConfirmed) {
      return moon.strategyPublicationRecordTransition(
        previous === undefined ? undefined : token(previous),
        token(next),
        uncommittedConfirmed,
      );
    },
    recordAllowsCommit(record) {
      return moon.strategyPublicationRecordAllowsCommit(token(record));
    },
    runChainValid(runDefinition, invocation, definitions, artifacts,
      manifest, limits) {
      return moon.strategyRunPublicationChainValid(
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        token(manifest),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      );
    },
    effectFreeChainValid(runDefinition, invocation, definitions, artifacts,
      manifest, receipt, capturedRun, limits) {
      return moon.strategyEffectFreeRunEvidenceChainValid(
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        token(manifest),
        token(receipt),
        token(capturedRun),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      );
    },
    effectFreeCommitValid(runDefinition, invocation, definitions, artifacts,
      derivations, orderings, retentions, manifest, receipt, capturedRun,
      request, attempt, indexEntry, limits) {
      return moon.strategyEffectFreePublicationCommitValid(
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        derivations.map(token),
        orderings.map(token),
        retentions.map(token),
        token(manifest),
        token(receipt),
        token(capturedRun),
        token(request),
        token(attempt),
        token(indexEntry),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      );
    },
    deliveryTransition(previous, next) {
      return moon.strategyDeliveryRecordTransition(
        previous === undefined ? undefined : token(previous),
        token(next),
      );
    },
  });
  publicationControls.set(moon, control);
  return control;
}

function outputExportControl(moon) {
  const fields = [
    'maxRows',
    'maxValueNodes',
    'maxValueTextBytes',
    'maxValueDepth',
    'maxValueWork',
    'maxWireBytes',
    'maxWireNodes',
    'maxWireDepth',
    'maxColumns',
    'maxOrderWork',
    'maxLogicalWireBytes',
    'maxLogicalWireNodes',
    'maxLogicalWireDepth',
    'maxSchemaFields',
    'maxSchemaBytes',
    'maxSchemaNodes',
    'maxSchemaDepth',
    'maxBatchBytes',
  ];
  const resultFields = [
    'maxResultFields',
    'maxResultMappingWork',
    'maxResultOrderWork',
    'maxResultWorkspaceEntries',
    ...fields,
  ];
  const validLimits = (limits, expected) =>
    limits !== null && typeof limits === 'object' &&
    Object.keys(limits).sort().join('\0') ===
      [...expected].sort().join('\0') &&
    expected.every(name => Number.isSafeInteger(limits[name]) &&
      limits[name] >= 0);
  return Object.freeze({
    begin(output, limits) {
      if (!validLimits(limits, fields)) {
        throw new TypeError('Invalid output export limits');
      }
      return checked(moon.strategyHostOutputExportBegin(
        output,
        limits.maxRows,
        limits.maxValueNodes,
        limits.maxValueTextBytes,
        limits.maxValueDepth,
        limits.maxValueWork,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxColumns,
        limits.maxOrderWork,
        limits.maxLogicalWireBytes,
        limits.maxLogicalWireNodes,
        limits.maxLogicalWireDepth,
        limits.maxSchemaFields,
        limits.maxSchemaBytes,
        limits.maxSchemaNodes,
        limits.maxSchemaDepth,
        limits.maxBatchBytes,
      ));
    },
    beginResult(host, result, limits) {
      if (!Number.isSafeInteger(result) || result < 0 ||
          !validLimits(limits, resultFields)) {
        throw new TypeError('Invalid Result output export request');
      }
      return checked(moon.strategyHostResultOutputExportBegin(
        host,
        result,
        limits.maxResultFields,
        limits.maxResultMappingWork,
        limits.maxResultOrderWork,
        limits.maxResultWorkspaceEntries,
        limits.maxRows,
        limits.maxValueNodes,
        limits.maxValueTextBytes,
        limits.maxValueDepth,
        limits.maxValueWork,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxColumns,
        limits.maxOrderWork,
        limits.maxLogicalWireBytes,
        limits.maxLogicalWireNodes,
        limits.maxLogicalWireDepth,
        limits.maxSchemaFields,
        limits.maxSchemaBytes,
        limits.maxSchemaNodes,
        limits.maxSchemaDepth,
        limits.maxBatchBytes,
      ));
    },
    next: value => checked(moon.strategyHostOutputExportNext(value)),
    finish: value => checked(moon.strategyHostOutputExportFinish(value)),
    identity(value) {
      return Object.freeze({
        orderedRowsCid: checked(moon.strategyHostOutputExportCid(value)),
        logicalRelationCid:
          checked(moon.strategyHostOutputExportLogicalRelationCid(value)),
        resultSchemaCid:
          checked(moon.strategyHostOutputExportResultSchemaCid(value)),
        bytes: checked(moon.strategyHostOutputExportBytes(value)),
        nodes: checked(moon.strategyHostOutputExportNodes(value)),
        rows: checked(moon.strategyHostOutputExportRows(value)),
        schemaBytes: checked(
          moon.strategyHostOutputExportSchemaBytes(value),
        ),
        schemaNodes: checked(
          moon.strategyHostOutputExportSchemaNodes(value),
        ),
        schemaFields: checked(
          moon.strategyHostOutputExportSchemaFields(value),
        ),
      });
    },
    cancel: moon.strategyHostOutputExportCancel,
  });
}

// Trusted assembly only. Standard entries bind this to their generated runtime;
// execution requests cannot supply a verifier, SQL or replacement runtime.
export function runtimeCore(moon) {
  return Object.freeze({
    siteControl: siteControl(moon),
    publicationControl: publicationControl(moon),
    outputExportControl: outputExportControl(moon),
    count: moon.strategyHostCount,
    programDefinitionCid: moon.strategyHostProgramDefinitionCid,
    resultInventory(value) {
      const names = moon.strategyHostResultNames(value);
      if (!Array.isArray(names)) throw new TypeError('Invalid Result inventory');
      if (names.length === 0) return Object.freeze([]);
      const inventory = checked(moon.strategyHostPublicationInventory(value));
      const count = moon.strategyHostPublicationInventoryCount(inventory);
      if (count !== names.length) {
        throw new TypeError('Invalid Result inventory projection');
      }
      return Object.freeze(Array.from({length: count}, (_, index) => {
        const definition = JSON.parse(checked(
          moon.strategyHostPublicationInventoryDefinitionJson(inventory, index),
        ));
        return Object.freeze({
          name: checked(
            moon.strategyHostPublicationInventoryName(inventory, index),
          ),
          task: checked(
            moon.strategyHostPublicationInventoryTask(inventory, index),
          ),
          definition: Object.freeze(definition),
        });
      }));
    },
    next: value => checked(moon.strategyHostNext(value)),
    nextTask: moon.strategyHostNextTask,
    managedProducer: moon.strategyHostManagedProducer,
    managedProducers: moon.strategyHostManagedProducers,
    managedMatches: moon.strategyHostManagedOutputMatches,
    managedInputMatches: moon.strategyHostManagedInputMatchesMaterial,
    selectManaged: moon.strategyHostSelectManagedRegistration,
    task: moon.strategyHostTask,
    taskCapacity: (value, task) => tuplePair(checked(
      moon.strategyHostTaskCapacity(value, task),
    )),
    registration: moon.strategyHostRegistration,
    completed: moon.strategyHostTaskCompleted,
    finished: moon.strategyHostFinished,
    stop: moon.strategyHostStop,
    closeOutputs: moon.strategyHostCloseOutputs,
    output: moon.strategyHostOutput,
    transferBegin: (value, source, transfer, retained, execution) => checked(
      moon.strategyHostTransferBegin(
        value, source, transfer, retained, execution,
      ),
    ),
    transferCharge: (value, transfer, bytes) => checked(
      moon.strategyHostTransferCharge(value, transfer, bytes),
    ),
    transferSettle: (value, transfer, confirmed) => checked(
      moon.strategyHostTransferSettle(value, transfer, confirmed),
    ),
    transferComplete: (value, transfer, retained) => checked(
      moon.strategyHostTransferComplete(value, transfer, retained),
    ),
    transferAbort: (value, transfer, confirmed) => checked(
      moon.strategyHostTransferAbort(value, transfer, confirmed),
    ),
    transferRelease: (value, receipt) => checked(
      moon.strategyHostTransferRelease(value, receipt),
    ),
    transferPending: moon.strategyHostTransferPending,
    transferReceipt: moon.strategyHostTransferReceipt,
    explain: (value, bytes, nodes) => JSON.parse(checked(moon.strategyHostExplain(value, bytes, nodes))),
    usage: value => Object.freeze(Object.fromEntries(
      moon.strategyHostUsage(value).map((count, index) => [usageKeys[index], count]),
    )),
  });
}
