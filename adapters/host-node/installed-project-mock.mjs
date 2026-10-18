import {resolve} from 'node:path';
import {checked} from '../host-common/runtime-result.mjs';
import {installedProjectOriginalsForRuntime} from './installed-project-configuration.mjs';
import {loadInstalledProjectConnections} from './installed-project-connections.mjs';
import {mockChurnRiskCatalogue} from './mock-churn-risk-catalogue.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};

// Original installation preparation under the separately admitted Source
// phase, before any fixture acquisition. The bundled declarations are not
// inferred from rows, a Task, pathname or the original connection's secrets.
// This view supplies no read decision, physical child, Run or capacity.
export async function prepareInstalledProjectMock(moon, project, profile,
  {assertCurrent, openFile} = {}) {
  let projectOriginal = installedProjectOriginalsForRuntime(project, moon);
  if (typeof assertCurrent !== 'function' || typeof project.directory !== 'string' ||
      !project.directory || typeof profile?.originalsForRuntime !== 'function' ||
      typeof profile?.mockLocatorsForRuntime !== 'function') {
    fail('InvalidInstalledMockPreparation');
  }
  let ports = Object.freeze({restore: moon?.clientProgramRowSourceRestoreRelationDeclaration,
    wire: moon?.clientProgramRowSourceDeclarationJson,
    mapping: moon?.clientProgramMockChurnRiskUpdateMapping,
    count: moon?.clientProjectConnectionsCount, name: moon?.clientProjectConnectionsName,
    connector: moon?.clientProjectConnectionsConnector});
  if (!Object.values(ports).every(port => typeof port === 'function')) {
    fail('InstalledProjectRuntimeUnavailable');
  }
  let profilePorts = Object.freeze({originals: profile.originalsForRuntime,
    locators: profile.mockLocatorsForRuntime});
  const call = (name, ...args) => Reflect.apply(ports[name], moon, args);
  const select = name => Reflect.apply(profilePorts[name], profile, [moon]);
  let selection = select('originals');
  function current() {
    assertCurrent();
    const observed = select('originals');
    if (installedProjectOriginalsForRuntime(project, moon) !== projectOriginal ||
        selection.configuration !== projectOriginal.configuration ||
        observed.configuration !== selection.configuration ||
        observed.selection !== selection.selection || observed.selected !== 'mock' ||
        selection.selected !== 'mock') fail('ForeignInstalledMockPreparation');
  }
  current();
  const locators = select('locators');
  if (typeof locators.dataFile !== 'string' || !locators.dataFile ||
      !locators.dataFile.isWellFormed() || locators.dataFile.length > 65536) {
    fail('InstalledMockDataUnavailable');
  }
  // This reads only the explicitly selected connections declaration. The
  // original metadata reader owns its same FD, UTF8 bounds and close carrier;
  // no entry's credential resolver, env variable or network is consulted.
  let connections = await loadInstalledProjectConnections(moon, project,
    {assertCurrent: current, ...(openFile === undefined ? {} : {openFile})});
  current();
  let connectionOriginal = connections.originalsForRuntime(moon);
  if (connectionOriginal.project !== projectOriginal ||
      connectionOriginal.connections === undefined) fail('InstalledMockConnectionsUnavailable');
  const count = call('count', connectionOriginal.connections);
  if (!Number.isSafeInteger(count) || count < 0 || count > 128) {
    fail('InstalledMockConnectionCountUnavailable');
  }
  let sources = [];
  for (const entry of mockChurnRiskCatalogue) {
    let found = false;
    for (let index = 0; index < count; index++) {
      if (call('name', connectionOriginal.connections, index) !== entry.connection) continue;
      if (call('connector', connectionOriginal.connections, index) !== entry.connectorId) {
        fail('InstalledMockConnectionChanged');
      }
      found = true;
    }
    if (!found) fail('InstalledMockCatalogueUnavailable');
    current();
    const declaration = checked(call('restore', entry.connectorId, entry.registration,
      entry.revision, JSON.stringify({views: entry.views}), undefined));
    const wire = call('wire', declaration);
    if (typeof wire !== 'string') fail('InvalidHostRuntimeResult');
    sources.push(Object.freeze({catalogue: entry, declaration, wire}));
  }
  sources = Object.freeze(sources);
  let mappingWire = checked(call('mapping', sources[0].declaration));
  if (typeof mappingWire !== 'string') fail('InvalidHostRuntimeResult');
  current();
  let originals = Object.freeze({project: projectOriginal, selection: selection.selection,
    configuration: selection.configuration, connections: connectionOriginal,
    dataFile: locators.dataFile, dataPath: resolve(project.directory, locators.dataFile),
    sources, mappingWire});
  let retired = false, view;
  function same(runtime, receiver) {
    if (runtime !== moon || receiver !== view) fail('ForeignInstalledMockPreparation');
  }
  view = Object.freeze({
    originalsForRuntime(runtime) {
      same(runtime, this);
      if (retired) fail('InstalledMockPreparationRetired');
      current();
      if (connections.originalsForRuntime(moon) !== connectionOriginal) {
        fail('ForeignInstalledMockPreparation');
      }
      return originals;
    },
    retire(runtime) {
      same(runtime, this);
      if (retired) return;
      // Managed references only, after the actual Source parent's close. This
      // cannot settle its FD, backing bytes, RowRuns or external cleanup ACKs.
      retired = true;
      originals = sources = mappingWire = connections = connectionOriginal = undefined;
      projectOriginal = selection = project = profile = profilePorts = ports = undefined;
      assertCurrent = openFile = undefined;
    },
  });
  return view;
}
