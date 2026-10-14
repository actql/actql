import type {Client, RunReference} from '@actql/sdk';
import {createExplorerGateway, startExplorerGateway} from './gateway.js';
import {createExplorerBrowserSource} from './browser-source.js';
declare const client: Client;
declare const ref: RunReference;
const gateway = createExplorerGateway({client, origin: 'http://127.0.0.1:43210'});
const server = await startExplorerGateway({client});
const browser = createExplorerBrowserSource({origin: server.origin});
await browser.connect(gateway.issueBootstrap().bootstrap);
const plan = await browser.plan('SELECT 1 AS n', {format: 'sql', maxNodes: 10});
const noProviderIO: 0 = plan.providerIO;
const view = await browser.inspect(ref);
const notAtomic: 'non_atomic' = view.consistency;
const original = await browser.runPlan(ref);
const boundReference: RunReference = original.runRef;
await browser.describe(ref, 'answer');
// @ts-expect-error The launcher owns no Run cancellation operation.
await server.cancel(ref);
// @ts-expect-error This transport cannot read a Result payload or allocate a grant.
await browser.rows(ref, 'answer');
// @ts-expect-error No implicit public bind is allowed.
await startExplorerGateway({client, hostname: '0.0.0.0'});
void noProviderIO; void notAtomic;
void boundReference;
