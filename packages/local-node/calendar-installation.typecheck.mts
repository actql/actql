import type {CalendarArtifactInstallation, HostInstallation} from './index.js';
import type {InstalledRemoteHostOptions} from './http-host.js';
import type {EmbeddedHostInstallation} from '@actql/node';

const artifact: CalendarArtifactInstallation = {
  selection: {version: 'actql-calendar-selection/0.1', tzdb_version: 'test-fixture',
    conversion_law: 'actql-calendar-boundaries/0.1', table_bytes_cid: 'sha256:' + '0'.repeat(64)},
  tableBytes: new Uint8Array(), limits: {max_bytes: 1000, max_nodes: 100, max_depth: 8,
    max_zones: 1, max_transitions: 0}, maxSelectionWork: 10000,
};
const local: HostInstallation = {calendarArtifact: artifact};
const embedded: EmbeddedHostInstallation = {calendarArtifact: artifact};
const remote: InstalledRemoteHostOptions = {directory: 'private-custody',
  authenticate: () => undefined, calendarArtifact: artifact};
void [local, embedded, remote];
// @ts-expect-error Exact semantic bytes are required, not an ambient TZDB path.
const ambient: CalendarArtifactInstallation = {...artifact, tableBytes: 'system-tzdb'};
// @ts-expect-error Artifact admission limits are explicit rather than defaults.
const missing: CalendarArtifactInstallation = {selection: artifact.selection, tableBytes: artifact.tableBytes};
// @ts-expect-error The selected artifact contract version is the existing 0.1.
const changed: CalendarArtifactInstallation = {...artifact, selection: {...artifact.selection, version: 'other'}};
void [ambient, missing, changed];
