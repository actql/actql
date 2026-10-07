import {snapshotClientRequest, snapshotCheckRequest} from '@actql/client-wire';
for (const snapshot of [snapshotClientRequest, snapshotCheckRequest]) {
  const received: unknown = snapshot({parameters: {value: [0, null, 1.25]}});
  void received;
}
