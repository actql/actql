// SourceView-owned profiles. These declarations are not runtime read authority,
// completeness evidence or permission to issue a ContentRef.
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const positiveBound = {type: 'integer', minimum: 1, maximum: 9007199254740991};
const versionCapability = strict => ({
  type: 'object', additionalProperties: false,
  required: ['contract_cid', 'required_nonnull'],
  properties: {
    contract_cid: cid,
    required_nonnull: strict ? {const: true} : {type: 'boolean'},
  },
});

export function fileListingProfile() {
  return {
    type: 'object', additionalProperties: false,
    required: ['version', 'kind', 'selectable', 'allow_unfiltered_listing',
      'admitted_scope_contract_cid', 'listing_schema_contract_cid'],
    properties: {
      version: {const: 'actql-file-list/0.1'}, kind: {const: 'file_listing'},
      selectable: {type: 'array', maxItems: 2, uniqueItems: true,
        items: {enum: ['paths', 'glob']}},
      allow_unfiltered_listing: {type: 'boolean'},
      admitted_scope_contract_cid: cid, listing_schema_contract_cid: cid,
      path_profile_cid: cid, version_capability: versionCapability(false),
      ...Object.fromEntries(['max_listing_items', 'max_examined_items',
        'max_listing_pages', 'max_request_attempts', 'max_listing_bytes',
        'max_listing_duration_ms', 'maximum_path_length'].map(name => [name, positiveBound])),
    },
  };
}

export function fileContentProfile() {
  return {
    type: 'object', additionalProperties: false,
    required: ['version', 'kind', 'admitted_scope_contract_cid',
      'content_schema_contract_cid', 'version_capability', 'representation'],
    properties: {
      version: {const: 'actql-file-content/0.1'}, kind: {const: 'file_content'},
      admitted_scope_contract_cid: cid, content_schema_contract_cid: cid,
      version_capability: versionCapability(true),
      representation: {const: 'exact_stored_bytes'},
    },
  };
}
