import {analyticOffsetCapacity} from './analytic-offset-source-input.mjs';

// These are installed acceptance ceilings, not observed input sizes or Host
// defaults. Preserve each corpus's declared envelope and the execution budget.
export const analyticPropertyCapacity = Object.freeze({
  max_analytic_frame_memberships: 10000,
  max_analytic_input_wire_bytes: 10000,
  max_analytic_output_wire_bytes: 10000,
  max_analytic_partition_wire_bytes: 10000,
});
const profiles = new Map([
  ['standard', analyticPropertyCapacity],
  ['analytic-property', analyticPropertyCapacity],
  ['analytic-offset', analyticOffsetCapacity],
]);

// A Host cannot change its installation profile between requests. Partition
// fixtures before creating Hosts so a wider corpus never replaces a narrower
// corpus's limits. Each case, including refusals and failures, runs once.
export function publicQueryProfiles(inputs) {
  const groups = new Map();
  for (const kind of ['successes', 'refusals', 'executionFailures']) {
    for (const item of inputs[kind] ?? []) {
      const name = item.hostProfile ?? 'standard';
      const capacity = profiles.get(name);
      if (capacity === undefined) throw new Error(`Unknown public query profile: ${name}`);
      if (!groups.has(name)) groups.set(name, {name, capacity,
        inputs: {successes: [], refusals: [], executionFailures: []}});
      groups.get(name).inputs[kind].push(item);
    }
  }
  return [...groups.values()];
}
