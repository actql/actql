const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const definitionKeys = [
  'program_definition_cid',
  'result_definition_cid',
  'result_name',
  'version',
];

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
  const definitionCids = new Set();
  const occurrences = checkedResults.map(result => {
    if (result === null || typeof result !== 'object' ||
        typeof result.name !== 'string' || result.name.length === 0 ||
        !Number.isSafeInteger(result.task) || result.task < 0 ||
        names.has(result.name) || result.definition === null ||
        typeof result.definition !== 'object' ||
        Array.isArray(result.definition) ||
        Object.keys(result.definition).sort().join('\0') !==
          definitionKeys.join('\0') ||
        result.definition.version !== 'actql-result-definition/0.1' ||
        result.definition.program_definition_cid !== programDefinitionCid ||
        result.definition.result_name !== result.name ||
        !cidPattern.test(result.definition.result_definition_cid) ||
        definitionCids.has(result.definition.result_definition_cid)) {
      fail('InvalidCheckedPublicationInventory');
    }
    names.add(result.name);
    definitionCids.add(result.definition.result_definition_cid);
    const definition = Object.freeze({...result.definition});
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
