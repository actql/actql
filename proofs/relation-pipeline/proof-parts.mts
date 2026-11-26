// Reviewed static proof ownership. This module performs no toolchain or runtime
// discovery: changing an assignment changes the canonical sealed plan digest.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
type Role = 'mutations' | 'capacity-normal' | 'capacity-support' | 'capacity-mutants';
type CapacityObligations = {
  normal?: {caseCount: number; targets: string[]};
  boundaries?: {values: number[]; caseCount: number; targets: string[]};
  finalNormal?: {caseCount: number; targets: string[]};
  backingCore?: string[]; backingModel?: boolean; structuralModel?: boolean;
  custody?: {healthy: number; negative: number}; nativeParentStartup?: boolean;
  mutations?: string[]; freshSearch?: string; shrink?: string; replayTargets?: string[];
  healthy?: number; ownerLocalRestoration?: {caseCount: number; targets: string[]};
};
type Part = {family: 'mutations' | 'capacity'; role: Role; job: string; stages: string[];
  variants?: string[]; obligations?: CapacityObligations; modes?: string[]; baseline?: string;
  replayTargets?: string[]; restoration?: string};
type Plan = {version: string; parts: Record<string, Part>; logicalAliases: Record<string, string[]>};

const freeze = <Value,>(value: Value): Value => {
  if (value && typeof value === 'object') { Object.values(value).forEach(freeze); Object.freeze(value); }
  return value;
};
const targets = ['js', 'wasm', 'native'];
const mutation = (job: string, variants: string[]): Part => ({family: 'mutations', role: 'mutations', job,
  stages: ['source', 'baseline', 'mutations'], variants, modes: ['fixed', 'explore'],
  baseline: 'js', replayTargets: targets,
  restoration: 'new-owner-restored-mutable-and-independent-pristine'});
const capacity = (job: string, role: Exclude<Role, 'mutations'>, obligations: CapacityObligations): Part => ({family: 'capacity', role, job,
  stages: ['source', 'capacity', ...(role === 'capacity-normal' ? ['final-normal'] : [])], obligations});
const mutants = (job: string, mutations: string[]) => capacity(job, 'capacity-mutants', {mutations,
  freshSearch: 'js', shrink: 'js', replayTargets: targets,
  healthy: mutations.length * targets.length,
  ownerLocalRestoration: {caseCount: mutations.length, targets}});
export const plan: Plan = freeze<Plan>({
  version: 'actql-pipeline-proof-parts/0.1',
  parts: {
    'L-C2': capacity('pipeline-capacity', 'capacity-normal', {
      normal: {caseCount: 28, targets}, boundaries: {values: [-1, 0, 1], caseCount: 28, targets},
      finalNormal: {caseCount: 114, targets},
    }),
    'L-C3': capacity('pipeline-capacity-support', 'capacity-support', {
      backingCore: targets, backingModel: true, structuralModel: true,
      custody: {healthy: 9, negative: 2}, nativeParentStartup: true,
    }),
    'L-C4': mutants('pipeline-capacity-mutants',
      ['missing-index-reservation', 'premature-keep-release', 'duplicate-index-release']),
    'L-C5': mutants('pipeline-capacity-mutants-rest',
      ['handoff-copy-without-accounting', 'oversized-metadata-map']),
    'L-M2': mutation('pipeline-mutations', ['handoff-wrong-port', 'stable-tie-reversed']),
    'L-M3': mutation('pipeline-mutations-second', ['rename-nullability-widened', 'rename-type-changed']),
    'L-M4': mutation('pipeline-mutations-rest', ['rename-swap-wrong-input', 'distinct-first-column-only']),
    'L-M5': mutation('pipeline-mutations-rest-second', ['distinct-reversed-survivors', 'distinct-handoff-wrong-port']),
  },
  // Logical local commands retain their complete original meaning. An alias
  // is not a hosted fragment and cannot be sealed independently.
  logicalAliases: {
    'L-C0': ['L-C2', 'L-C3'], 'L-C1': ['L-C4', 'L-C5'],
    'L-M0': ['L-M2', 'L-M3'], 'L-M1': ['L-M4', 'L-M5'],
  },
});
export const partIds: string[] = freeze(Object.keys(plan.parts));
export const mutationPartIds: string[] = freeze(partIds.filter(id => plan.parts[id].family === 'mutations'));
export const capacityPartIds: string[] = freeze(partIds.filter(id => plan.parts[id].family === 'capacity'));
export const partJobs: Record<string, string> = freeze(Object.fromEntries(partIds.map(id => [id, plan.parts[id].job])));
export const partStages: Record<string, string[]> = freeze(Object.fromEntries(partIds.map(id => [id, plan.parts[id].stages])));
export const mutationNamesByPart: Record<string, string[]> = freeze(Object.fromEntries(mutationPartIds.map(id => [id, plan.parts[id].variants!])));
export const capacityObligationsByPart: Record<string, CapacityObligations> = freeze(Object.fromEntries(capacityPartIds.map(id => [id, plan.parts[id].obligations!])));
export const logicalMutationNamesByPart: Record<string, string[]> = freeze(Object.fromEntries(Object.entries(plan.logicalAliases)
  .filter(([, ids]) => ids.every(id => plan.parts[id].family === 'mutations'))
  .map(([id, ids]) => [id, ids.flatMap(id => mutationNamesByPart[id])])));
export const logicalCapacityObligationsByPart: Record<string, CapacityObligations> = freeze(Object.fromEntries(Object.entries(plan.logicalAliases)
  .filter(([, ids]) => ids.every(id => plan.parts[id].family === 'capacity'))
  .map(([id, ids]) => {
    const values = ids.map(id => capacityObligationsByPart[id]);
    const mutations = values.flatMap(value => value.mutations ?? []);
    return [id, mutations.length ? {...values[0], mutations,
      healthy: mutations.length * targets.length,
      ownerLocalRestoration: {caseCount: mutations.length, targets}} : Object.assign({}, ...values)];
  })));
export const capacityMutationNames: string[] = freeze(capacityPartIds.flatMap(id => capacityObligationsByPart[id].mutations ?? []));
export const planDigest: string = createHash('sha256').update(JSON.stringify(plan)).digest('hex');
export function partFamily(id: string): Part['family'] {
  assert(partIds.includes(id), `Unknown proof part ${id}`);
  return plan.parts[id].family;
}
export function partRole(id: string): Role {
  partFamily(id);
  return plan.parts[id].role;
}
