import {recordUpdateMockProjectFiles} from '../record-approval/mock-project.mjs';
export function mockProjectFiles({recordId, previousName, nextName}) {
  if (previousName === nextName) throw new TypeError('Fixture must change the selected name');
  return recordUpdateMockProjectFiles({connection: 'hubspot', resource: 'companies', alias: 'hubspot.companies',
    idField: 'id', valueField: 'name', recordId, previousValue: previousName,
    controlId: 'mock-control', controlValue: 'Untouched control',
    updatePermission: 'hubspot:objects:batch-update', observePermission: 'hubspot:objects:read'});
}
