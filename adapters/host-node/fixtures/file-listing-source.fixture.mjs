// Authored finite declaration and opaque Resource fixtures. These objects are
// trusted installation inputs, not reference envelopes supplied by a Program.
import {createHash} from 'node:crypto';
import {checked} from '../../host-common/runtime-result.mjs';
import {rowSourceCheckEnvironment} from '../installed-row-source.mjs';

export const canonical = value => value && typeof value === 'object'
  ? Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
    : `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
  : JSON.stringify(value);
export const cid = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;
export const token = ch => `sha256:${ch.repeat(64)}`;
export const resource = ch => ({$actql_ref: 'resource', version: 'actql-resource-ref/0.1',
  provider_namespace: 'file-fixture', resource_kind: 'file',
  provider_identity_cid: token('a'), authority_scope_cid: token('b'),
  boundary_cid: token('c'), identity_cid: token(ch)});
export const item = (ch, path, version = '1') => ({resource: resource(ch), name: path,
  path, version, media_type: null, size_bytes: 3, modified_at: null});

export function fileListingDeclaration(moon, baseWire, {maxListingBytes = 32768,
  schema: declaredSchema} = {}) {
  const schema = declaredSchema ?? {
    resource: {type: 'resource_ref', resource_kind: 'file', nullable: false},
    version: {type: 'string', nullable: false}, name: {type: 'string', nullable: false},
    path: {type: 'string', nullable: true}, media_type: {type: 'string', nullable: true},
    size_bytes: {type: 'number', nullable: true}, modified_at: {type: 'timestamp', nullable: true},
  };
  const spec = {resource: 'files', resource_kind: 'file', schema_wire: canonical(schema),
    schema_cid: cid(schema), request_schema_wire: canonical({type: 'object', nullable: false,
      additional_properties: false, fields: {
        paths: {type: 'array', nullable: true, max_items: 8,
          items: {type: 'string', nullable: false}},
        glob: {type: 'string', nullable: true},
      }}), facts_wire: '{}'};
  const restore = () => checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    'fixture', 'fixture', 'fixture/0.1', JSON.stringify({views: [spec]}), undefined));
  const first = JSON.parse(moon.clientProgramRowSourceDeclarationJson(restore()));
  spec.facts_wire = canonical({file_listing: {
    version: 'actql-file-list/0.1', kind: 'file_listing', selectable: ['paths', 'glob'],
    allow_unfiltered_listing: true, admitted_scope_contract_cid: token('a'),
    listing_schema_contract_cid: first.views[0].carrier_schema_cid,
    version_capability: {contract_cid: token('b'), required_nonnull: true},
    max_listing_items: 3, max_examined_items: 9, max_listing_pages: 4,
    max_request_attempts: 4, max_listing_bytes: maxListingBytes,
    max_listing_duration_ms: 10000, maximum_path_length: 64,
  }});
  const declaration = restore();
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(baseWire, declared);
  const view = JSON.parse(environment.wire).source_views[0];
  const aliases = [{name: 'docs.invoices', sourceRef: declared.views[0].source_ref,
    sourceViewContractCid: view.contract_cid,
    schemaContractCid: declared.views[0].carrier_schema_cid}];
  const issuer = moon.clientProgramResourceReferenceIssuer((kind, wire) =>
    kind === 'file' && ['d', 'e', 'f'].some(ch => canonical(resource(ch)) === wire), () => true);
  return {declaration, declared, environment, aliases, issuer, spec};
}
