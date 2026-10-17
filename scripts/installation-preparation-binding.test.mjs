import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {checkInstallationPreparationBinding, installationPreparationBindingPath,
  installationPreparationFields, renderInstallationPreparationBinding} from './generate-credential-scope-binding.mjs';
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
