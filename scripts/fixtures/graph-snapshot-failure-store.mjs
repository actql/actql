// Controlled physical failures of an actual retained Store. No completion,
// publication, accounting, or Run evidence is manufactured by this fixture.
export function graphSnapshotFailureStore({createStore, targetKey, failure}) {
  if (typeof createStore !== 'function' || typeof targetKey !== 'string' ||
      !['append', 'seal'].includes(failure)) throw new TypeError('InvalidSnapshotFailureFixture');
  const leases = [];
  let allowCleanup = false;
  let failedAppends = 0, lostSeals = 0, refusedCleanups = 0;
  return Object.freeze({
    leases,
    counts: () => ({failedAppends, lostSeals, refusedCleanups}),
    permitCleanup: () => { allowCleanup = true; },
    async factory({key, bytes, frame, parentDirectory}) {
      const physical = await createStore({parentDirectory, capacityBytes: bytes,
        maxFrameBytes: frame, maxEntries: 1});
      const targeted = key === targetKey;
      const record = {key, physical, writers: [], sealed: []};
      leases.push(record);
      if (!targeted) return physical;
      return Object.freeze({
        status: () => physical.status(),
        reserve(maximum) {
          const writer = physical.reserve(maximum);
          record.writers.push(writer);
          if (!targeted) return writer;
          return Object.freeze({
            start: () => writer.start(),
            async append(part) {
              if (failure === 'append') {
                failedAppends++;
                throw new Error('InjectedGraphSnapshotAppendFailure');
              }
              return writer.append(part);
            },
            async seal(identity) {
              // Lose the acknowledgement only after a real sealed body exists.
              const body = await writer.seal(identity);
              record.sealed.push(body);
              lostSeals++;
              throw new Error('InjectedGraphSnapshotSealAcknowledgementLost');
            },
          });
        },
        close: () => physical.close(),
        async cleanup() {
          if (targeted && !allowCleanup) {
            refusedCleanups++;
            throw new Error('InjectedGraphSnapshotCleanupPending');
          }
          return physical.cleanup();
        },
      });
    },
    async reclaim() {
      allowCleanup = true;
      for (const {physical} of leases) {
        physical.close();
        await physical.cleanup();
      }
    },
  });
}
