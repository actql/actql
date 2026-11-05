// The existing Host Run owns admission and retirement. This view associates
// each real Source preparation with that same parent; it owns no Ledger,
// physical reader, retry engine or replacement cleanup acknowledgement.
export function bindInstalledManagedSources(profile, runFor) {
  if (profile === undefined || typeof profile.prepareManagedRun === 'function') return profile;
  const originals = profile.sources ?? [profile];
  if (!originals.every(source => typeof source.managedCaptureCapacity === 'function')) return profile;
  const sources = originals.map(source => {
    const prepare = source.prepare, capacity = source.ledgerCapacity;
    const captureCapacity = source.managedCaptureCapacity;
    const wholeCapacity = source.managedWholeSourceCapacity;
    if (![prepare, capacity, captureCapacity].every(value => typeof value === 'function')) {
      throw new TypeError('InstalledManagedSourceUnavailable');
    }
    const forwarded = {};
    for (const name of ['open', 'openCapture', 'close', 'admitsSource', 'retainedCapture', 'managedEffectPlanSelection',
      'retirePreparedSource']) {
      const method = source[name];
      if (method !== undefined) {
        if (typeof method !== 'function') throw new TypeError('InstalledManagedSourceUnavailable');
        forwarded[name] = (...args) => Reflect.apply(method, source, args);
      }
    }
    const preparations = new WeakMap();
    return Object.freeze({...source, ...forwarded,
      ...(wholeCapacity === undefined ? {} : {
        managedWholeSourceCapacity(facts) {
          if (typeof wholeCapacity !== 'function') throw new TypeError('InstalledManagedSourceUnavailable');
          return Reflect.apply(wholeCapacity, source, [facts]);
        },
      }),
      managedCaptureCapacity(requirement) {
        return Reflect.apply(captureCapacity, source, [requirement]);
      },
      async prepare(facts) {
        const pure = Object.getOwnPropertyDescriptor(facts, 'preparedProgram');
        const effect = Object.getOwnPropertyDescriptor(facts, 'preparedEffect');
        if (pure !== undefined && effect !== undefined) throw new TypeError('ForeignInstalledManagedSource');
        const field = effect ?? pure;
        const name = effect === undefined ? 'preparedProgram' : 'preparedEffect';
        if (field === undefined || !Object.hasOwn(field, 'value') || field.value === undefined) {
          throw new TypeError('ForeignInstalledManagedSource');
        }
        const checkedPrepared = field.value, parent = runFor(checkedPrepared);
        const forwardedFacts = Object.freeze({...facts, managedRun: parent});
        const prepared = await Reflect.apply(prepare, source, [forwardedFacts]);
        // A cancellation or retirement during preparation cannot publish a
        // new association or upgrade an equal-shaped Source preparation.
        const after = Object.getOwnPropertyDescriptor(facts, name);
        if (after === undefined || !Object.hasOwn(after, 'value') ||
            after.value !== checkedPrepared || runFor(checkedPrepared) !== parent) {
          throw new TypeError('ForeignInstalledManagedSource');
        }
        preparations.set(prepared, Object.freeze({prepared: checkedPrepared, parent}));
        return prepared;
      },
      ledgerCapacity(prepared) {
        const original = preparations.get(prepared);
        if (original === undefined || runFor(original.prepared) !== original.parent) {
          throw new TypeError('ForeignInstalledManagedSource');
        }
        const selected = Reflect.apply(capacity, source, [prepared]);
        return Object.freeze({...selected, managedRun: original.parent});
      },
    });
  });
  if (profile.sources === undefined) return sources[0];
  const forwarded = {};
  for (const name of ['close', 'admitsSource']) {
    const method = profile[name];
    if (method !== undefined) {
      if (typeof method !== 'function') throw new TypeError('InstalledManagedSourceUnavailable');
      forwarded[name] = (...args) => Reflect.apply(method, profile, args);
    }
  }
  return Object.freeze({...profile, ...forwarded, sources: Object.freeze(sources)});
}
