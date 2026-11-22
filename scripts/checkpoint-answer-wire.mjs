import {project} from './generate-client-publication-wire.mjs';

const own = (value, key) => Object.hasOwn(value, key);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const fail = name => { throw new Error(`UnsupportedCheckpointAnswerConstruction:${name}`); };
function closed(value, required, optional = []) {
  if (!object(value) || required.some(key => !own(value, key)) ||
      Object.keys(value).some(key => !required.includes(key) && !optional.includes(key))) fail('shape');
}
function text(value) {
  if (typeof value !== 'string' || value.length === 0) fail('text');
  return value;
}
function constant(rule) { closed(rule, ['const']); return text(rule.const); }
function choices(rule) {
  if (!own(rule, 'oneOf')) return [rule];
  closed(rule, ['oneOf']);
  if (!Array.isArray(rule.oneOf) || rule.oneOf.length === 0) fail('oneOf');
  return rule.oneOf;
}
function requirements(rule) {
  return choices(rule).map(item => {
    closed(item, ['const']);
    if (!Array.isArray(item.const) || item.const.length === 0 ||
        item.const.some(value => typeof value !== 'string' || value.length === 0) ||
        new Set(item.const).size !== item.const.length) fail('requirements');
    return [...item.const];
  });
}

// The execution_checkpoint schema is the only kind/subject/phase/artifact/claim
// inventory. The construction recipe selects supported candidate profiles and
// field transport; neither renderer authors another profile table.
export function checkpointAnswerContract(registry, protocol) {
  const recipe = registry.checkpoint_answer_construction;
  closed(recipe, ['summary_schema', 'checkpoint_profile_source', 'profiles', 'decisions',
    'documents', 'resolution_subject_fields', 'identities', 'proof',
    'decisions_and_omissions', 'canonical', 'time', 'signer', 'limits', 'output', 'authority']);
  if (recipe.summary_schema !== '#/schemas/checkpoint_summary' ||
      recipe.checkpoint_profile_source.contract !== 'actql-protocol-schemas.json' ||
      recipe.checkpoint_profile_source.schema !== 'artifact_schemas.execution_checkpoint.oneOf') fail('source');
  closed(recipe.proof, ['scheme', 'key_id', 'signature']);
  if (recipe.proof.scheme !== 'ed25519-v1' ||
      recipe.proof.signature !== 'actual external callback output; canonical Base64 exact64bytes/88characters; reject nonzero padbits') fail('proof-encoding');
  // Transport the fixed Ed25519 byte demand and canonical pad bits to both SDKs.
  const signatureEncoding = {byteLength: 64, pattern: '[A-Za-z0-9+/]{85}[AQgw]=='};
  const branches = protocol.artifact_schemas.execution_checkpoint.oneOf;
  if (!Array.isArray(branches) || branches.length === 0) fail('profiles');
  const profiles = [];
  const identities = new Set();
  for (const branch of branches) {
    closed(branch, ['properties']);
    const fields = branch.properties;
    closed(fields, ['subject', 'phase', 'kind', 'required_artifact', 'requirements']);
    const kind = constant(fields.kind), phase = constant(fields.phase);
    const artifactType = constant(fields.required_artifact.properties.artifact_type);
    const claims = requirements(fields.requirements);
    for (const subject of choices(fields.subject)) {
      const name = constant(subject.properties.kind);
      const identity = JSON.stringify([kind, phase, name]);
      if (identities.has(identity)) fail('duplicate-profile');
      identities.add(identity);
      profiles.push({kind, phase, subject: name, artifactType, requirements: claims});
    }
  }
  const kinds = new Map();
  for (const profile of profiles) {
    const retained = kinds.get(profile.kind);
    if (retained && (retained.artifactType !== profile.artifactType ||
        JSON.stringify(retained.requirements) !== JSON.stringify(profile.requirements))) fail('conflicting-kind');
    kinds.set(profile.kind, profile);
  }
  if (!Array.isArray(recipe.profiles) || recipe.profiles.length === 0) fail('candidate-profiles');
  const candidates = recipe.profiles.map(candidate => {
    closed(candidate, ['name', 'kind', 'subject', 'approval', 'preparedInvocationCid', 'resolutionSubject']);
    const selected = profiles.filter(profile => profile.kind === candidate.kind && profile.subject === candidate.subject);
    if (selected.length !== 1 || !own(recipe.documents, candidate.approval) ||
        !own(recipe.identities, candidate.approval) ||
        !own(recipe.resolution_subject_fields, candidate.resolutionSubject)) fail('candidate-profile');
    if (!['invocation', 'effect'].includes(candidate.approval) ||
        !['prepare', 'run'].includes(candidate.resolutionSubject)) fail('candidate-feature');
    if (candidate.preparedInvocationCid !== null &&
        !['summary.requiredArtifact.cid', 'summary.preparedInvocationCid'].includes(candidate.preparedInvocationCid)) fail('prepared-source');
    return {...candidate, ...selected[0]};
  });
  if (new Set(candidates.map(value => value.name)).size !== candidates.length ||
      new Set(candidates.map(value => JSON.stringify([value.kind, value.subject]))).size !== candidates.length) fail('candidate-identity');
  for (const document of [...Object.values(recipe.documents), ...Object.values(recipe.resolution_subject_fields)]) {
    if (!object(document) || Object.keys(document).length === 0) fail('document');
    for (const rule of Object.values(document)) {
      closed(rule, [], ['constant', 'source', 'concatenate', 'copy', 'requiredOn', 'omitOn']);
      if (['constant', 'source', 'concatenate'].filter(key => own(rule, key)).length !== 1) fail('field-expression');
      if (own(rule, 'source') && !/^(?:summary(?:\.[A-Za-z]+)+|actor\.[A-Za-z]+|selectedProfile\.preparedInvocationCid|decision|decidedAt|signedApprovalWithSelfCid|evidenceCid)$/u.test(rule.source)) fail('field-source');
      if (own(rule, 'concatenate') && (!Array.isArray(rule.concatenate) ||
          rule.concatenate.some(value => typeof value !== 'string'))) fail('concatenate');
      if (own(rule, 'copy') && rule.copy !== 'exact ordered original list') fail('copy');
      if (own(rule, 'requiredOn') && rule.requiredOn !== 'approved effect') fail('requiredOn');
      if (own(rule, 'omitOn') && rule.omitOn !== 'rejected') fail('omitOn');
    }
  }
  const summary = project(registry.schemas.checkpoint_summary);
  const cidPaths = new Map();
  function scalarDomains(schema, path = []) {
    if (schema.$ref) fail('summary-reference');
    if (schema.pattern === '^sha256:[0-9a-f]{64}$') cidPaths.set(JSON.stringify(path), path);
    for (const [key, child] of Object.entries(schema.properties ?? {})) scalarDomains(child, [...path, key]);
    for (const name of ['oneOf', 'allOf']) for (const child of schema[name] ?? []) scalarDomains(child, path);
    if (schema.items && JSON.stringify(schema.items).includes('sha256:')) fail('summary-cid-array');
  }
  scalarDomains(summary);
  if (!Array.isArray(recipe.canonical.identity_text_paths) || recipe.canonical.identity_text_paths.some(path =>
      !Array.isArray(path) || path.length === 0 || path.some(key => typeof key !== 'string' || !/^[A-Za-z]+$/u.test(key)))) fail('identity-text-paths');
  // These are the existing Run-evidence review forms, not a new identity
  // inventory. Versions come from their original artifact schemas. Effect
  // display DATA keeps exact keys; Model retains its identifier-key domain.
  const reviews = ['run_review_projection', 'review_projection'].map(name => {
    const schema = protocol.artifact_schemas[name];
    const version = schema?.properties?.version?.const;
    if (typeof version !== 'string' ||
        !schema.required?.includes('review_projection_cid') ||
        schema.properties.review_projection_cid?.pattern !== '^sha256:[0-9a-f]{64}$') fail('review-profile');
    return {version, selfField: 'review_projection_cid', dataKeys: name === 'review_projection'};
  });
  return {profiles, candidates, recipe, summary, cidPaths: [...cidPaths.values()], reviews, signatureEncoding};
}

