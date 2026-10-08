import type {HostInstallation, SourceProfilePaths} from '@actql/local-node';
import type {InstalledRemoteHostOptions} from '@actql/local-node/http-host';
import {connect, open, type EmbeddedHostInstallation} from '@actql/node';

const paths: SourceProfilePaths = ['/profiles/first.json', '/profiles/second.json',
  '/profiles/third.json'];
const embedded: HostInstallation = {directory: '/host', sourceProfilePaths: paths};
const remote: InstalledRemoteHostOptions = {...embedded, directory: '/host',
  authenticate: () => 'operator'};
const singular: HostInstallation = {sourceProfilePath: '/profiles/one.json'};
const absent: HostInstallation = {};
const nodeInstallation: EmbeddedHostInstallation = embedded;
void connect({mode: 'local', owner: 'local', installation: nodeInstallation});
void open({installation: {sourceProfilePaths: paths}});
// @ts-expect-error The Node entry also requires two or more plural profiles.
void open({installation: {sourceProfilePaths: ['/profiles/one.json']}});
// @ts-expect-error The plural entry does not replace the existing singular entry.
const one: SourceProfilePaths = ['/profiles/one.json'];
// @ts-expect-error Omit Source options to install no Source.
const empty: SourceProfilePaths = [];
// @ts-expect-error A selected profile path is text.
const malformed: SourceProfilePaths = ['/profiles/first.json', 2];
// @ts-expect-error The caller cannot mutate the readonly published selection.
paths.push('/profiles/fourth.json');
void [remote, singular, absent, one, empty, malformed];
