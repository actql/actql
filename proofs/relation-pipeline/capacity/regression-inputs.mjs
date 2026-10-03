// One invocation owns these read-only inputs. Never retain a validation result:
// every substituted report still traverses the complete capacity validator.
function freeze(value) {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
}

export function prepareCapacityRegressionInputs(original, current, read) {
  // Parsed originals stay private. Each case receives independent mutable
  // clones, including executions, owners and nested source dictionaries.
  const parts = original.parts.map(({ path }) => ({ path, report: JSON.parse(read(path)) }));
  return Object.freeze({
    current: freeze(structuredClone(current)),
    parts: () => structuredClone(parts),
  });
}
