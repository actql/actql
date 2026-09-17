// Portable registry and scoped access for managed row representations. File
// providers install their own grouped reader; memory-only consumers never load
// Node filesystem or crypto modules.
const representations = new WeakMap();
const issue = code => Object.assign(new Error(code), {code});
const member = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name] : undefined;
  } catch { return undefined; }
};
const cleanupState = handle => {
  if (!handle || typeof member(handle, 'status') !== 'function') {
    return Object.freeze({pending: true, errors: Object.freeze([])});
  }
  try {
    const state = handle.status();
    if (!state || typeof state.pending !== 'boolean') {
      return Object.freeze({pending: true, errors: Object.freeze([])});
    }
    return Object.freeze({
      pending: state.pending,
      errors: Object.freeze(Array.isArray(state.errors) ? [...state.errors] : []),
    });
  } catch (error) {
    return Object.freeze({pending: true, errors: Object.freeze([error])});
  }
};

function memoryUseFailure(reason, acquired) {
  const native = member(reason, 'cleanupHandle');
  if (member(reason, 'cleanupPending') !== true) return undefined;
  let usesReleased = false;
  const diagnostics = [];
  const releaseFailures = [];
  const releaseAll = () => {
    if (usesReleased) return;
    usesReleased = true;
    for (let index = acquired.length - 1; index >= 0; index--) {
      try { acquired[index].releaseUse(); }
      catch (error) { releaseFailures.push(error); }
    }
  };
  const initial = cleanupState(native);
  if (!initial.pending) {
    releaseAll();
    if (releaseFailures.length === 0) return undefined;
  }
  const failure = issue(typeof member(reason, 'code') === 'string'
    ? member(reason, 'code') : 'ManagedInputUseFailed');
  failure.cause = reason;
  failure.primaryFailure = reason;
  failure.cleanupPending = true;
  diagnostics.push(...initial.errors);
  const status = () => {
    const state = usesReleased
      ? Object.freeze({pending: false, errors: Object.freeze([])})
      : cleanupState(native);
    const releaseStates = releaseFailures.map(error =>
      cleanupState(member(error, 'cleanupHandle')));
    return Object.freeze({
      pending: !usesReleased || releaseStates.some(value => value.pending),
      errors: Object.freeze([
        ...diagnostics,
        ...state.errors,
        ...releaseFailures,
        ...releaseStates.flatMap(value => value.errors),
      ]),
    });
  };
  failure.cleanupErrors = status().errors;
  failure.cleanupHandle = Object.freeze({
    status,
    async retry() {
      if (!usesReleased && typeof member(native, 'retry') === 'function') {
        try { await native.retry(); }
        catch (error) { diagnostics.push(error); }
      }
      if (!usesReleased && !cleanupState(native).pending) releaseAll();
      for (const error of releaseFailures) {
        const handle = member(error, 'cleanupHandle');
        if (cleanupState(handle).pending &&
            typeof member(handle, 'retry') === 'function') {
          try { await handle.retry(); }
          catch (retryError) { diagnostics.push(retryError); }
        }
      }
      failure.cleanupErrors = status().errors;
      failure.cleanupPending = status().pending;
      return status();
    },
  });
  return failure;
}

function releaseMemoryUses(acquired, primary) {
  const primaryProvided = arguments.length >= 2;
  const errors = [];
  for (let index = acquired.length - 1; index >= 0; index--) {
    try { acquired[index].releaseUse(); }
    catch (error) { errors.push(error); }
  }
  if (errors.length === 0) return;
  const failure = issue('ManagedInputReleaseFailed');
  const hasReleaseCause = errors[0] !== null &&
    (typeof errors[0] === 'object' || typeof errors[0] === 'function') &&
    Object.hasOwn(errors[0], 'primaryFailure');
  const releaseCause = hasReleaseCause
    ? errors[0].primaryFailure
    : errors[0];
  failure.cause = primaryProvided ? primary : releaseCause;
  failure.primaryFailure = primaryProvided ? primary : releaseCause;
  failure.cleanupErrors = Object.freeze([...errors]);
  const handles = errors.map(error =>
    member(error, 'cleanupPending') === true
      ? member(error, 'cleanupHandle')
      : undefined);
  const status = () => Object.freeze({
    pending: handles.some(handle => cleanupState(handle).pending),
    errors: Object.freeze([
      ...errors,
      ...handles.flatMap(handle => cleanupState(handle).errors),
    ]),
  });
  failure.cleanupPending = status().pending;
  if (failure.cleanupPending) {
    failure.cleanupHandle = Object.freeze({
      status,
      async retry() {
        for (const handle of handles) {
          if (cleanupState(handle).pending &&
              typeof member(handle, 'retry') === 'function') {
            try { await handle.retry(); }
            catch (error) { failure.cleanupErrors = Object.freeze([
              ...failure.cleanupErrors, error,
            ]); }
          }
        }
        failure.cleanupPending = status().pending;
        return status();
      },
    });
  }
  throw failure;
}

