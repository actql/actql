import {runRecordUpdateApprovalPhase} from '../record-approval/workflow.mjs';
import {hubspotUpdateCase} from '../record-approval/cases.mjs';
export function runHubSpotApprovalPhase({programs, selection, ...phase}) {
  return runRecordUpdateApprovalPhase({...phase, definition: hubspotUpdateCase(programs, selection)});
}
