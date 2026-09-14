// Trusted Host assembly only. Program/ordinary Connector data cannot supply prepare.
import { runBroadAcquisition } from "./broad-acquisition.mjs";
import { runSettledQuery } from "./settled-query.mjs";

export function runBroadQuery(grant, prepare, limits, signal, accounting) {
  return runSettledQuery(grant, prepare, limits, signal, runBroadAcquisition,
    (value, attempt) => value.accepted === attempt, accounting);
}
