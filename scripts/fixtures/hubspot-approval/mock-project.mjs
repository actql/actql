import {recordUpdateMockProjectFiles} from '../record-approval/mock-project.mjs';
import {recordUpdateFixtureState} from '../record-approval/cases.mjs';
export function mockProjectFiles(selection) {
  // Preserve the original standalone three-field selection's control id.
  const {before} = recordUpdateFixtureState({...selection, controlId: selection.controlId ?? 'mock-control'});
  return recordUpdateMockProjectFiles({connection: 'hubspot', resource: 'companies', alias: 'hubspot.companies',
    idField: 'id', valueField: 'name', recordId: before.target.id, previousValue: before.target.name,
    controlId: before.control.id, controlValue: before.control.name,
    updatePermission: 'hubspot:objects:batch-update', observePermission: 'hubspot:objects:read'});
}
