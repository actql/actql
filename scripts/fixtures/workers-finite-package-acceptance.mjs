import assert from 'node:assert/strict';

const outputLimits = {
  maxResultFields: 10, maxResultMappingWork: 10000, maxResultOrderWork: 10000,
  maxResultWorkspaceEntries: 1000, maxRows: 100, maxValueNodes: 10000,
  maxValueTextBytes: 100000, maxValueDepth: 100, maxValueWork: 100000,
  maxWireBytes: 100000, maxWireNodes: 10000, maxWireDepth: 100, maxColumns: 100,
  maxOrderWork: 10000, maxLogicalWireBytes: 100000, maxLogicalWireNodes: 10000,
  maxLogicalWireDepth: 100, maxSchemaFields: 100, maxSchemaBytes: 10000,
  maxSchemaNodes: 1000, maxSchemaDepth: 100, maxBatchBytes: 32,
};

// Reused by the isolated installed-tarball consumer. Only serialized original
// materials enter this factory; fixture handles cannot cross the link unit.
export async function exerciseWorkersFinitePackage(createRuntime, input, maxBatchBytes = 32) {
  const {host, core, createAuthorizationGate} = createRuntime(17, input.configuration);
  assert.equal(host.core, core);
  const authorization = createAuthorizationGate({configuration: JSON.stringify({
    version: 'actql-execution-account-config/0.1', account_id: 'packed-finite',
    entries: [{entry_id: 'original', outcome: 'allow',
      principal: {any_of: ['package-tester']},
      connection: {any_of: ['in-process-default']}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []}],
  }), context: {principal: 'package-tester', contextCid: 'sha256:' + 'a'.repeat(64)},
  protectedSites: ['in-process-default']});
  try {
    assert.throws(() => host.admitMaterials(input.wire, 'sha256:' + 'b'.repeat(64)));
    const original = host.admitMaterials(input.wire, input.runDefinitionCid);
    const setup = host.open(original.preparation,
      {...original, ledger: host.createLedger()}, authorization);
    return await host.withExecution(setup, authorization, async () => {
      const exported = await core.outputExportControl.beginResult(setup, 0, {...outputLimits, maxBatchBytes});
      try {
        let wire = '';
        while (true) {
          const part = core.outputExportControl.advance(exported, 8);
          if (part.issue !== undefined) throw new Error(part.issue);
          if (part.batch !== undefined) wire += part.batch;
          if (part.complete) break;
        }
        wire += core.outputExportControl.finish(exported);
        return {rows: JSON.parse(wire), identity: core.outputExportControl.identity(exported),
          measurement: core.outputExportControl.measurement(exported)};
      } finally { core.outputExportControl.cancel(exported); }
    });
  } finally { authorization.close(); }
}
