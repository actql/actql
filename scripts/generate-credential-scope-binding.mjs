// A read-only projection of the existing credential Owner's fields, not a
// second grant schema or an authorization implementation.
import {readFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
export const credentialScopeBindingPath = 'adapters/host-common/credential-scope-fields.generated.mjs';
const ownerPath = 'src/remote_credential/credential.mbt';
const preparationSubjectPath = 'src/remote_credential/installation_preparation_subject.mbt';
const preparationGrantPath = 'src/remote_credential/installation_preparation_grant.mbt';
export const installationPreparationBindingPath = 'adapters/host-common/installation-preparation-fields.generated.mjs';
export const installationPreparationBridgePath = 'src/connectors_builtin_node/client_installation_preparation_fields.generated.mbt';
// These existing Owner fields are deliberately NOT subject comparisons.
// Operation is checked separately for each invocation; time, revocation and
// use quota remain prepare_credential_use/authorize_credential_use decisions.
const separate = Object.freeze({
  operation: 'per-operation authorization',
  expires_unix_ms: 'trusted clock and lifetime',
  max_uses: 'durable use quota',
  grant_cid: 'derived grant identity',
});
const camel = name => name.replace(/_([a-z])/gu, (_, letter) => letter.toUpperCase());

export function credentialInvocationFields(source) {
  const match = /^struct RemoteCredentialGrant \{\n([^}]+)\n\}/mu.exec(source);
  if (match === null) throw new Error('CredentialGrantOwnerDeclarationMissing');
  const fields = match[1].trim().split('\n').map(line => {
    const field = /^\s*([a-z][a-z0-9_]*)\s*:\s*(String|Int|Int64)\s*$/u.exec(line);
    if (field === null) throw new Error('CredentialGrantOwnerFieldUnsupported');
    return field[1];
  });
  if (new Set(fields).size !== fields.length ||
      Object.keys(separate).some(field => !fields.includes(field))) {
    throw new Error('CredentialGrantOwnerFieldMismatch');
  }
  return fields.filter(field => !Object.hasOwn(separate, field)).map(camel);
}

export function renderCredentialScopeBinding(source) {
  const fields = credentialInvocationFields(source);
  return '// Generated from src/remote_credential/credential.mbt#RemoteCredentialGrant.\n' +
    '// Run scripts/generate-credential-scope-binding.mjs; do not edit the field list.\n' +
    '// Operation, expiry, quota and derived CID stay with their separate Owner checks.\n' +
    'export const credentialInvocationBindingKeys = Object.freeze([\n' +
    fields.map(field => `  '${field}',`).join('\n') + '\n]);\n';
}

export function checkCredentialScopeBinding(root = repository, source = readFileSync(join(root, ownerPath), 'utf8')) {
  if (readFileSync(join(root, credentialScopeBindingPath), 'utf8') !== renderCredentialScopeBinding(source)) {
    throw new Error('CredentialScopeBindingStale');
  }
}

// These are the actual Common declarations, not another scope schema. The
// original opaque subject travels separately; primitive fields cannot recreate
// its operational Host/Site/credential custody or provide authority.
function preparationOwnerFields(source, name, opaque = false) {
    const match = new RegExp(`^pub\\(all\\) struct ${name} \\{\\n([^}]+)\\n\\}`, 'mu').exec(source);
    if (match === null) throw new Error('InstallationPreparationOwnerDeclarationMissing');
    const fields = match[1].trim().split('\n').map(line => {
      const field = /^\s*([a-z][a-z0-9_]*)\s*:\s*(String|Int|Int64|InstallationPreparationSubject)\s*$/u.exec(line);
      if (field === null || (field[2] === 'InstallationPreparationSubject' &&
          (!opaque || field[1] !== 'subject')) ||
          (opaque && field[1] === 'subject' && field[2] !== 'InstallationPreparationSubject')) {
        throw new Error('InstallationPreparationOwnerFieldUnsupported');
      }
      return {name: field[1], type: field[2], key: camel(field[1])};
    });
    // Validate nominal custody before omitting it from the primitive vector.
    // An unchanged generated field list cannot prove a required opaque member.
    if (new Set(fields.map(field => field.name)).size !== fields.length ||
        (opaque && fields.filter(field => field.type === 'InstallationPreparationSubject').length !== 1)) {
      throw new Error('InstallationPreparationOwnerFieldMismatch');
    }
    return fields.filter(field => field.type !== 'InstallationPreparationSubject');
}

export function installationPreparationFields(subjectSource, grantSource) {
  return {subject: preparationOwnerFields(subjectSource, 'InstallationPreparationSubjectFields').map(field => field.key),
    request: preparationOwnerFields(grantSource, 'InstallationPreparationCredentialScope', true).map(field => field.key)};
}

