import {runRecordUpdateApprovalPhase} from '../record-approval/workflow.mjs';
import {kintoneUpdateCase} from '../record-approval/cases.mjs';
export function runKintoneApprovalPhase({programs, selection, ...phase}) {
  return runRecordUpdateApprovalPhase({...phase,
    createDefinition: () => kintoneUpdateCase(programs, selection)});
}
