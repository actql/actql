import {mockProjectFiles as originalProjectFiles} from './mock-project.mjs';

// Two separate checked Source occurrences in one binary JOIN. The aliases
// select the same existing declared resource and permissions; neither alias
// nor their equal logical bytes stand in for a complete producer Unit.
export function mockProjectFiles(selection) {
  const files = originalProjectFiles(selection);
  const catalog = JSON.parse(files['mock/catalog.json']);
  catalog.connections.hubspot.query_aliases.push({name: 'hubspot.companies_peer', resource: 'companies'});
  files['mock/catalog.json'] = JSON.stringify(catalog, null, 2) + '\n';
  return files;
}
