import {createInstalledRestSource} from '@actql/local-node/connector-installation';
import type {RestSourceInstallationDefinition, RestSourceTransform} from '@actql/local-node/connector-installation';

const definition: RestSourceInstallationDefinition = {
  registration: 'example', revision: 'example/0.1',
  profileVersion: 'actql-installed-example-rest-source/0.1', origin: 'https://example.invalid',
  auth: {kind: 'bearer'}, sources: [{resource: 'records', resource_kind: 'record',
    fields: [{name: 'id', type: 'string', nullable: false}], read: {method: 'GET', path: '/records'},
    pagination: {kind: 'none', items: []}, limits: {maxPageRows: 2, maxPageBytes: 1024,
      maxPages: 1, maxRows: 2, maxNodes: 64, maxDepth: 8, maxCursorBytes: 32}}],
};
const transform: RestSourceTransform = (page, context) => {
  const original: string = page.rowsWire;
  const columns: readonly string[] = context.columns;
  // @ts-expect-error The author receives no credential or service port.
  void context.credential;
  // @ts-expect-error The received original page is immutable DATA.
  page.rowCount = 42;
  void columns;
  return {rowsWire: original};
};
createInstalledRestSource(definition);
createInstalledRestSource(definition, {decodePage: transform});
// @ts-expect-error A response projection is synchronous; it cannot return a computation.
createInstalledRestSource(definition, {decodePage: async page => ({rowsWire: page.rowsWire})});
// @ts-expect-error Capacity/Host setup is not an author option.
createInstalledRestSource(definition, {capacity: {}});
