import type {Client, Execution} from './index.js';
import type {WirePlanView, WireRunView} from '@actql/client-wire';

declare const client: Client;
declare const run: Execution;
const plan: WirePlanView = await client.plan('SELECT 1 AS n', {format: 'sql'});
const view: WireRunView = await run.inspect({maxWireBytes: 65536, maxNodes: 10000, maxDepth: 64});
const consistency: 'non_atomic' = view.consistency;
const pending: boolean | undefined = view.run_state.cleanup_pending;
void plan; void consistency; void pending;
// @ts-expect-error Read-only plan options are not an execution profile.
await client.plan('SELECT 1 AS n', {stopOnEntry: true});
// @ts-expect-error Inspect does not accept a manual resume or Sample request.
await run.inspect({until: 'step', sampleItems: 1});
