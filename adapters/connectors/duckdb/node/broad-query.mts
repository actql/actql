// Trusted Host assembly only. Program/ordinary Connector data cannot supply prepare.
import { runBroadAcquisition } from "./broad-acquisition.mjs";
import { runSettledQuery } from "./settled-query.mjs";
import type {BroadAcquisitionPort} from './broad-acquisition.mjs';
import type {PrepareQuery} from './settled-query.mjs';
import type {SourceAccounting, SourceLimits} from './source-acquisition.mjs';

export function runBroadQuery<Attempt, Observation, InputArgs extends unknown[], BoundInput>(
  grant: object, prepare: PrepareQuery<BroadAcquisitionPort, Attempt, Observation, InputArgs, BoundInput>,
  limits: SourceLimits, signal?: AbortSignal, accounting?: SourceAccounting,
) {
  return runSettledQuery(grant, prepare, limits, signal, runBroadAcquisition,
    (value, attempt) => value.accepted === attempt, accounting);
}
