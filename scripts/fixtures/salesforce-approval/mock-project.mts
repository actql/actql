import {recordUpdateMockProjectFiles} from '../record-approval/mock-project.mjs';
import type {salesforceUpdateCase} from '../record-approval/cases.mjs';
export function mockProjectFiles({recordId, previousName, nextName}: Parameters<typeof salesforceUpdateCase>[1]) {
  if (previousName === nextName) throw new TypeError('Fixture must change the selected Name');
  return recordUpdateMockProjectFiles({connection: 'salesforce', resource: 'Account', alias: 'salesforce.accounts',
    idField: 'Id', valueField: 'Name', recordId, previousValue: previousName,
    controlId: '001MockUntouched', controlValue: 'Untouched control',
    updatePermission: 'salesforce:record:update', observePermission: 'salesforce:record:observe'});
}
