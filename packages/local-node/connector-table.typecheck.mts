import {createInstalledConnectorTable, publishSource, publishEffect,
  type InstalledConnectorEntry, type InstalledConnectorTable,
  type HostInstallation} from '@actql/local-node';
import {open, connect} from '@actql/node';
import type {InstalledRemoteHostOptions} from '@actql/local-node/http-host';

const entries: readonly InstalledConnectorEntry[] = [{name: 'example',
  registration: 'example', revision: 'example/0.1',
  source: {profileVersion: 'actql-installed-example-source/0.1',
    load: async () => ({check() {}, identityParts() {}, load() {}})}}];
const connectorTable = createInstalledConnectorTable(entries);
const installation: HostInstallation = {connectorTable};
void open({installation});
void connect({mode: 'local', owner: 'local', installation});
const http: InstalledRemoteHostOptions = {directory: '/host', connectorTable,
  authenticate: () => 'owner'};
void publishSource({sourceProfilePath: '/source.json', connectorTable});
void publishEffect({effectProfilePath: '/effect.json', connectorTable});
// @ts-expect-error A plain object is not an admitted table handle.
const forged: InstalledConnectorTable = {};
// @ts-expect-error Installation loading is a lazy function, not an import URL.
createInstalledConnectorTable([{name: 'bad', source: {profileVersion: 'v', load: './provider.mjs'}}]);
// @ts-expect-error The entry inventory is readonly.
entries.push({name: 'later'});
void [http, forged];
