import type {Execution} from './index.d.ts';
import type {WireClientBodyByOperation} from '@actql/client-wire';

declare const run: Execution;
void run.wait({since:0});
void run.wait({since:null, until:'terminal', signal:new AbortController().signal});
// @ts-expect-error A state revision is not a string token.
void run.wait({since:'1'});
// @ts-expect-error A state revision is not an authorization flag.
void run.wait({since:true});
declare const original: Omit<WireClientBodyByOperation['wait'], 'since'>;
const waiting: WireClientBodyByOperation['wait'] = {...original, since:null};
void waiting;
// @ts-expect-error Omission is normalized by the SDK, not accepted on the wire.
const missing: WireClientBodyByOperation['wait'] = original;
void missing;
