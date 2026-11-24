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

// The optional callback observes the same serializer's bounded DATA. It does
// not replace native traversal, detachment or the Host's actual preparation.
snapshotClientRequest({parameters: {value: 1}}, (units, document, values) => {
  const reservedUnits: number = units;
  const reservedValues: number = values;
  const completedDocument: string | undefined = document;
  void [reservedUnits, reservedValues, completedDocument];
  // @ts-expect-error Intermediate growth has no completed JSON document yet.
  const alwaysComplete: string = document;
  void alwaysComplete;
});
// @ts-expect-error The observer receives numeric extents, not caller-selected text.
snapshotClientRequest({}, (units: string) => {void units;});
