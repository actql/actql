import type {Client, RunReference} from '@actql/sdk';
import {createReadEpoch, describeExistingResult, readExistingRun, readStaticPlan} from './read-model.js';
declare const client: Client;
declare const ref: RunReference;
const ticket = createReadEpoch().capture();
const plan = await readStaticPlan(client, 'SELECT 1 AS n', {format: 'sql'}, ticket);
const zero: 0 = plan.providerIO;
const run = await readExistingRun(client, ref, ticket);
const nonAtomic: 'non_atomic' = run.consistency;
await describeExistingResult(client, ref, 'answer', ticket);
// @ts-expect-error A static read does not install a control profile.
await readStaticPlan(client, {}, {stopOnEntry: true}, ticket);
void zero; void nonAtomic;
