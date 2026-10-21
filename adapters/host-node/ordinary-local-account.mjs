// Standard Local bootstrap in the existing Host/Account initialization owner.
// Common owns the complete policy; these writes record actual exclusive first
// adoption, not permits inferred from a missing file or a profile label.
import {lstat, mkdir, open} from 'node:fs/promises';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {readBoundedConfigurationUtf8, withOriginalFile} from './source-profile-json.mjs';
import {readHostRootAccountAdoption, adoptHostRootAccount} from './host-root-format.mjs';
import {assertOriginalPreparedLocalPublicationStoreOwnership} from '../store-local/publication-store.mjs';
import {canonicalJson, contentCid, bytesCid} from './local-account-config.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';

const maximum = 1_000_000;
const fail = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
const exact = (value, fields) => value !== null && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...fields].sort().join('\0');

export async function prepareOrdinaryLocalAccount({root, principal, preparedOriginal,
  rootCreation, operatorAuthorization}) {
  if (operatorAuthorization !== undefined && (operatorAuthorization === null ||
      typeof operatorAuthorization !== 'object' || Array.isArray(operatorAuthorization))) {
    fail('InvalidLocalAccountAuthorization');
  }
  // An explicitly selected configuration replaces bootstrap routing. Never
  // merge, overwrite, or turn its null/invalid/unreadable value into absence.
  if (operatorAuthorization?.accountConfig !== undefined ||
      operatorAuthorization?.accountConfiguration !== undefined) return undefined;
  const current = () => assertOriginalPreparedLocalPublicationStoreOwnership(
    preparedOriginal, join(root, 'publication'));
  current();
  const intentPath = join(root, 'account-initialization.json');
  const directory = join(root, 'account');
  const materialPath = join(directory, 'bootstrap.json');
  const configPath = join(directory, 'account.json');
  async function readOptional(path) {
    current();
    let state;
    try { state = await lstat(path); }
    catch (cause) { if (cause?.code === 'ENOENT') return undefined; throw cause; }
    if (!state.isFile() || state.isSymbolicLink() || (state.mode & 0o077) !== 0) {
      fail('LocalAccountInitializationExposed');
    }
    const wire = await readBoundedConfigurationUtf8(path, {maxBytes: maximum});
    current();
    return wire;
  }
  const syncDirectory = path => withOriginalFile(path,
    original => open(original, 'r'), original => original.sync());
  async function createOriginal(path, wire, parent) {
    current();
    if (Buffer.byteLength(wire, 'utf8') > maximum) fail('LocalAccountInitializationLimit');
    try {
      await withOriginalFile(path, original => open(original, 'wx', 0o600), async handle => {
        current(); await handle.writeFile(wire, 'utf8'); await handle.sync(); current();
      });
    } catch (cause) {
      if (cause?.code !== 'EEXIST') throw cause;
      if (await readOptional(path) !== wire) fail('LocalAccountInitializationConflict', cause);
    }
    await syncDirectory(parent); current();
  }
  const parse = wire => {
    try { return JSON.parse(wire); } catch (cause) { fail('LocalAccountInitializationInvalid', cause); }
  };
  const adopted = await readHostRootAccountAdoption(root, preparedOriginal);
  let intentWire = await readOptional(intentPath);
  if (intentWire === undefined) {
    if (adopted !== undefined) fail('LocalAccountAdoptedStateMissing');
    if (rootCreation !== 'new') fail('LocalAccountFirstInitializationUnavailable');
    // A pre-existing default-area file is not an authored selection or a
    // reason to overwrite operator material, even on this fresh Host root.
    try { await lstat(directory); fail('LocalAccountInitializationConflict'); }
    catch (cause) { if (cause?.code !== 'ENOENT') throw cause; }
    intentWire = canonicalJson({version: 'actql-local-account-initialization/0.1',
      record_id: randomUUID(), account_id: 'local-' + randomUUID(), principal});
    await createOriginal(intentPath, intentWire, root);
  }
  const intent = parse(intentWire);
  if (!exact(intent, ['version', 'record_id', 'account_id', 'principal']) ||
      intent.version !== 'actql-local-account-initialization/0.1' || intent.principal !== principal ||
      ![intent.record_id, intent.account_id].every(value => typeof value === 'string' &&
        value.length > 0 && value.length <= 128)) fail('LocalAccountInitializationInvalid');
  const initializationCid = bytesCid(Buffer.from(intentWire, 'utf8'));
  if (adopted !== undefined && (adopted.initialization_cid !== initializationCid ||
      adopted.account_id !== intent.account_id || adopted.record_id !== intent.record_id)) {
    fail('LocalAccountInitializationChanged');
  }
  if (adopted !== undefined && await readOptional(join(root, 'publication', 'store.json')) === undefined) {
    fail('LocalAccountAdoptedStateMissing');
  }
  let flight;
  return Object.freeze({adopt(moon, subjects, store) {
    if (flight !== undefined) return flight;
    // Retain the actual Store before any current/metadata await. This does
    // not infer ownership from status: current() checks the nominal exclusion.
    const originalStore = store, originalStatus = store.status;
    flight = Promise.resolve().then(async () => {
      current();
      if (typeof originalStatus !== 'function' ||
          Reflect.apply(originalStatus, originalStore, []).closed !== false) {
        fail('LocalAccountInitializationChanged');
      }
      const profile = moon.clientProgramLocalStandardAccountProfile();
      const identity = {profile_id: runtimeField(profile, 0), profile_version: runtimeField(profile, 1),
        profile_cid: runtimeField(profile, 2)};
      if (identity.profile_id !== 'actql-local-standard' || identity.profile_version !== '0.1' ||
          typeof runtimeField(profile, 3) !== 'string' ||
          contentCid(parse(runtimeField(profile, 3))) !== identity.profile_cid) {
        fail('LocalAccountProfileUnavailable');
      }
      const configuration = checked(moon.clientProgramLocalStandardAccountConfiguration(
        intent.account_id, principal, subjects.controlConnection, subjects.configuredConnections,
        subjects.modelTasks.map(runtimeTupleFromFields),
        subjects.requestTarget === undefined ? undefined : runtimeTupleFromFields(subjects.requestTarget),
        subjects.signingKeyResource));
      if (typeof configuration !== 'string') fail('InvalidHostRuntimeResult');
      const subjectCid = contentCid(subjects);
      const materialWire = canonicalJson({profile: identity, subjectCid, configuration,
        initializationCid, configurationCid: contentCid(parse(configuration))});
      let material = await readOptional(materialPath);
      if (adopted === undefined) {
        if (material === undefined) {
          await mkdir(directory, {recursive: true, mode: 0o700}); current();
          await createOriginal(materialPath, materialWire, directory);
          material = materialWire;
          // This same first materialization may create its configuration.
          // A retained material record with a missing configuration does NOT
          // prove creation never happened, even before final adoption.
          if (await readOptional(configPath) === undefined) {
            await createOriginal(configPath, configuration, directory);
          }
        }
        await syncDirectory(root); current();
      }
      if (material === undefined) fail('LocalAccountAdoptedStateMissing');
      if (material !== materialWire) fail('LocalAccountInitializationChanged');
      const currentWire = await readOptional(configPath);
      if (currentWire === undefined) fail('LocalAccountAdoptedStateMissing');
      // Current operator restrictions are authoritative. Verify the actual
      // Account/identity without restoring or merging the generated grants.
      const account = moon.executionAuthorizationAdmit(currentWire);
      const state = JSON.parse(moon.executionAuthorizationAccountJson(account));
      if (state.state !== 'admitted' || state.account_id !== intent.account_id) {
        fail('LocalAccountConfigurationRejected');
      }
      const record = {record_id: intent.record_id, account_id: intent.account_id,
        configuration_cid: contentCid(parse(configuration)), initialization_cid: initializationCid,
        subject_cid: subjectCid, profile: identity};
      await adoptHostRootAccount(root, preparedOriginal, record);
      current();
      if (Reflect.apply(originalStatus, originalStore, []).closed !== false) {
        fail('LocalAccountInitializationChanged');
      }
      return Object.freeze({...operatorAuthorization, accountConfig: configPath,
        siteKey: subjects.controlConnection});
    });
    return flight;
  }});
}
