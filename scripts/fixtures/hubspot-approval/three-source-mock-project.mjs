import {recordUpdateMockProjectFiles} from '../record-approval/mock-project.mjs';

// Distinct published inputs retain separate checked Source occurrences even
// though each borrows the same authorized companies resource and data.
export function mockProjectFiles({recordId, previousName, nextName}) {
  if (previousName === nextName) throw new TypeError('Fixture must change the selected name');
  const files = recordUpdateMockProjectFiles({connection: 'hubspot', resource: 'companies', alias: 'hubspot.companies',
    idField: 'id', valueField: 'name', recordId, previousValue: previousName,
    controlId: 'mock-control', controlValue: 'Untouched control',
    updatePermission: 'hubspot:objects:batch-update', observePermission: 'hubspot:objects:read'});
  const catalog = JSON.parse(files['mock/catalog.json']);
  catalog.connections.hubspot.query_aliases.push(
    {name: 'hubspot.companies_middle', resource: 'companies'},
    {name: 'hubspot.companies_right', resource: 'companies'});
  files['mock/catalog.json'] = JSON.stringify(catalog, null, 2) + '\n';
  return files;
}
