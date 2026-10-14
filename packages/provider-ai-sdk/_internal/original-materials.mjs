const fail = () => {throw Object.assign(new TypeError('InvalidOpenAIOriginalMaterials'),
  {code:'InvalidOpenAIOriginalMaterials'});};
const record = (value, required, optional = {}) => {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) fail();
  const names = Reflect.ownKeys(value);
  if (names.some(name => typeof name !== 'string' ||
      !Object.hasOwn(required,name) && !Object.hasOwn(optional,name)) ||
      Object.keys(required).some(name => !names.includes(name))) fail();
  const fields = names.map(name => {
    const d = Object.getOwnPropertyDescriptor(value,name);
    if (d === undefined || !d.enumerable || !Object.hasOwn(d,'value')) fail();
    return [name,(required[name] ?? optional[name])(d.value)];
  });
  return Object.freeze(Object.fromEntries(fields));
};
const scalar = value => {
  if (!['string','bigint','number','boolean','undefined'].includes(typeof value) && value !== null) fail();
  return value;
};
const fields = names => Object.fromEntries(names.split(',').map(name => [name,scalar]));
const shape = names => value => record(value,fields(names));
const original = value => record(value,{
  cid:value => {if (typeof value !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(value)) fail();return value;},
  wire:value => {if (typeof value !== 'string') fail();return value;},
});
const installation = value => record(value,{
  ...fields('build_artifact_cid,builder_id,builder_revision,codec_id,codec_revision,completion_basis,endpoint,http_method,streaming,validator_artifact_cid,validator_id,validator_revision'),
  sdk:shape('interface,lock_artifact_cid,package_name,version'),
});

// A closed installation DATA snapshot, not a canonical parser, opaque Owner
// reconstruction or funding proof. Each descriptor is read exactly once;
// the existing Common readers alone admit the original wire and CID.
export function snapshotOpenAIOriginalMaterials(value) {
  return record(value,{
    responseProfile:original,
    policyOriginals:value => record(value,{retention:original,metadata:original,clock:original,data:original}),
    readerLimits:value => record(value,Object.fromEntries(
      ['maxBytes','maxNodes','maxDepth','maxMembers','maxWork'].map(name => [name,value => {
        if (!Number.isSafeInteger(value) || value < 1 || value > 2147483647) fail();return value;
      }]))),
    installation,
    originalReadInstallation:value => record(value,{
      bootstrap:shape('bootstrapExecutionBytes,bootstrapRetainedBytes,maxDelegations,maxHoldings,maxReservations'),
      modelExecutionBytes:scalar,modelRetainedBytes:scalar,
      nodeInstallation:value => record(value,{
        runtimeArtifactCid:scalar,layoutArtifactCid:scalar,
        layout:shape('barrier_cid,execution_bytes,layout_artifact_cid,parameter_values_cid,prepared_rows,program_definition_cid,retained_bytes,runtime_artifact_cid'),
      }),
    },{
      storeBootstrap:shape('maxDirectoryEntries,maxWireBytes'),
      publicationCapacity:shape('retainedBytes,workspaceBytes'),
      metadataAcquisition:value => record(value,{
        retainedBytes:scalar,workspaceBytes:scalar,
        metadata:shape('maxLedgerEntries,maxWireBytes'),directory:shape('maxDirectoryEntries,maxWireBytes'),
      }),
      currentStateCodec:value => record(value,{
        quantum:scalar,comparisonWork:scalar,decode:value => record(value,{
          maxWork:scalar,parse:shape('max_depth,max_input_bytes,max_nodes'),
          tree:shape('max_depth,max_nodes,max_string_bytes,max_total_string_bytes'),
        }),
      }),
    }),
    rawCaptureSelection:value => record(value,{
      ...fields('availableUntil,deleteBy,extensionCeilingAt,metadataDeleteBy,selectedAt'),
      selectionAvailable:value => {if (typeof value !== 'function') fail();return value;},
    }),
  });
}

export function admitOpenAIOriginalMaterials(moon, materials) {
  if (moon === null || (typeof moon !== 'object' && typeof moon !== 'function') ||
      typeof moon.clientProgramReadModelResponseProfile !== 'function' ||
      typeof moon.clientProgramAdmitEffectDependencyBody !== 'function') {
    throw Object.assign(new TypeError('OpenAIOriginalRuntimeUnavailable'),{code:'OpenAIOriginalRuntimeUnavailable'});
  }
  const {maxBytes,maxNodes,maxDepth,maxMembers,maxWork} = materials.readerLimits;
  const checked = result => {
    if (result?.$tag === 1 && result._0 !== undefined && result._0 !== null) return result._0;
    throw Object.assign(new TypeError('OpenAIOriginalMaterialsRefused'),{code:'OpenAIOriginalMaterialsRefused'});
  };
  const profile = checked(moon.clientProgramReadModelResponseProfile(
    materials.responseProfile.wire,materials.responseProfile.cid,maxBytes,maxNodes,maxDepth,maxMembers,maxWork));
  const policies = Object.fromEntries([
    ['retention','retention_contract'],['metadata','metadata_retention_policy'],
    ['clock','clock_contract'],['data','data_policy'],
  ].map(([name,kind]) => {
    const body = materials.policyOriginals[name];
    return [name,checked(moon.clientProgramAdmitEffectDependencyBody(
      kind,body.cid,body.wire,maxBytes,maxNodes,maxDepth))];
  }));
  const {installation,originalReadInstallation:read,rawCaptureSelection:raw} = materials;
  return Object.freeze({
    originalReadInstallation:Object.freeze({...read,nodeInstallation:Object.freeze({
      ...read.nodeInstallation,installation,probability:undefined,
      layout:Object.freeze({...read.nodeInstallation.layout,response_profile:profile}),
    })}),
    rawCaptureSelection:Object.freeze({...raw,...policies,profile,installation,probability:undefined}),
  });
}
