import {projectEffectSiteRun, type AllowedEffectRun, type RunDefinition,
  type PreparedEffectProgram} from '@actql/run-host-core';
declare const allowed: AllowedEffectRun;
declare const definition: RunDefinition;
declare const prepared: PreparedEffectProgram;
const claims = [{taskKey: 'original', dispatchCid: null,
  dispatchReserved: false, physicalStartClaimed: false}] as const;
const result = projectEffectSiteRun(allowed, definition, 'authority', [], 'clock', false, claims);
const candidate: string = result.stateWire;
const unpublished: false = result.publicationReady;
const taskCleanupOnly: boolean = result.taskCleanupComplete;
void [candidate, unpublished, taskCleanupOnly];
// @ts-expect-error Task cleanup is not whole Effect/Run cleanup evidence.
result.cleanupComplete;
// @ts-expect-error Original allowed Run is required, not a prepared Program.
projectEffectSiteRun(prepared, definition, 'authority', [], 'clock', false, claims);
// @ts-expect-error Complete original claim facts cannot be omitted.
projectEffectSiteRun(allowed, definition, 'authority', [], 'clock', false);
// @ts-expect-error No absent locator is synthesized from undefined.
projectEffectSiteRun(allowed, definition, 'authority', [], 'clock', false, [{taskKey: 'original', dispatchCid: undefined, dispatchReserved: false, physicalStartClaimed: false}]);
// @ts-expect-error Published readiness is not mutable DATA.
result.publicationReady = true;