export function renderInstallationPreparationBinding(subjectSource, grantSource) {
  const fields = installationPreparationFields(subjectSource, grantSource);
  return '// Generated from the existing remote_credential installation preparation declarations.\n' +
    '// DATA binding only; original opaque custody and per-use authority stay separate.\n' +
    ['subject', 'request'].map(kind =>
      `export const installationPreparation${kind === 'subject' ? 'Subject' : 'Request'}Keys = Object.freeze([\n` +
      fields[kind].map(field => `  '${field}',`).join('\n') + '\n]);\n').join('') +
    'export const installationPreparationSubjectKinds = Object.freeze([\n' +
    preparationOwnerFields(subjectSource, 'InstallationPreparationSubjectFields')
      .map(field => `  '${field.type}',`).join('\n') + '\n]);\n';
}

export function renderInstallationPreparationBridge(subjectSource, grantSource) {
  const subjects = preparationOwnerFields(subjectSource, 'InstallationPreparationSubjectFields');
  const requests = preparationOwnerFields(grantSource, 'InstallationPreparationCredentialScope', true);
  const prepare = (name, fields, subject) => `///|\n#export_name("clientInstallationPreparation${name}Prepare")\n` +
    `pub fn client_installation_preparation_${name.toLowerCase()}_prepare(\n` +
    (subject ? '  subject : @credential.InstallationPreparationSubject,\n' : '') +
    fields.map(field => `  ${field.name} : ${field.type},`).join('\n') +
    `\n) -> @credential.InstallationPreparation${name === 'Subject' ? 'Subject' : 'CredentialScope'} raise NodeHostFailure {\n` +
    `  match\n    @credential.${subject ? 'admit_installation_preparation_credential_scope' : 'prepare_installation_preparation_subject'}({\n` +
    (subject ? '      subject,\n' : '') + fields.map(field => `      ${field.name},`).join('\n') +
    '\n    }) {\n    Ok(value) => value\n    Err(issue) => raise RemoteCredential(issue)\n  }\n}\n';
  const projection = (name, fields) => `\n///|\n#export_name("clientInstallationPreparation${name}Fields")\n` +
    `pub fn client_installation_preparation_${name.toLowerCase()}_fields(\n` +
    `  value : @credential.InstallationPreparation${name === 'Subject' ? 'Subject' : 'CredentialScope'},\n` +
    ') -> Array[String] {\n' + (name === 'Subject' ? '  let value = value.fields()\n' : '') +
    '  [\n' + fields.map(field => `    value.${field.name}${field.type === 'String' ? '' : '.to_string()'},`).join('\n') + '\n  ]\n}\n';
  return '// Generated by scripts/generate-credential-scope-binding.mjs from the existing Common declarations.\n' +
    '// Primitive DATA projection only; no operational custody, authority or funding.\n\n' +
    prepare('Subject', subjects, false) + projection('Subject', subjects) + '\n' +
    prepare('Scope', requests, true) + projection('Scope', requests);
}

export function checkInstallationPreparationBridge(root = repository) {
  const expected = renderInstallationPreparationBridge(readFileSync(join(root, preparationSubjectPath), 'utf8'),
    readFileSync(join(root, preparationGrantPath), 'utf8'));
  if (readFileSync(join(root, installationPreparationBridgePath), 'utf8') !== expected) {
    throw new Error('InstallationPreparationBridgeStale');
  }
}

export function checkInstallationPreparationBinding(root = repository,
  subjectSource = readFileSync(join(root, preparationSubjectPath), 'utf8'),
  grantSource = readFileSync(join(root, preparationGrantPath), 'utf8')) {
  if (readFileSync(join(root, installationPreparationBindingPath), 'utf8') !==
      renderInstallationPreparationBinding(subjectSource, grantSource)) {
    throw new Error('InstallationPreparationBindingStale');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--write')) writeFileSync(join(repository, credentialScopeBindingPath),
    renderCredentialScopeBinding(readFileSync(join(repository, ownerPath), 'utf8')));
  checkCredentialScopeBinding();
  if (process.argv.includes('--write')) writeFileSync(join(repository, installationPreparationBindingPath),
    renderInstallationPreparationBinding(readFileSync(join(repository, preparationSubjectPath), 'utf8'),
      readFileSync(join(repository, preparationGrantPath), 'utf8')));
  checkInstallationPreparationBinding();
  if (process.argv.includes('--write')) writeFileSync(join(repository, installationPreparationBridgePath),
    renderInstallationPreparationBridge(readFileSync(join(repository, preparationSubjectPath), 'utf8'),
      readFileSync(join(repository, preparationGrantPath), 'utf8')));
  checkInstallationPreparationBridge();
  // Human diagnostics must not prefix npm pack --json metadata on stdout.
  console.error('Credential invocation fields match the existing Owner');
}
