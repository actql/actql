import type {Client, RunReference} from '@actql/sdk';
import {createReadEpoch, describeExistingResult, planStoryModel, readExistingRun, readExistingRunPlan, readExistingRunStory, readStaticPlan} from './read-model.js';
import type {WirePlanView} from '@actql/client-wire';
declare const originalView: WirePlanView;
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
const savedStory = await readExistingRunStory(client, ref, {locale: 'ja'}, ticket);
const sameStoryRef: RunReference = savedStory.runRef;
const staticOriginal: 'static' = original.plan.observation;
await describeExistingResult(client, ref, 'answer', ticket);
// @ts-expect-error A static read does not install a control profile.
await readStaticPlan(client, {}, {stopOnEntry: true}, ticket);
void zero; void nonAtomic;
void originalRef; void staticOriginal;
void sameStoryRef;
