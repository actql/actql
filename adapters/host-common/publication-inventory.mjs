import {sealPublicationContract} from './run-publication-contracts.mjs';

const cidPattern = /^sha256:[0-9a-f]{64}$/u;

export class PublicationInventoryError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

const fail = code => {
  throw new PublicationInventoryError(code);
};

// Derive the complete publication inventory from the checked graph snapshot.
// Callers cannot supply, rename, reorder, or omit Result occurrences here.
export function prepareCheckedPublicationInventory(
  programDefinitionCid,
  checkedResults,
) {
  if (!cidPattern.test(programDefinitionCid) ||
      !Array.isArray(checkedResults) || checkedResults.length === 0) {
    fail('InvalidCheckedPublicationInventory');
  }
  const names = new Set();
  const occurrences = checkedResults.map(result => {
    if (result === null || typeof result !== 'object' ||
        typeof result.name !== 'string' || result.name.length === 0 ||
        !Number.isSafeInteger(result.task) || result.task < 0 ||
        names.has(result.name)) {
      fail('InvalidCheckedPublicationInventory');
    }
    names.add(result.name);
    const definition = sealPublicationContract('result_definition', {
      version: 'actql-result-definition/0.1',
      program_definition_cid: programDefinitionCid,
      result_name: result.name,
    });
    return Object.freeze({
      name: result.name,
      task: result.task,
      definition,
    });
  });
  const requestInventory = occurrences.map(({name, definition}) =>
    Object.freeze({
      result_name: name,
      result_definition_cid: definition.result_definition_cid,
    }));
  return Object.freeze({
    programDefinitionCid,
    occurrences: Object.freeze(occurrences),
    requestInventory: Object.freeze(requestInventory),
  });
}
