// Explicit-port recipe fixtures shared with real Common constructor checks.
import assert from 'node:assert/strict';
import {captureHubSpotEffectPlanRecipeBuilder} from '../host/hubspot-effect-plan.mjs';
const ok = value => ({$tag: 1, _0: value});
const freeze = value => Object.freeze(value);
export function hubSpotEffectPlanFixture() {
  const quotes = [], compositions = [], moon = {
    clientProgramHubSpotEffectConstructorCapacity(kind, input, output, counts) {
      const value = freeze({kind, input: [...input], output: [...output], counts: [...counts]}); quotes.push(value); return value;
    },
    clientProgramHubSpotEffectRecipeCapacities(original, finalization, limits, units, quantum, control, host) {
      assert.equal(original.length, 4); assert.equal(finalization.kind, 6); assert.equal(limits.length, 18);
      assert.equal(typeof units, 'bigint'); assert(quantum > 0);
      for (const tuple of original) {assert(tuple._0); assert.equal(tuple._1, undefined); assert.equal(tuple._2, undefined);}
      const call = {original, finalization, limits: [...limits], units, quantum, control, host}; compositions.push(call);
      return ok(Array.from({length: 8}, (_, index) => freeze({index, call})));
    },
    clientProgramInstalledEffectControlWireBound() {return ok(4096);},
    clientProgramInstalledEffectOperationStagedExtentPrepare(initial, maximum) {return ok(freeze({initial, maximum}));},
    clientProgramInstalledEffectOperationExtentFromCapacityPrepare(operation, capacity, transfer, physical) {
      return ok(freeze({operation, capacity, transfer, physical}));
    },
    clientProgramInstalledEffectHostInputCaptureRecipeExtentPrepare(operation, capacities, ...limits) {
      assert.equal(capacities.length, 6); return ok(freeze({operation, capacities, limits}));
    },
  };
  const limits = {
    body: {maxInputBytes: 8192, maxNodes: 2000, maxDepth: 24, maxFields: 16, maxNameBytes: 256,
      maxValueNodes: 2000, maxValueTextBytes: 8192, maxComparisonWork: 20000,
      maxOutputBytes: 8192, maxOutputNodes: 2000, maxOutputDepth: 24},
    request: {maxRows: 100, maxProperties: 100, maxTraceBytes: 128,
      maxBodyBytes: 20000, maxBodyNodes: 3000, maxBodyDepth: 24},
    read: {maxResponseBytes: 30000, maxRequestBytes: 10000, maxNodes: 3000, maxDepth: 24,
      maxProperties: 100, maxNameUnits: 256, maxRows: 10, maxColumns: 10, maxCursorUnits: 256,
      maxValueNodes: 3000, maxValueTextBytes: 8192, maxOutputBytes: 10000, maxOutputNodes: 3000,
      maxOutputDepth: 24, maxRequestNodes: 3000, maxRequestDepth: 24},
    write: {maxRequestBytes: 20000, maxResponseBytes: 30000, maxNodes: 3000, maxDepth: 24, maxRows: 1},
  };
  const options = {mappings: freeze([freeze({resource: 'companies', mappingRef: 'mapping:hubspot/update.v1',
    mappingCid: 'sha256:' + 'a'.repeat(64), fields: freeze(['amount', 'tags'])})]),
    portalId: '7', objectTypeUnits: 9, metadataResources: {account: 'account', properties: 'properties'},
    credentialSite: {construction: {scope: {namespaceId: 'original', resourceOrigin: 'https://hubspot.invalid'},
      issuer: {keyId: 'original-key'}, limits: {maxSecretBytes: 256}}},
    limits, maxRecoveryBytes: 65536, inputLimits: {
      body: {maxBytes: 65536, maxNodes: 10000, maxDepth: 100},
      preview: {maxWireBytes: 1000000, maxNodes: 10000, maxDepth: 100}}};
  const build = captureHubSpotEffectPlanRecipeBuilder({moon});
  return {moon, options, quotes, compositions, build};
}

