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