export function managedRepresentation(material) {
  return representations.get(material);
}

export function installManagedRepresentation(material, representation) {
  if (!material || typeof material !== 'object' ||
      representations.has(material)) {
    throw issue('InvalidManagedInputRegistration');
  }
  representations.set(material, Object.freeze(representation));
}

export function managedInputCodecContractCid(material) {
  return representations.get(material)?.codecContractCid;
}

export function managedInputPhysicalManifestCid(material) {
  return representations.get(material)?.physicalManifest?.cid;
}

// Pure capacity advertisement for an explicit representation Transfer. These
// are safe upper bounds fixed by the representation owner, not observed usage
// and not permission to acquire the generation.
export function managedInputTransferEstimate(material) {
  const representation = representations.get(material);
  if (!representation) return undefined;
  try {
    if (typeof representation.transferAvailable === 'function' &&
        representation.transferAvailable() !== true) {
      return undefined;
    }
  } catch { return undefined; }
  const estimate = representation.transferEstimate;
  return estimate === undefined ? undefined : Object.freeze({...estimate});
}

// Pure support lookup used during candidate preparation. It grants no Store
// access, pins no generation and starts no provider work.
export function managedInputSupportsRows(material) {
  return typeof representations.get(material)?.rowProvider?.read === 'function';
}

// Managed in-memory representation registration. Its physical lifetime stays
// with the installed implementation; this registry only acquires a scoped
// use count and never turns the opaque material into a portable handle.
export function registerManagedMemoryInput(
  material, readable, available, rowProvider, release, transferEstimate,
) {
  const estimateValid = transferEstimate === undefined ||
    (transferEstimate !== null && typeof transferEstimate === 'object' &&
      [transferEstimate.transferBytes, transferEstimate.retainedBytes,
        transferEstimate.executionBytes].every(value =>
        typeof value === 'bigint' && value >= 0n));
  if (!material || typeof material !== 'object' ||
      representations.has(material) || typeof readable !== 'function' ||
      typeof available !== 'function' || rowProvider === null ||
      typeof rowProvider !== 'object' ||
      typeof rowProvider.read !== 'function' ||
      typeof release !== 'function' || available() !== true ||
      !estimateValid) {
    throw issue('InvalidManagedInputRegistration');
  }
  let open = true, readers = 0, released = false;
  let releaseAttempted = false, releaseFailed = false, releaseFailure;
  const closeWaiters = [];
  const settleCloseWaiters = () => {
    if (!released && !releaseFailed) return;
    while (closeWaiters.length > 0) {
      const waiter = closeWaiters.shift();
      if (released) waiter.resolve();
      else waiter.reject(releaseError());
    }
  };
  const finishRelease = () => {
    if (released || releaseAttempted || open || readers !== 0) return;
    releaseAttempted = true;
    try {
      release();
      released = true;
    } catch (error) {
      releaseFailed = true;
      releaseFailure = error;
    }
    settleCloseWaiters();
  };
  const releaseCleanup = Object.freeze({
    status() {
      if (released) return Object.freeze({pending: false, errors: Object.freeze([])});
      const state = cleanupState(member(releaseFailure, 'cleanupHandle'));
      return Object.freeze({
        pending: true,
        errors: Object.freeze([
          ...(releaseFailed ? [releaseFailure] : []),
          ...state.errors,
        ]),
      });
    },
    async retry() {
      const handle = member(releaseFailure, 'cleanupHandle');
      if (!released && member(releaseFailure, 'cleanupPending') === true &&
          typeof member(handle, 'retry') === 'function') {
        await handle.retry();
        if (!cleanupState(handle).pending) {
          released = true;
          settleCloseWaiters();
        }
      }
      return releaseCleanup.status();
    },
  });
  const releaseError = () => {
    const failure = issue('ManagedInputReleaseFailed');
    failure.cause = releaseFailure;
    failure.primaryFailure = releaseFailure;
    failure.cleanupErrors = releaseCleanup.status().errors;
    failure.cleanupPending = true;
    failure.cleanupHandle = releaseCleanup;
    return failure;
  };
  const held = {
    readable,
    available: () => open && available() === true,
    sourceAvailable: () => available() === true,
    rowProvider,
    memory: true,
    transferAvailable: () => open && available() === true,
    transferEstimate: transferEstimate === undefined
      ? undefined
      : Object.freeze({...transferEstimate}),
    acquire() {
      if (!open || available() !== true) {
        throw issue('ManagedInputUnavailable');
      }
      readers++;
    },
    releaseUse() {
      if (readers < 1) throw issue('InvalidManagedInputUse');
      readers--;
      finishRelease();
      if (releaseFailed && !released) throw releaseError();
    },
  };
  installManagedRepresentation(material, held);
  return Object.freeze({
    async close() {
      open = false;
      finishRelease();
      if (releaseFailed && !released) throw releaseError();
      if (!released) {
        // An admitted reader still owns the generation. Its releaseUse()
        // settles these waiters without polling or granting a new use.
        await new Promise((resolve, reject) => {
          closeWaiters.push({resolve, reject});
          settleCloseWaiters();
        });
      }
    },
    status: () => Object.freeze({
      open,
      readers,
      released,
      releaseRequested: !open,
      releaseAttempted,
      releaseFailed: releaseFailed && !released,
    }),
  });
}

