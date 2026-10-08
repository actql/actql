import type {EffectProfilePaths, HostInstallation} from '@actql/local-node';
import type {InstalledRemoteHostOptions} from '@actql/local-node/http-host';
import {connect, open, type EmbeddedHostInstallation} from '@actql/node';

const paths: EffectProfilePaths = ['/profiles/crm.json', '/profiles/warehouse.json'];
const local: HostInstallation = {directory: '/host', effectProfilePaths: paths};
const remote: InstalledRemoteHostOptions = {...local, directory: '/host',
  authenticate: () => 'operator'};
const node: EmbeddedHostInstallation = local;
void connect({mode: 'local', owner: 'local', installation: node});
void open({installation: {effectProfilePaths: paths}});
const singular: HostInstallation = {effectProfilePath: '/profiles/one.json'};
// @ts-expect-error One installation uses the existing singular entry.
const one: EffectProfilePaths = ['/profiles/one.json'];
// @ts-expect-error Omit Effect options to install no Effect.
const empty: EffectProfilePaths = [];
// @ts-expect-error Paths are text, including the Node entry point.
void open({installation: {effectProfilePaths: ['/profiles/one.json', 2]}});
// @ts-expect-error The installation selection is readonly.
paths.push('/profiles/third.json');
void [remote, singular, one, empty];
