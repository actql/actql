// Project the checked INFER Result selections into the existing completed-Run
// publisher. The common Invocation binding retains the real completed output;
// this adapter neither creates a completion nor serializes semantic evidence.
import {storeCompletedResultPublicationPayload} from
  '../host-common/durable-result-payload.mjs';
import {localContractLimits} from './local-values-plan.mjs';
import {checked} from '../host-common/runtime-result.mjs';

export function inferPublicationExecution({moon, core, operation, binding,
  compiled, preparedProgram}) {
  const control = core.publicationControl;
  control.checkClientCompiledRunOwner(compiled, preparedProgram);
  if (compiled.kind !== 'infer' || typeof operation?.withResult !== 'function') {
    throw new TypeError('InvalidInferPublicationExecution');
  }
  const occurrences = Object.freeze(Array.from({
    length: moon.clientProgramResultCount(preparedProgram),
  }, (_, index) => {
    // Direct Results have no optional compiled transformation. The existing
    // binding-owned selection covers both direct and transformed Results.
    const owner = checked(moon.clientProgramInferPublicationBegin(binding, index));
    try {
      const selection = moon.clientProgramInferPublicationSelection(owner);
      const definitionContract = control.admit('result_definition',
        moon.strategyPublicationContractJson(
          moon.clientProgramInferResultDefinition(selection)), localContractLimits);
      const name = moon.clientProgramInferResultName(selection);
      const definition = JSON.parse(definitionContract.wire);
      if (name !== moon.clientProgramResultName(preparedProgram, index) ||
          definition.program_definition_cid !==
            moon.clientProgramDefinitionCid(preparedProgram)) {
        throw new TypeError('ForeignInferPublicationResult');
      }
      return Object.freeze({name,
        task: moon.clientProgramInferResultTask(selection), definitionContract});
    } finally {
      moon.clientProgramInferPublicationRelease(owner);
    }
  }));
  return Object.freeze({status: 'host-tasks-completed',
    resultInventory: occurrences,
    publicationInventory: Object.freeze({occurrences}),
    async storePublicationResult(index, store, publication, signal) {
      if (!Number.isSafeInteger(index) || occurrences[index] === undefined) {
        throw new TypeError('InvalidInferPublicationResult');
      }
      const occurrence = occurrences[index];
      return operation.withResult(binding, index, async ({selection, storeExport}) => {
        const definition = control.admit('result_definition',
          moon.strategyPublicationContractJson(
            moon.clientProgramInferResultDefinition(selection)),
          publication.contractLimits);
        if (definition.identity !== occurrence.definitionContract.identity ||
            moon.clientProgramInferResultName(selection) !== occurrence.name ||
            moon.clientProgramInferResultTask(selection) !== occurrence.task) {
          throw new TypeError('ForeignInferPublicationResult');
        }
        const stored = await storeCompletedResultPublicationPayload(store,
          core.outputExportControl, undefined, index, publication.outputLimits,
          {control, definition, runDefinition: publication.runDefinition,
            invocation: publication.invocation, retention: publication.retention,
            evidenceContext: publication.evidenceContext,
            limits: publication.contractLimits}, signal, storeExport);
        return Object.freeze({...stored, occurrence: Object.freeze({
          name: occurrence.name, task: occurrence.task, definition})});
      }, signal);
    },
  });
}
