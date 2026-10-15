import type {Client, RunReference} from '@actql/sdk';
import type {WireRunView, WireOwnerObservations} from '@actql/client-wire';
import type {ReadTicket} from './read-model.js';
export const runObservationLimits: Readonly<{maxEntries:32;maxWireBytes:65536;maxNodes:10000;maxDepth:64}>;
type Unavailable = Readonly<{state:'unavailable';reason:string}>;
type Run = WireRunView['run_state'];
type Owner = Extract<WireOwnerObservations['owners'][number],{kind:'observed'}>;
type HistoryEntry = Extract<Owner['history'],{kind:'page'}>['entries'][number];
export type RunObservationModel = Readonly<{
  runRef: RunReference; consistency:'non_atomic'; observationScope:'owner_local';
  run: Readonly<{id:string;status:Run['status'];updatedAt:string;controlRevision:number;terminal:boolean;
    stopReason?:Run['stop_reason'];boundary?:Run['boundary'];cleanupPending?:boolean;pausePending?:boolean;expiryPending?:boolean;
    cancellation:Unavailable|Readonly<{state:'observed';requested:boolean;physicalStop:'unknown'|'confirmed'}>}>;
  planBinding:Readonly<{compiledPlanCid:string|null;logicalMapCid:string|null}>;
  components:WireRunView['components'];
  quantities:readonly (Readonly<{kind:'unknown';unit:string;reason:string}>|Readonly<{
    kind:'exact'|'bound'|'estimate';value:string;unit:string;scopeCid:string;basisCid:string}>)[];
  resultAvailability:Unavailable|Readonly<{state:'observed';entries:readonly Readonly<{
    name:string;state:'available'|'unavailable'|'unknown';reason:string;observedAt:string;causeCid?:string}>[]}>;
  histories:Unavailable|Readonly<{state:'observed';consistency:'non_atomic';ordering:'owner_local';
    owners:readonly (Readonly<{owner:string;state:'unavailable';reason:string}>|Readonly<{
      owner:string;state:'observed';ownerRef:Owner['ownerRef'];
      snapshot:Unavailable|Readonly<{state:'observed';cid:string;revision?:number}>;
      history:Unavailable|Readonly<{state:'page';entries:readonly HistoryEntry[];
        head:null|Readonly<{generation:string;revision:number;entryCid:string}>;cursorAvailable:boolean}>}>)[]}>;
  sample:Readonly<{state:WireRunView['sample']['state'];reason?:string}>;
  logicalProgress:Unavailable;elapsed:Unavailable;tokens:Unavailable;cost:Unavailable;preview:Unavailable;
}>;
export function runObservationModel(view:WireRunView,owners:WireOwnerObservations|null,ref:RunReference):RunObservationModel;
export function readRunObservation(client:Pick<Client,'attach'>,ref:RunReference,ticket:ReadTicket):Promise<RunObservationModel>;
