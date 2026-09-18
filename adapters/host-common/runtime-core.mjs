import {checked} from './runtime-result.mjs';

const usageKeys = ['planningWork', 'attempts', 'holdings', 'transferredBytes',
  'reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes', 'reservedExecutionBytes'];
const tuplePair = value => Array.isArray(value)
  ? value
  : value !== null && typeof value === 'object'
    ? [value._0, value._1]
    : undefined;
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const resultDefinitionKeys = [
  'program_definition_cid',
  'result_definition_cid',
  'result_name',
  'version',
];
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

function checkedResultDefinition(text, name) {
  let definition;
  try { definition = JSON.parse(text); }
  catch { throw new TypeError('Invalid checked Result Definition'); }
  if (definition === null || typeof definition !== 'object' ||
      Array.isArray(definition) ||
      Object.keys(definition).sort().join('\0') !==
        resultDefinitionKeys.join('\0') ||
      definition.version !== 'actql-result-definition/0.1' ||
      definition.result_name !== name ||
      !cidPattern.test(definition.program_definition_cid) ||
      !cidPattern.test(definition.result_definition_cid)) {
    throw new TypeError('Invalid checked Result Definition');
  }
  return Object.freeze({...definition});
}

// Trusted assembly only. Standard entries bind this to their generated runtime;
// execution requests cannot supply a verifier, SQL or replacement runtime.
export function runtimeCore(moon) {
  return Object.freeze({
    siteControl: siteControl(moon),
    publicationControl: publicationControl(moon),
    count: moon.strategyHostCount,
    programDefinitionCid: moon.strategyHostProgramDefinitionCid,
    resultInventory(value) {
      const names = moon.strategyHostResultNames(value);
      const tasks = moon.strategyHostResultTasks(value);
      const definitions = checked(moon.strategyHostResultDefinitions(value));
      if (!Array.isArray(names) || !Array.isArray(tasks) ||
          !Array.isArray(definitions) || names.length !== tasks.length ||
          names.length !== definitions.length ||
          new Set(names).size !== names.length ||
          names.some(name => typeof name !== 'string' || name.length === 0) ||
          tasks.some(task => !Number.isSafeInteger(task) || task < 0) ||
          definitions.some(body => typeof body !== 'string')) {
        throw new TypeError('Invalid checked Result inventory');
      }
      return Object.freeze(names.map((name, index) => Object.freeze({
        name,
        task: tasks[index],
        definition: checkedResultDefinition(definitions[index], name),
      })));
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