// Representation-neutral managed row use. Memory generations are pinned in
// this portable module. Installed physical providers retain their own grouped
// read operation so importing the Local connector does not import Node I/O.
export async function withManagedInputRows(
  occurrences, authorize, append, use, signal, beforeRead, commit,
) {
  if (!Array.isArray(occurrences) || occurrences.length === 0 ||
      typeof authorize !== 'function' || typeof append !== 'function' ||
      typeof use !== 'function' ||
      (commit !== undefined && typeof commit !== 'function')) {
    throw issue('InvalidManagedInputUse');
  }
  const held = occurrences.map(occurrence =>
    representations.get(occurrence?.material));
  const providers = held.map(value => value?.rowProvider);
  if (providers.some(provider => typeof provider?.read !== 'function')) {
    throw issue('UnsupportedManagedRowRepresentation');
  }
  if (held.every(value => value.memory === true)) {
    const admit = (index, acquired = false) => {
      signal?.throwIfAborted();
      const occurrence = occurrences[index];
      const value = held[index];
      const isAvailable = acquired
        ? value.sourceAvailable() === true
        : value.available() === true;
      if (!isAvailable || occurrence.input == null ||
          value.readable(occurrence.input) !== true ||
          authorize(occurrence.input, index) !== true) {
        throw issue('ManagedInputUnavailable');
      }
    };
    const unique = [...new Set(held)];
    const acquired = [];
    let failed = false;
    try {
      for (const value of unique) {
        value.acquire();
        acquired.push(value);
      }
      for (let index = 0; index < occurrences.length; index++) {
        admit(index, true);
      }
      for (let index = 0; index < providers.length; index++) {
        admit(index, true);
        await providers[index].read(
          undefined,
          row => append(index, row),
          signal,
        );
      }
      for (let index = 0; index < occurrences.length; index++) {
        admit(index, true);
      }
      const provisional = await use();
      for (let index = 0; index < occurrences.length; index++) {
        admit(index, true);
      }
      signal?.throwIfAborted();
      return typeof commit === 'function'
        ? await commit(provisional)
        : provisional;
    } catch (error) {
      failed = true;
      if (member(error, 'cleanupPending') === true) {
        const retained = memoryUseFailure(error, acquired);
        if (retained !== undefined) throw retained;
        throw error;
      }
      releaseMemoryUses(acquired, error);
      throw error;
    } finally {
      if (!failed) releaseMemoryUses(acquired);
    }
  }
  if (held.some(value => value.memory === true) ||
      held.some(value => value.rowUse !== held[0].rowUse) ||
      typeof held[0].rowUse !== 'function') {
    throw issue('UnsupportedManagedRowRepresentation');
  }
  return held[0].rowUse(
    occurrences, authorize, append, use, signal, beforeRead, commit,
  );
}
