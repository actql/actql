import {runRecordUpdateApprovalPhase} from '../record-approval/workflow.mjs';
import {hubspotUpdateCase} from '../record-approval/cases.mjs';
import type {ConnectorPhaseOptions} from '../record-approval/command.mjs';
export function runHubSpotApprovalPhase({programs, selection, ...phase}: ConnectorPhaseOptions<Parameters<typeof hubspotUpdateCase>[1]>) {
  return runRecordUpdateApprovalPhase({...phase,
    createDefinition: phase.definition === undefined ? () => hubspotUpdateCase(programs!, selection!) : undefined});
}
