import {recordUpdateMockProjectFiles} from '../record-approval/mock-project.mjs';
export function mockProjectFiles({recordId, previousName, nextName}) {
  if (previousName === nextName) throw new TypeError('Fixture must change the selected Subject');
  return recordUpdateMockProjectFiles({connection: 'kintone', resource: 'inquiries', alias: 'kintone.inquiries',
    idField: '$id', valueField: 'Subject', recordId, previousValue: previousName,
    controlId: '9007199254740994', controlValue: 'Untouched control',
    updatePermission: 'kintone:records:update', observePermission: 'kintone:records:read'});
}
