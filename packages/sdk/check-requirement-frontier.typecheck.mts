import {createCheckSupplementationSession, getCheckRequirementFrontier,
  equalCheckRequirementFrontiers, type Client, type CheckOutcome} from '@actql/sdk';

declare const client: Client;
declare const outcome: CheckOutcome;
const frontier = getCheckRequirementFrontier(outcome);
if (frontier) {
  const context: string = frontier.contextRef;
  const scope: 'bound_input' = frontier.scope.kind;
  void context; void scope;
  for (const requirement of frontier.requirements) {
    const parameter: string = requirement.facts.parameter;
    const expectedType: string = requirement.facts.expected_type;
    void parameter; void expectedType;
    // @ts-expect-error Missing input has no fabricated actual supplied type.
    requirement.facts.actual_type;
    // @ts-expect-error Locations are presentation, not obligation equality keys.
    requirement.location;
  }
  // @ts-expect-error A known frontier is an immutable observation.
  frontier.requirements.push({code: 'parameter_value_required'});
  // @ts-expect-error A frontier supplies no execution permission.
  frontier.verified;
}
const equal: boolean | undefined = equalCheckRequirementFrontiers(outcome, outcome);
void equal;
const session = createCheckSupplementationSession(client, {maxAttempts: 3});
const result = await session.check('SELECT @x', {format: 'sql', parameters: {x: 1}});
if (result.decision.kind === 'stop') {
  const reason: 'frontier_unavailable' | 'no_known_supplement' | 'unchanged_frontier' |
    'attempt_budget' = result.decision.reason;
  void reason;
}
// @ts-expect-error Attempt bounds do not expose an authoritative supplementation write.
session.supplement({fulfilled: true});
// @ts-expect-error The local session cannot execute a Program.
session.submit('SELECT 1');
// @ts-expect-error The attempt cap must be supplied explicitly.
createCheckSupplementationSession(client);
