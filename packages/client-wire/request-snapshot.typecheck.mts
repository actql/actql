import {snapshotClientRequest, snapshotCheckRequest, prepareClientHostRequest,
  type WireConnection} from '@actql/client-wire';
for (const snapshot of [snapshotClientRequest, snapshotCheckRequest]) {
  const received: unknown = snapshot({parameters: {value: [0, null, 1.25]}});
  void received;
}
const prepared = prepareClientHostRequest('check', {untrusted: true});
const retained = prepareClientHostRequest('attach', {untrusted: true}, true);
void retained;
// @ts-expect-error The capture selection is typed, not a caller packet field.
prepareClientHostRequest('attach', {untrusted: true}, 'immutable');
if (prepared !== undefined) {
  const body: unknown = prepared.body;
  const target: WireConnection = prepared.connection;
  void body;
  void target;
}
