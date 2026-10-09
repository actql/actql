import {snapshotClientRequest, snapshotCheckRequest, prepareClientHostRequest,
  type WireConnection} from '@actql/client-wire';
for (const snapshot of [snapshotClientRequest, snapshotCheckRequest]) {
  const received: unknown = snapshot({parameters: {value: [0, null, 1.25]}});
  void received;
}
const prepared = prepareClientHostRequest('check', {untrusted: true});
if (prepared !== undefined) {
  const body: unknown = prepared.body;
  const target: WireConnection = prepared.connection;
  void body;
  void target;
}
