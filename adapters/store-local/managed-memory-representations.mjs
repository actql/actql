// Portable registry and scoped access for managed row representations. File
// providers install their own grouped reader; memory-only consumers never load
// Node filesystem or crypto modules.
const representations = new WeakMap();
const issue = code => Object.assign(new Error(code), {code});

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

// Pure support lookup used during candidate preparation. It grants no Store
// access, pins no generation and starts no provider work.
export function managedInputSupportsRows(material) {
  return typeof representations.get(material)?.rowProvider?.read === 'function';
}

// Managed in-memory representation registration. Its physical lifetime stays
// with the installed implementation; this registry only acquires a scoped
// use count and never turns the opaque material into a portable handle.
export function registerManagedMemoryInput(
  material, readable, available, rowProvider, release,
) {
  if (!material || typeof material !== 'object' ||
      representations.has(material) || typeof readable !== 'function' ||
      typeof available !== 'function' || rowProvider === null ||
      typeof rowProvider !== 'object' ||
      typeof rowProvider.read !== 'function' ||
      typeof release !== 'function' || available() !== true) {
    throw issue('InvalidManagedInputRegistration');
  }
  let open = true, readers = 0, released = false;
  let resolveClosed;
  const closed = new Promise(resolve => { resolveClosed = resolve; });
  const finishRelease = () => {
    if (released || open || readers !== 0) return;
    released = true;
    try { release(); }
    finally { resolveClosed(); }
  };
  const held = {
    readable,
    available: () => open && available() === true,
    sourceAvailable: () => available() === true,
    rowProvider,
    memory: true,
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
    },
  };
  installManagedRepresentation(material, held);
  return Object.freeze({
    async close() {
      open = false;
      finishRelease();
      await closed;
    },
    status: () => Object.freeze({open, readers, released}),
  });
}

// Representation-neutral managed row use. Memory generations are pinned in
// this portable module. Installed physical providers retain their own grouped
// read operation so importing the Local connector does not import Node I/O.
export async function withManagedInputRows(
  occurrences, authorize, append, use, signal, beforeRead,
) {
  if (!Array.isArray(occurrences) || occurrences.length === 0 ||
      typeof authorize !== 'function' || typeof append !== 'function' ||
      typeof use !== 'function') {
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
      return await use();
    } finally {
      for (let index = acquired.length - 1; index >= 0; index--) {
        acquired[index].releaseUse();
      }
    }
  }
  if (held.some(value => value.memory === true) ||
      held.some(value => value.rowUse !== held[0].rowUse) ||
      typeof held[0].rowUse !== 'function') {
    throw issue('UnsupportedManagedRowRepresentation');
  }
  return held[0].rowUse(
    occurrences, authorize, append, use, signal, beforeRead,
  );
}
