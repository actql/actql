// Salesforce's original public consumer now delegates only the shared phase
// order. Provider authentication, Account policy and signed approval stay with
// the same original installed Host and externally configured operator.
import {runRecordUpdateApprovalPhase} from '../record-approval/workflow.mjs';
import {salesforceUpdateCase} from '../record-approval/cases.mjs';
export function runSalesforceApprovalPhase({programs, selection, ...phase}) {
  return runRecordUpdateApprovalPhase({...phase, definition: salesforceUpdateCase(programs, selection)});
}
