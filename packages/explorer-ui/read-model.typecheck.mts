import type {Client, RunReference} from '@actql/sdk';
import {createReadEpoch, describeExistingResult, explanationStoryModel, planStoryModel, readExistingRun, readExistingRunPlan, readExistingRunExplanation, readExistingRunStory, readStaticPlan} from './read-model.js';
import type {WirePlanView, WireExplanationFacts, WireRunExplanationView} from '@actql/client-wire';
declare const structuralFacts: WireExplanationFacts;
declare const savedExplanation: WireRunExplanationView;
const structuralOnly: 'structural' = structuralFacts.disclosure;
if (savedExplanation.explanation.state === 'projected') {
  const boundPlan: string = savedExplanation.explanation.facts.compiled_plan_cid;
  void boundPlan;
}
type FilterMeaning = Extract<WireExplanationFacts['steps'][number]['meaning'], {kind: 'filter'}>;
type ProjectedPredicate = Extract<FilterMeaning['predicate'], {state: 'projected'}>;
type RedactedLiteral = Extract<ProjectedPredicate['nodes'][number], {form: 'literal_redacted'}>;
const redacted: RedactedLiteral = {form: 'literal_redacted',
  type: {projection: 'shape_and_nullability', kind: 'string', nullable: false}};
// @ts-expect-error Literal values are outside the first public profile.
const literalLeak: RedactedLiteral = {...redacted, value: 'private'};
// @ts-expect-error Inferred Text bounds must not disclose a literal's length.
const lengthLeak: RedactedLiteral['type'] = {...redacted.type, max_utf8_bytes: 7};
// @ts-expect-error Retention absence cannot carry reconstructed facts.
const repaired: WireRunExplanationView['explanation'] = {state: 'not_projected', reason: 'not_retained', facts: structuralFacts};
void structuralOnly; void literalLeak; void lengthLeak; void repaired;
declare const originalView: WirePlanView;
const explained = explanationStoryModel(originalView, structuralFacts, {locale: 'ja'});
const originalFactsCid: string = explained.factsCid;
const originalMeaning: WireExplanationFacts['steps'][number]['meaning'] = explained.occurrences[0].explanation.meaning;
// @ts-expect-error Structural explanation text is not an execution/control fact.
const executionConfirmed: true = explained.occurrences[0].explanation.executed;
void originalFactsCid; void originalMeaning; void executionConfirmed;
const story = planStoryModel(originalView, {locale: 'ja'});
const logicalOrder: 'logical_dependencies' = story.ordering.kind;
const storyStatic: 'static' = story.observation;
// @ts-expect-error Locale selection does not install a runtime control profile.
planStoryModel(originalView, {locale: 'ja', stopOnEntry: true});
// @ts-expect-error Unsupported languages are not silently given another locale.
planStoryModel(originalView, {locale: 'fr'});
void logicalOrder; void storyStatic;
declare const client: Client;
declare const ref: RunReference;
const ticket = createReadEpoch().capture();
const plan = await readStaticPlan(client, 'SELECT 1 AS n', {format: 'sql'}, ticket);
const zero: 0 = plan.providerIO;
const run = await readExistingRun(client, ref, ticket);
const nonAtomic: 'non_atomic' = run.consistency;
const original = await readExistingRunPlan(client, ref, ticket);
const originalRef: RunReference = original.runRef;
const retainedExplanation: WireRunExplanationView = await readExistingRunExplanation(client, ref, ticket);
const explanationRef: RunReference = retainedExplanation.run_ref;
// @ts-expect-error Reading absent original Facts does not expose a repair operation.
await readExistingRunExplanation(client, ref, ticket, {recompile: true});
void explanationRef;
const savedStory = await readExistingRunStory(client, ref, {locale: 'ja'}, ticket);
const sameStoryRef: RunReference = savedStory.runRef;
const staticOriginal: 'static' = original.plan.observation;
await describeExistingResult(client, ref, 'answer', ticket);
// @ts-expect-error A static read does not install a control profile.
await readStaticPlan(client, {}, {stopOnEntry: true}, ticket);
void zero; void nonAtomic;
void originalRef; void staticOriginal;
void sameStoryRef;
