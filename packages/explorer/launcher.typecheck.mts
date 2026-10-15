import type {Client} from '@actql/sdk';
import {startExplorer, openLocalExplorer} from './launcher.js';
declare const client: Client;
const borrowed = await startExplorer({client});
await startExplorer({client, launchInput: {kind: 'program', text: 'SELECT 1', format: 'sql'}});
await borrowed.close();
const owned = await openLocalExplorer({local: {stateDir: './state'}});
const state: string = owned.local.stateDir;
await owned.close();
// @ts-expect-error The launcher cannot bind a public interface.
await startExplorer({client, hostname: '0.0.0.0'});
// @ts-expect-error Local ownership is explicit, never another borrowed Client.
await openLocalExplorer({client});
// @ts-expect-error Closing a viewer exposes no Run mutation.
await owned.cancel();
void state;
