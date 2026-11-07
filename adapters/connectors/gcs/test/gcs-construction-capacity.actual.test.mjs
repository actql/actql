// Bounded pure producer diagnostic, NOT ordinary Host admission/cleanup proof.
// The installed composition tests remain the owner of that separate evidence.
import test from 'node:test';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as provider from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {sourceEnvironmentConstructionGeometry, sourceEnvironmentRetainedGeometry, sourceAuthoredViewConstructionGeometry}
  from '../../../host-node/installed-source-construction-geometry.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {prepareGcsSourceDeclarationInputs} from '../host/gcs-source-declaration.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {contentCid} from '../../../host-node/local-account-config.mjs';
import {prepareGcsCollectionTarget, gcsCollectionUploadMapping} from '../host/gcs-collection-target.mjs';
import {gcsUploadCatalogDeclaration} from '../host/gcs-upload-declaration.mjs';

const limits = {maxBytes: 4000000, maxNodes: 400000, maxDepth: 64};
const zero = () => checked(moon.clientProgramInstalledSourceConstructionCapacity(0n, 0n, 0n, 0n, 0n, 0n));
const bytes = original => {
  const composed = checked(moon.clientProgramComposeInstalledSourceConstructionCapacity(zero(), [original]));
  return runtimeField(moon.clientProgramSerializationCapacityBytes(composed), 1);
};
const nodeCount = value => value !== null && typeof value === 'object'
  ? 1 + Object.values(value).reduce((n, child) => n + nodeCount(child), 0) : 1;
const structuralBound = wire => {
  let result = 1;
  for (let i = 0; i < wire.length; i++) {
    const c = wire.charCodeAt(i);
    result += c === 123 || c === 91 ? 2 : c === 58 || c === 44 || c === 92 ? 1 : 0;
  }
  return result;
};

