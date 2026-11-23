// One installed module original for invocation computation data. The selected
// Host still owns startup/currentness and complete pre-use facility coverage;
// this sampler issues neither authority nor physical resource admission.
const QueryClockDate = Date;
const queryClockIso = Date.prototype.toISOString;
const queryClockApply = Reflect.apply;

export const sampleOriginalQueryTime = (): string =>
  queryClockApply(queryClockIso, new QueryClockDate(), []);
