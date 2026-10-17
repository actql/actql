import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {checkInstallationPreparationBinding, installationPreparationBindingPath,
  installationPreparationFields, renderInstallationPreparationBinding,
  checkInstallationPreparationBridge, installationPreparationBridgePath,
  renderInstallationPreparationBridge} from './generate-credential-scope-binding.mjs';
import {installationPreparationRequestKeys, installationPreparationSubjectKeys} from
  '../adapters/host-common/installation-preparation-fields.generated.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const subject = readFileSync(join(root, 'src/remote_credential/installation_preparation_subject.mbt'), 'utf8');
const grant = readFileSync(join(root, 'src/remote_credential/installation_preparation_grant.mbt'), 'utf8');

test('metadata binding derives actual Common subject and per-use fields without Run stand-ins', () => {
  checkInstallationPreparationBinding(root);
  assert.deepEqual(installationPreparationSubjectKeys, [
    'accountConfigurationCid', 'accountId', 'connection', 'connectorRegistration',
    'connectorRevision', 'declarationSourceCid', 'installationRequestId', 'principal',
    'runtimeBundleCid', 'siteGeneration', 'siteKey',
  ]);
  assert.deepEqual(installationPreparationRequestKeys, [
    'metadataOccurrenceId', 'operation', 'requestBodyCid', 'requestMethod',
    'requestPath', 'resourceOrigin',
  ]);
  assert(Object.isFrozen(installationPreparationSubjectKeys));
  assert(Object.isFrozen(installationPreparationRequestKeys));
  assert(!installationPreparationSubjectKeys.includes('runInvocationCid'));
  assert(!installationPreparationSubjectKeys.includes('hostAdoptionCid'));
});

test('metadata typed bridge derives constructor and projection together from the same Owner', () => {
  checkInstallationPreparationBridge(root);
  const scratch = mkdtempSync(join(tmpdir(), 'installation-preparation-bridge-'));
  try {
    const path = join(scratch, installationPreparationBridgePath);
    const subjectPath = join(scratch, 'src/remote_credential/installation_preparation_subject.mbt');
    const grantPath = join(scratch, 'src/remote_credential/installation_preparation_grant.mbt');
    mkdirSync(dirname(path), {recursive: true}); mkdirSync(dirname(subjectPath), {recursive: true});
    writeFileSync(subjectPath, subject); writeFileSync(grantPath, grant);
    writeFileSync(path, renderInstallationPreparationBridge(subject, grant));
    checkInstallationPreparationBridge(scratch);
    const added = subject.replace('  principal : String', '  additional_original : String\n  principal : String');
    writeFileSync(subjectPath, added);
    const actual = renderInstallationPreparationBridge(added, grant);
    assert(actual.includes('  additional_original : String,'));
    assert(actual.includes('value.additional_original,'));
    assert.throws(() => checkInstallationPreparationBridge(scratch), /InstallationPreparationBridgeStale/u);
    writeFileSync(subjectPath, subject);
    writeFileSync(path, renderInstallationPreparationBridge(subject, grant)
      .replace('    value.declaration_source_cid,\n', ''));
    assert.throws(() => checkInstallationPreparationBridge(scratch), /InstallationPreparationBridgeStale/u);
  } finally { rmSync(scratch, {recursive: true, force: true}); }
});

test('new metadata Owner field or missing generated comparison independently fails freshness', () => {
  const scratch = mkdtempSync(join(tmpdir(), 'installation-preparation-binding-'));
  try {
    const path = join(scratch, installationPreparationBindingPath);
    mkdirSync(dirname(path), {recursive: true});
    writeFileSync(path, renderInstallationPreparationBinding(subject, grant));
    const changed = subject.replace('  principal : String', '  additional_original : String\n  principal : String');
    assert(installationPreparationFields(changed, grant).subject.includes('additionalOriginal'));
    assert.throws(() => checkInstallationPreparationBinding(scratch, changed, grant), /InstallationPreparationBindingStale/u);
    writeFileSync(path, renderInstallationPreparationBinding(subject, grant).replace("  'declarationSourceCid',\n", ''));
    assert.throws(() => checkInstallationPreparationBinding(scratch, subject, grant), /InstallationPreparationBindingStale/u);
    assert.throws(() => installationPreparationFields(subject,
      grant.replace('subject : InstallationPreparationSubject', 'foreign : InstallationPreparationSubject')),
    /InstallationPreparationOwnerFieldUnsupported/u);
  } finally { rmSync(scratch, {recursive: true, force: true}); }
});