test('GCS complete three-view source measures original declaration quantity without replacing constructors', () => {
  const profile = {version: 'actql-installed-gcs-source/0.1', connectorId: 'gcs1',
    project: 'fixture-project', bucket: 'actql-fixture', prefix: 'test/', mediaType: 'application/pdf',
    siteProfilePath: '/not-opened/site.json', accountConfigurationWire: '{}',
    limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
      maxListingBytes: 32768, maxDurationMs: 10000, maxPathBytes: 1024,
      maxPageBytes: 8192, maxPageItems: 9, maxRequestBytes: 4096, maxContentBytes: 4096}};
  const base = readFileSync(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8').trimEnd();
  const inputs = prepareGcsSourceDeclarationInputs(profile, {includeObjects: true});
  const initialUnits = BigInt(profile.connectorId.length + base.length) + inputs.initialViews.reduce((n, view) =>
    n + Object.entries(view).reduce((m, [key, value]) => m + BigInt(key.length + value.length), 0n), 0n);
  const initialBasis = 6n * initialUnits + 64n * BigInt(inputs.initialViews.length);
  const restore = views => checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    profile.connectorId, 'gcs', 'gcs/0.1', JSON.stringify({views}), undefined));
  const preliminary = restore(inputs.initialViews);
  const preliminaryWire = moon.clientProgramRowSourceDeclarationJson(preliminary);
  const finalViews = inputs.deriveFinalViews(JSON.parse(preliminaryWire));
  const finalViewsWire = JSON.stringify({views: finalViews});
  const declaration = restore(finalViews);
  const wire = moon.clientProgramRowSourceDeclarationJson(declaration);
  const original = {declared: JSON.parse(wire)};
  const derivationBasis = initialBasis + 6n * BigInt(preliminaryWire.length);
  const finalBasis = 6n * BigInt(profile.connectorId.length + base.length + finalViewsWire.length) + 64n;
  const quantity = moon.clientProgramGcsUploadCatalogConstructionCapacity(wire,
    profile.connectorId.length, limits.maxBytes, limits.maxNodes, limits.maxDepth);
  const extended = gcsUploadCatalogDeclaration(provider, wire, profile.connectorId, limits);
  const mappingQuantity = moon.clientProgramGcsCollectionMappingConstructionCapacity(extended,
    profile.project.length, profile.bucket.length, profile.prefix.length,
    `connector://${profile.connectorId}/objects`.length, profile.connectorId.length,
    limits.maxBytes, limits.maxNodes, limits.maxDepth);
  const environmentBasis = 16n * BigInt(extended.length + base.length);
  const commonBytes = (retainedBasis, env = 0n) => runtimeField(moon.clientProgramSerializationCapacityBytes(
    checked(moon.clientProgramInstalledSourceConstructionCapacity(
      4n * retainedBasis + env, 8n * retainedBasis + env, 8n * retainedBasis + env, env, env, env))), 1);
  console.log(`GCS previous input-proportional constructor initial_basis=${initialBasis} preliminary_units=${preliminaryWire.length} derivation_basis=${derivationBasis} final_views_units=${finalViewsWire.length} final_basis=${finalBasis} environment_basis=${environmentBasis} first_retained_bytes=${commonBytes(initialBasis)} derivation_retained_bytes=${commonBytes(derivationBasis)} final_retained_bytes=${commonBytes(finalBasis)} environment_additional_peak_bytes=${commonBytes(0n, environmentBasis)} common_before_final_bytes=${commonBytes(initialBasis + derivationBasis + finalBasis)} common_final_peak_bytes=${commonBytes(initialBasis + derivationBasis + finalBasis, environmentBasis)}`);
  const authored = sourceAuthoredViewConstructionGeometry(finalViews);
  const assembled = sourceEnvironmentConstructionGeometry(base, JSON.parse(extended));
  const retainedBasis = initialBasis + finalBasis;
  const actualCommon = checked(moon.clientProgramInstalledSourceConstructionCapacity(
    4n * retainedBasis + authored.nodes + assembled.retained.nodes,
    8n * retainedBasis + authored.text + assembled.retained.text,
    8n * retainedBasis + authored.wire + assembled.retained.wire,
    assembled.workspace.nodes, assembled.workspace.text, assembled.workspace.wire));
  const facts = moon.clientProgramGcsSourceFactsConstructionCapacity(inputs.initialViews.length,
    inputs.scopeCid, inputs.versionCid,
    JSON.parse(preliminaryWire).views.find(view => view.resource === 'files').carrier_schema_cid,
    JSON.parse(preliminaryWire).views.find(view => view.resource === 'contents').carrier_schema_cid,
    ['maxListingItems', 'maxExaminedItems', 'maxPages', 'maxAttempts', 'maxListingBytes',
      'maxDurationMs', 'maxPathBytes', 'maxPageBytes'].map(name => BigInt(profile.limits[name])));
  const exactTotal = checked(moon.clientProgramComposeInstalledSourceConstructionCapacity(actualCommon,
    [facts, checked(moon.clientProgramInstalledSourceRetainedConstructionCapacity(quantity))]));
  console.log(`GCS actual-shape constructor authored_nodes=${authored.nodes} environment_nodes=${assembled.nodes} environment_text=${assembled.text} facts_peak_bytes=${bytes(facts)} common_final_peak_bytes=${runtimeField(moon.clientProgramSerializationCapacityBytes(actualCommon), 1)} combined_pre_site_peak_bytes=${runtimeField(moon.clientProgramSerializationCapacityBytes(exactTotal), 1)}`);
  // A genuine native DATA binding for this isolated producer fixture, never
  // a Common Reference/installation permission or actual Host resource proof.
  const target = prepareGcsCollectionTarget(provider, {project: profile.project,
    bucket: profile.bucket, prefix: profile.prefix,
    targetRef: `connector://${profile.connectorId}/objects`, resourceKind: 'file_collection',
    catalogCid: JSON.parse(extended).catalog_cid,
    installationCid: contentCid({purpose: 'construction-quantity-fixture', profile}), ...limits});
  const mappingWire = gcsCollectionUploadMapping(target, extended, profile.connectorId, limits);
  const beforeMapping = rowSourceCheckEnvironment(base, JSON.parse(extended));
  const oldRetained = sourceEnvironmentRetainedGeometry(beforeMapping);
  const mappingEnvironment = sourceEnvironmentConstructionGeometry(base, JSON.parse(extended), [mappingWire]);
  const mappingCommon = checked(moon.clientProgramInstalledSourceConstructionCapacity(
    4n * retainedBasis + authored.nodes + oldRetained.nodes + mappingEnvironment.retained.nodes,
    8n * retainedBasis + authored.text + oldRetained.text + mappingEnvironment.retained.text,
    8n * retainedBasis + authored.wire + oldRetained.wire + mappingEnvironment.retained.wire,
    mappingEnvironment.workspace.nodes, mappingEnvironment.workspace.text, mappingEnvironment.workspace.wire));
  const mappingTotal = checked(moon.clientProgramComposeInstalledSourceConstructionCapacity(mappingCommon,
    [facts, checked(moon.clientProgramInstalledSourceRetainedConstructionCapacity(quantity)),
      checked(moon.clientProgramInstalledSourceRetainedConstructionCapacity(mappingQuantity))]));
  const beforeMappingCommon = checked(moon.clientProgramInstalledSourceConstructionCapacity(
    4n * retainedBasis + authored.nodes + oldRetained.nodes,
    8n * retainedBasis + authored.text + oldRetained.text,
    8n * retainedBasis + authored.wire + oldRetained.wire, 0n, 0n, 0n));
  const mappingConstructorTotal = checked(moon.clientProgramComposeInstalledSourceConstructionCapacity(beforeMappingCommon,
    [facts, checked(moon.clientProgramInstalledSourceRetainedConstructionCapacity(quantity)), mappingQuantity]));
  console.log(`GCS native mapping constructor full_peak_bytes=${runtimeField(moon.clientProgramSerializationCapacityBytes(mappingConstructorTotal), 1)} mapping_retained_bytes=${bytes(checked(moon.clientProgramInstalledSourceRetainedConstructionCapacity(mappingQuantity)))}`);
  console.log(`GCS actual-shape mapping wire_units=${mappingWire.length} prior_environment_retained_nodes=${oldRetained.nodes} prior_environment_retained_text=${oldRetained.text} workspace_nodes=${mappingEnvironment.workspace.nodes} workspace_text=${mappingEnvironment.workspace.text} common_mapping_peak_bytes=${runtimeField(moon.clientProgramSerializationCapacityBytes(mappingCommon), 1)} combined_mapping_peak_bytes=${runtimeField(moon.clientProgramSerializationCapacityBytes(mappingTotal), 1)}`);
  const parsed = JSON.parse(wire), catalog = JSON.parse(parsed.catalog);
  const rawNodes = nodeCount(parsed) + nodeCount(catalog) + parsed.contracts.reduce((n, body) => n + nodeCount(JSON.parse(body)), 0);
  console.log(`GCS actual three-view wire_units=${wire.length} raw_nodes=${rawNodes} structural_bound=${structuralBound(wire)} extension_bytes=${bytes(quantity)} extension_retained_bytes=${bytes(checked(moon.clientProgramInstalledSourceRetainedConstructionCapacity(quantity)))} extended_units=${extended.length} mapping_bytes=${bytes(mappingQuantity)}`);
  assert.equal(original.declared.views.length, 3);
  assert.equal(JSON.parse(extended).command_bodies.length, 1);
  assert.ok(structuralBound(wire) >= rawNodes);
});
