// Export the original checked Serialize completion through the existing
// Result view, physical payload and completed-Run publication owners. This
// adapter borrows completion/custody; it does not issue a Run or hold bytes.
import {storeCompletedResultPublicationPayload} from
  '../host-common/durable-result-payload.mjs';

const yieldToHost = () => new Promise(resolve => setImmediate(resolve));
const issue = code => Object.assign(new Error(code), {code});
const quantity = value => Number.isInteger(value) && value >= 0 && value <= 2147483647;

export function serializationPublicationExecution({moon, core, compiled,
  preparedProgram, generation, contractLimits, remainingWork, chargeWork,
  quantum = 32}) {
  const control = core.contentGenerationControl;
  core.publicationControl.checkClientCompiledRunOwner(compiled, preparedProgram);
  if (compiled.kind !== 'serialization' || typeof remainingWork !== 'function' ||
      typeof chargeWork !== 'function' || !quantity(quantum) || quantum < 1 || quantum > 64) {
    throw new TypeError('InvalidContentPublicationExecution');
  }
  // This also verifies the exact original live generation, not an admitted
  // saved envelope or another Run's equal-identity completion.
  control.completedOutput(compiled, generation);
  const occurrences = Object.freeze(Array.from({
    length: moon.clientProgramResultCount(preparedProgram),
  }, (_, index) => control.resultOccurrence(compiled, preparedProgram, index, contractLimits)));
  return Object.freeze({status: 'host-tasks-completed', resultInventory: occurrences,
    publicationInventory: Object.freeze({occurrences}),
    async storePublicationResult(index, store, publication, signal) {
      if (!Number.isSafeInteger(index) || occurrences[index] === undefined) {
        throw new TypeError('InvalidContentPublicationResult');
      }
      const output = control.completedOutput(compiled, generation);
      const occurrence = control.resultOccurrence(compiled, preparedProgram, index,
        publication.contractLimits);
      const expected = occurrences[index];
      if (occurrence.name !== expected.name || occurrence.task !== expected.task ||
          occurrence.definitionContract.identity !== expected.definitionContract.identity) {
        throw new TypeError('ForeignContentPublicationResult');
      }
      // Reserve this view's workspace on the original Run Ledger before
      // entering this adapter. Its mapper work consumes that same allowance;
      // the existing payload owner enforces its physical export limits.
      signal?.throwIfAborted();
      const selection = control.resultStart(preparedProgram, index, output,
        publication.outputLimits);
      try {
        for (;;) {
          signal?.throwIfAborted();
          const remaining = remainingWork();
          if (!quantity(remaining)) throw new TypeError('InvalidGeneratedContentWorkAllowance');
          if (remaining === 0) throw issue('GeneratedContentWorkLimit');
          const granted = Math.min(quantum, remaining);
          const next = control.resultAdvance(selection, granted);
          if (!quantity(next.work) || next.work > granted || typeof next.ready !== 'boolean') {
            throw issue('InvalidGeneratedContentAdvance');
          }
          if (chargeWork(next.work) !== true) throw issue('GeneratedContentWorkLimit');
          if (next.issue !== undefined) {
            throw Object.assign(issue('GeneratedContentResultFailed'), {cause: next.issue});
          }
          signal?.throwIfAborted();
          if (next.ready) break;
          if (next.work === 0) throw issue('InvalidGeneratedContentAdvance');
          await yieldToHost();
        }
        const stored = await storeCompletedResultPublicationPayload(store,
          core.outputExportControl, undefined, index, publication.outputLimits,
          {control: core.publicationControl, definition: occurrence.definitionContract,
            runDefinition: publication.runDefinition, invocation: publication.invocation,
            retention: publication.retention, evidenceContext: publication.evidenceContext,
            limits: publication.contractLimits}, signal, () => control.resultFinish(selection),
          async (handle, exportSignal) => {
            for (;;) {
              exportSignal?.throwIfAborted();
              const remaining = remainingWork();
              if (!quantity(remaining)) throw new TypeError('InvalidGeneratedContentWorkAllowance');
              if (remaining === 0) {
                // Exhausted input requires no new transition. Observe that
                // original cursor, not a speculative positive-work poll.
                if (core.outputExportControl.rowsComplete(handle)) return undefined;
                throw issue('GeneratedContentWorkLimit');
              }
              const granted = Math.min(quantum, remaining);
              const next = core.outputExportControl.advance(handle, granted);
              if (!quantity(next.work) || next.work > granted ||
                  typeof next.complete !== 'boolean' ||
                  next.batch !== undefined && typeof next.batch !== 'string') {
                throw issue('InvalidGeneratedContentAdvance');
              }
              // A failed frame may already have consumed traversal work. The
              // same original Run allowance sees it before failure cleanup.
              if (chargeWork(next.work) !== true) throw issue('GeneratedContentWorkLimit');
              if (next.issue !== undefined) {
                throw Object.assign(issue('GeneratedContentResultFailed'), {cause: next.issue});
              }
              exportSignal?.throwIfAborted();
              if (next.batch !== undefined) return next.batch;
              if (next.complete) return undefined;
              if (next.work === 0) throw issue('InvalidGeneratedContentAdvance');
              await yieldToHost();
            }
          });
        return Object.freeze({...stored, occurrence: Object.freeze({name: occurrence.name,
          task: occurrence.task, definition: occurrence.definitionContract})});
      } finally { control.resultCancel(selection); }
    }});
}
