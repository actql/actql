// Read options and the selected validation method belong to the invocation,
// including a query shortcut that waits for credentials or Run observation.
export function captureReadOptions(options) {
  if (options === null || typeof options !== 'object' &&
      typeof options !== 'function' || Array.isArray(options)) return options;
  // Ordinary property access preserves class, inherited and hidden ceilings.
  return Object.freeze(Object.fromEntries(['signal', 'maxWireBytes',
    'maxRowWireBytes', 'maxRowRetainedValueBytes', 'maxRows',
    'maxRetainedValueBytes', 'maxBatchRows', 'maxBatchRetainedValueBytes']
    .map(name => [name, options[name]])));
}

export function captureResultRead(ClientError, schemaOrOptions, options) {
  const object = schemaOrOptions !== null &&
    ['object', 'function'].includes(typeof schemaOrOptions);
  let typed;
  try { typed = options !== undefined || object && '~standard' in schemaOrOptions; }
  catch { throw new ClientError('InvalidResultSchema'); }
  if (!typed) {
    return Object.freeze({options: captureReadOptions(
      schemaOrOptions === undefined ? {} : schemaOrOptions)});
  }
  let standard, validate;
  try {
    standard = schemaOrOptions?.['~standard'];
    validate = standard?.validate;
    if (standard?.version !== 1 || typeof standard.vendor !== 'string' ||
        typeof validate !== 'function') throw new Error('Invalid standard');
  } catch {
    throw new ClientError('InvalidResultSchema');
  }
  return Object.freeze({options: captureReadOptions(options === undefined ? {} : options),
    validate: value => Reflect.apply(validate, standard, [value])});
}

// Aborting the wait releases the reader owner even if application code returns
// a never-settling Promise. It cannot stop arbitrary JavaScript or its effects.
export function awaitValidation(value, signal) {
  return new Promise((resolve, reject) => {
    const abort = () => { signal.removeEventListener('abort', abort); reject(signal.reason); };
    signal.addEventListener('abort', abort, {once: true});
    if (signal.aborted) abort();
    Promise.resolve(value).then(result => {
      signal.removeEventListener('abort', abort);
      resolve(result);
    }, cause => {
      signal.removeEventListener('abort', abort);
      reject(cause);
    });
  });
}

export function validationOutcome(result) {
  if (result === null || typeof result !== 'object' || Array.isArray(result)) {
    return {kind: 'invalid_result'};
  }
  const issues = result.issues;
  if (issues !== undefined) {
    // Empty issues is still a failure under Standard Schema. Validate the
    // diagnostic shape, but do not serialize outputs, paths or thrown values.
    if (!Array.isArray(issues) || !issues.every(issue => issue !== null &&
        typeof issue === 'object' && typeof issue.message === 'string' &&
        (issue.path === undefined || Array.isArray(issue.path) &&
          issue.path.every(part => ['string', 'number', 'symbol'].includes(typeof part) ||
            part !== null && typeof part === 'object' &&
            ['string', 'number', 'symbol'].includes(typeof part.key))))) {
      return {kind: 'invalid_result'};
    }
    return {kind: 'issues', issues};
  }
  if (!('value' in result)) return {kind: 'invalid_result'};
  // Keep any output, even a Promise/thenable, boxed through async plumbing.
  return {value: result.value};
}
