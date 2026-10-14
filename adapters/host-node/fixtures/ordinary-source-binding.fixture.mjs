// Declared independent materials: no preparation or product output is used to
// produce the expected physical targets, installation bindings or Source CIDs.
const cid = digit => `sha256:${digit.repeat(64)}`;
export function boundSourceInventoryFixture() {
  return {version: 'actql-client-bound-source-inventory/0.1', environmentCid: cid('a'),
    acquisitions: [0, 1].map(index => ({stage: index, input: 0, task: index,
      checkedSource: {requirementCid: cid(index === 0 ? '1' : '2'),
        sourceRef: `connector://fixture_${index}/records#rows`,
        sourceContractCid: cid('3'), carrierSchemaContractCid: cid('4'),
        sourceDataPolicyCid: cid('5'), dataClassification: 'public',
        sourceViewContractCid: cid('6'), inputContractCid: cid('7'), outputContractCid: cid('8')},
      readTuple: {connection: `fixture:${index}`, resource: 'records', operation: 'read'},
      physicalBinding: {resource: 'records', fields: ['id', 'score'], catalog_cid: cid('9'),
        path: 'e\u0301/%2F'},
      installationBinding: {connectorId: `fixture_${index}`, connectorRegistration: 'fixture',
        connectorRevision: 'fixture/0.1', bindingCid: cid(index === 0 ? 'b' : 'c')},
    }))};
}