export function commonCheckpointProfileSource(contract) {
  const kinds = [...new Map(contract.profiles.map(profile => [profile.kind, profile])).values()];
  const literal = value => Array.isArray(value) ? '[' + value.map(literal).join(', ') + ']' : JSON.stringify(value);
  const header = '// Generated by scripts/generate-client-host-wire.mjs; do not edit.\n' +
    '// Checkpoint profiles and existing review versions come only from protocol schemas.\n\n';
  return header + '///|\npub fn artifact_type(kind : String) -> String? {\n  match kind {\n' +
    kinds.map(profile => `    ${literal(profile.kind)} => Some(${literal(profile.artifactType)})\n`).join('') +
    '    _ => None\n  }\n}\n\n' +
    '///|\npub fn combination_valid(\n  subject : String,\n  phase : String,\n  kind : String,\n) -> Bool {\n  match (subject, phase, kind) {\n' +
    contract.profiles.map(profile => `    (${literal(profile.subject)}, ${literal(profile.phase)}, ${literal(profile.kind)}) => true\n`).join('') +
    '    _ => false\n  }\n}\n\n' +
    '///|\npub fn requirement_max_arity(kind : String) -> Int? {\n  match kind {\n' +
    kinds.map(profile => `    ${literal(profile.kind)} => Some(${Math.max(...profile.requirements.map(value => value.length))})\n`).join('') +
    '    _ => None\n  }\n}\n\n' +
    '///|\npub fn requirements_valid(\n  kind : String,\n  requirements : Array[String],\n) -> Bool {\n  match kind {\n' +
    kinds.map(profile => `    ${literal(profile.kind)} => ` + profile.requirements.map(value => `requirements == ${literal(value)}`).join(' ||\n      ') + '\n').join('') +
    '    _ => false\n  }\n}\n\n' +
    '///|\nfn candidate_profile_flags(\n  subject : String,\n  phase : String,\n  kind : String,\n) -> (Bool, Bool, Bool)? {\n  match (subject, phase, kind) {\n' +
    contract.candidates.map(profile => `    (${literal(profile.subject)}, ${literal(profile.phase)}, ${literal(profile.kind)}) => Some((` +
      `${profile.approval === 'effect'}, ${profile.resolutionSubject === 'run'}, ${profile.preparedInvocationCid === 'summary.preparedInvocationCid'}))\n`).join('') +
    '    _ => None\n  }\n}\n\n' +
    '///|\nfn review_data_keys(version : String) -> Bool? {\n  match version {\n' +
    contract.reviews.map(profile => '    ' + literal(profile.version) + ' => Some(' + profile.dataKeys + ')\n').join('') +
    '    _ => None\n  }\n}\n';
}
