import type {Client,RunReference} from '@actql/sdk';
import {createReadEpoch} from './read-model.js';
import {readRunObservation} from './run-observation.js';
import {RunInspector} from './plan-explorer.js';
declare const client:Client,ref:RunReference;
const model=await readRunObservation(client,ref,createReadEpoch().capture());
const nonAtomic:'non_atomic'=model.consistency;
const unavailable:'unavailable'=model.logicalProgress.state;
RunInspector({model});
// @ts-expect-error A presentation model supplies no execution permission.
model.allow;
// @ts-expect-error The component has no control mutation callback.
RunInspector({model,onResume:()=>{}});
void nonAtomic;void unavailable;
