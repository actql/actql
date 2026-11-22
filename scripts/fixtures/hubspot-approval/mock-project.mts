import {recordUpdateMockProjectFiles} from '../record-approval/mock-project.mjs';
import {recordUpdateFixtureSeed, recordUpdateFixtureState} from '../record-approval/cases.mjs';
export function mockProjectFiles(selection: Parameters<typeof recordUpdateFixtureState>[0]) {
  // Preserve the original standalone three-field selection's control id.
  const {before} = recordUpdateFixtureState({...selection, controlId: selection.controlId ?? 'mock-control'});
  return projectFiles(before);
}

export function mockProjectFilesFromSeed(seed: Parameters<typeof recordUpdateFixtureSeed>[0]) {
  return projectFiles(recordUpdateFixtureSeed(seed));
}

function projectFiles(before: ReturnType<typeof recordUpdateFixtureSeed>) {
  return recordUpdateMockProjectFiles({connection: 'hubspot', resource: 'companies', alias: 'hubspot.companies',
    idField: 'id', valueField: 'name', recordId: before.target.id, previousValue: before.target.name,
    controlId: before.control.id, controlValue: before.control.name,
    updatePermission: 'hubspot:objects:batch-update', observePermission: 'hubspot:objects:read'});
}
