import assert from 'node:assert/strict';

export const retirementModelExecution = Object.freeze({target: 'model', count: 55,
  command: Object.freeze([process.execPath, 'proofs/relation-chain/retirement-check.mjs']),
  summary: 'Checked 55 theorems, expected claim types and axiom dependencies'});
export const retirementFixture = 'src/connectors/local/relation_chain_lifetime_wbtest.mbt';
export const retirementPremises = Object.freeze([
  'pending denotes an accepted completed and stopped intermediate child; not an arbitrary cancel request',
  'child cleanup true confirms execution reclamation; false or error keeps the same execution custody',
  'all chain steps satisfy the reviewed early-retirement eligibility predicate; no conservative family inheritance',
  'accepted output references and checked generations remain separate from execution scratch custody',
  'accepted child and metadata-control work preserves the original productive budget',
]);
export const retirementGuarantees = Object.freeze([
  'every started child retains execution responsibility or a recorded retirement; repeated confirmed retirement is idempotent',
  'cleanup false or error blocks successor creation and preserves accepted intermediate output references',
  'successful intermediate retirement removes execution custody once without removing accepted output references',
  'admitted serial traces have at most one owed child execution; retained output allocations are not included in that count',
  'pending cancellation and terminal cleanup cannot start a successor or reenter Compute',
]);
export const retirementResidual = Object.freeze([
  'finite existing built-in fixtures only; child semantics, identity binding and logical work remain local obligations',
  'one owed execution is not a physical live-allocation or RSS upper bound; retained output/cursor/closure sizing remains unproved',
  'active-child cancellation, delayed stop and arbitrary family callbacks require their own connection claims',
  'no GC completion, universal implementation refinement or all-provider liveness is derived',
]);
const reviewed = Object.freeze({operation: 'builtin-chain/early-retirement', variant: 'accepted-intermediate-cleanup',
  profile: 'eight existing lifetime cases; numeric binding/groups/JOIN/Append and authored Values/UNNEST; completed generations retained',
  length: Object.freeze([2, 3, 4, 6]), stopContract: 'cancel-between-completed-children-preserves-cleanup-custody',
  entrypoint: 'bounded_relation_chain_execution_state',
  provider: 'src/connectors/local/selected_relation_provider.mbt', children: Object.freeze([retirementFixture])});
const clone = value => structuredClone(value);
export const retirementBindings = () => [{...clone(reviewed), premises: [...retirementPremises], residual: [...retirementResidual]}];
export const executedRetirementCoverage = () => ({fixture: retirementFixture, scopes: [clone(reviewed)]});
export const isRetirement = binding => Object.keys(reviewed).every(key =>
  JSON.stringify(binding?.[key]) === JSON.stringify(reviewed[key]));
const names = Object.freeze([
  'built-in chains reclaim each intermediate execution and preserve exact outputs',
  'chain cancellation between reclaimed children does not start the next child',
  'intermediate cleanup false and error preserve child custody until parent retry',
  'cancelling pending intermediate cleanup preserves reclamation custody',
  'unaudited chain steps keep conservative capacity and child custody',
  'Values and UNNEST chains reclaim scratch and preserve accepted output generations',
  'Values and UNNEST cleanup failures retain child custody and retry exactly once',
  'cancellation after reclaimed Values does not start UNNEST or publish unfinished output',
]);

// Connection review is scoped to these existing functions and fixture cases.
// Text guards plus executed finite tests are not a universal refinement proof.
export function checkRetirementConnection(read) {
  const source = read(reviewed.provider);
  const begin = source.indexOf('fn reclaim_relation_chain_child(');
  const end = source.indexOf('fn bounded_relation_chain_execution_state(', begin);
  assert(begin >= 0 && end > begin, 'Missing reviewed retirement owner');
  const compact = value => value.replace(/\/\/[^\n]*/gu, '').replace(/\s+/gu, '');
  const reclaim = compact(source.slice(begin, end));
  assert(reclaim.includes('guardstate.currentisSome(active)&&managed_provider_stopped(active)else'),
    'Missing completed-child physical-stop guard');
  assert(reclaim.includes('matchcleanup_managed_provider(active){Ok(true)=>{state.current=Nonestate.children=[]state.reclaiming=falseOk(true)}result=>result}'),
    'Missing success-only execution retirement and pending custody');
  assert(!reclaim.includes('state.completed='), 'Intermediate retirement clears accepted outputs');
  const route = compact(source.slice(end));
  assert(route.includes('ifcancelled.val&&state.pending{terminal.val=truereturnOk(managed_provider_stopped_poll(0L,0L))}'),
    'Missing scoped pending cancellation');
  assert(route.includes('ifstate.pending{matchreclaim_relation_chain_child(state){Ok(true)=>()Ok(false)=>returnOk(managed_provider_waiting(0L,0L))Err(issue)=>{terminal.val=truereturnOk(managed_provider_failed(issue,0L,0L))}}'),
    'Missing pending reclamation custody before successor admission');
  assert(route.includes('letreclaimed_prefix=relation_chain_reclaimed_prefix(sequence)'),
    'Missing reviewed retirement prefix selection');
  // Keep the all-eligible model scope. The adopted prefix selector is local to
  // the completed position; it does not admit conservative family suffixes.
  assert(route.includes('state.completed[state.position]=Some(output)state.position+=1state.pending=trueletreclaims_scratch=state.position<=reclaimed_prefixifreclaims_scratch{state.reclaiming=truematchreclaim_relation_chain_child(state){Ok(_)=>()Err(issue)=>{terminal.val=truereturnOk(managed_provider_failed(issue,progress,work))}}}else{state.current=None}'),
    'Missing accepted output before intermediate retirement');
  assert(route.includes('state.children.push(next)state.current=Some(next)state.pending=falsestate.input_preparation=None'),
    'Missing conservative successor execution custody');
  assert(route.includes('Ok(false)=>returnOk(false)Err(issue)=>returnErr(issue)'),
    'Missing parent cleanup retry custody');
  const fixture = read(retirementFixture);
  for (const name of names) assert(fixture.includes(`test "${name}"`), 'Missing independently reviewed retirement case');
}
