import {recordUpdateMockProjectFiles} from '../record-approval/mock-project.mjs';
import {recordUpdateFixtureSeed, recordUpdateFixtureState} from '../record-approval/cases.mjs';
export function mockProjectFiles(selection: Parameters<typeof recordUpdateFixtureState>[0]) {
  const {before} = recordUpdateFixtureState({...selection, controlId: selection.controlId ?? '9007199254740994'});
  return projectFiles(before);
}

export function mockProjectFilesFromSeed(seed: Parameters<typeof recordUpdateFixtureSeed>[0]) {
  return projectFiles(recordUpdateFixtureSeed(seed));
}

function projectFiles(before: ReturnType<typeof recordUpdateFixtureSeed>) {
  return recordUpdateMockProjectFiles({connection: 'kintone', resource: 'inquiries', alias: 'kintone.inquiries',
    idField: '$id', valueField: 'Subject', recordId: before.target.id, previousValue: before.target.name,
    controlId: before.control.id, controlValue: before.control.name,
    updatePermission: 'kintone:records:update', observePermission: 'kintone:records:read'});
}
