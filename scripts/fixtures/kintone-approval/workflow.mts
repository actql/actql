import {runRecordUpdateApprovalPhase} from '../record-approval/workflow.mjs';
import {kintoneUpdateCase} from '../record-approval/cases.mjs';
import type {ConnectorPhaseOptions} from '../record-approval/command.mjs';
export function runKintoneApprovalPhase({programs, selection, ...phase}: ConnectorPhaseOptions<Parameters<typeof kintoneUpdateCase>[1]>) {
  return runRecordUpdateApprovalPhase({...phase,
    createDefinition: phase.definition === undefined ? () => kintoneUpdateCase(programs!, selection!) : undefined});
}
