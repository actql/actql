import type {Client, Execution} from './index.js';
import type {WireEffectfulStaticPlanView, WirePlanView, WireRunView, WireRunPlanView, WireRunExplanationView, WireRunExplanationContextView} from '@actql/client-wire';

declare const client: Client;
declare const run: Execution;
const plan: WirePlanView | WireEffectfulStaticPlanView = await client.plan('SELECT 1 AS n', {format: 'sql'});
const view: WireRunView = await run.inspect({maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64});
const consistency: 'non_atomic' = view.consistency;
const pending: boolean | undefined = view.run_state.cleanup_pending;
void plan; void consistency; void pending;
// @ts-expect-error Read-only plan options are not an execution profile.
await client.plan('SELECT 1 AS n', {stopOnEntry: true});
// @ts-expect-error Inspect does not accept a manual resume or Sample request.
await run.inspect({until: 'step', sampleItems: 1});

const original: WireRunPlanView = await run.plan({maxWireBytes: 65536});
void original.run_ref; void original.plan_view.logical_map;
// @ts-expect-error Original map reads do not admit execution or Sample options.
await run.plan({until: 'step'});

if (plan.version === "actql-effectful-static-plan-view/0.1") {
  const scope: "computation_component" = plan.computation.scope;
  const permission: "unknown" = plan.observations.permission.state;
  void scope; void permission;
}

const facts: WireRunExplanationView = await run.explain({signal: AbortSignal.timeout(1000),
  maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64});
void facts.run_ref; void facts.explanation;
// @ts-expect-error Structural explanation does not accept disclosure or Sample options.
await run.explain({rawLiterals: true, sampleItems: 1});

const savedContext: WireRunExplanationContextView = await run.explainContext({maxWireBytes: 65536});
if (savedContext.explanation.state === 'projected') {
  const originalPlan: WirePlanView = savedContext.explanation.view.plan;
  void originalPlan;
}
// @ts-expect-error Saved Context belongs to an attached Execution.
await client.explainContext();
// @ts-expect-error A Context read cannot reacquire or execute a Source.
await run.explainContext({reconstruct: true});
