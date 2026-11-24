// Standard Local bootstrap in the existing Host/Account initialization owner.
// Common owns the complete policy; these writes record actual exclusive first
// adoption, not permits inferred from a missing file or a profile label.
import {lstat, mkdir, open} from 'node:fs/promises';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {readBoundedConfigurationUtf8, withOriginalFile} from './source-profile-json.mjs';
import {readHostRootAccountAdoption, adoptHostRootAccount, type admitHostRootFormat} from './host-root-format.mjs';
import {assertOriginalPreparedLocalPublicationStoreOwnership} from '../store-local/publication-store.mjs';
import {canonicalJson, contentCid, bytesCid} from './local-account-config.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {isAccountConstruction, readAccountOriginal} from './account-construction.mjs';
import {runtimeField, runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';

import type {createAccountConstruction} from './account-construction.mjs';
import type {loadExecutionAuthorizationRuntime} from './authorization.mjs';

type Construction = ReturnType<typeof createAccountConstruction>;
type Frame = ReturnType<Construction['begin']>;
type AuthorizationRuntime = Awaited<ReturnType<typeof loadExecutionAuthorizationRuntime>>;
type Runtime = Pick<AuthorizationRuntime, 'executionAuthorizationAdmit' | 'executionAuthorizationAccountJson'> &
  Readonly<{
    clientProgramLocalStandardAccountProfile(): unknown;
    clientProgramLocalStandardAccountConfiguration(...args: AccountArguments): unknown;
    clientProgramLocalStandardAccountConfigurationPrepared(...args: [...AccountArguments, Frame['core']]): unknown;
  }>;
type AccountArguments = [string, string, string, readonly string[], readonly Record<string, unknown>[],
  Record<string, unknown> | undefined, string | undefined];
type Selection = Readonly<{accountConfig?: string | null; accountConfiguration?: string | null}>;
type BootstrapInputs<Authorization> = Readonly<{
  root: string;
  principal: string;
  preparedOriginal: unknown;
  rootCreation: Awaited<ReturnType<typeof admitHostRootFormat>>;
  operatorAuthorization?: Authorization & Selection;
}>;
type SubjectPair = readonly [string, string];
type TupleFields = Pick<SubjectPair, 0 | 1>;
type Subjects = Readonly<{
  controlConnection: string;
  configuredConnections: readonly string[];
  modelTasks: readonly SubjectPair[];
  requestTarget?: SubjectPair;
  signingKeyResource?: string;
}>;
type Store = Readonly<{status(): Readonly<{closed: boolean}>}>;
type Adoption<Authorization> = Readonly<Omit<Authorization, 'accountConfig' | 'siteKey'> & {accountConfig: string; siteKey: string}>;
type InitializationIntent = Readonly<{version: string; record_id: string; account_id: string; principal: string}>;

const maximum = 1_000_000;
const fail: (code: string, cause?: unknown) => never = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
const exact = (value: unknown, fields: readonly string[]) => value !== null && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...fields].sort().join('\0');

export async function prepareOrdinaryLocalAccount<Authorization extends object = Selection>(
  {accountConstruction, ...options}: BootstrapInputs<Authorization> & Readonly<{accountConstruction?: Construction}>) {
  if (accountConstruction === undefined) return prepareOrdinaryLocalAccountOriginal(options);
  if (!isAccountConstruction(accountConstruction)) fail('ForeignAccountConstruction');
  const frame = accountConstruction.begin();
  try {
    const result = await prepareOrdinaryLocalAccountOriginal(options, frame, accountConstruction);
    if (result !== undefined) frame.hold();
    frame.finish(result !== undefined);
    return result;
  } catch (cause) {frame.failure(cause); frame.finish(false); throw cause;}
}

async function prepareOrdinaryLocalAccountOriginal<Authorization extends object>(
  {root, principal, preparedOriginal, rootCreation, operatorAuthorization}: BootstrapInputs<Authorization>,
  frame?: Frame, construction?: Construction) {
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
  async function readOptional(path: string) {
    current();
    let state;
    try { state = await lstat(path); }
    catch (cause) { if ((cause as NodeJS.ErrnoException | undefined)?.code === 'ENOENT') return undefined; throw cause; }
    if (!state.isFile() || state.isSymbolicLink() || (state.mode & 0o077) !== 0) {
      fail('LocalAccountInitializationExposed');
    }
    const wire = frame === undefined ? await readBoundedConfigurationUtf8(path, {maxBytes: maximum})
      : await readAccountOriginal(path, frame);
    current();
    return wire;
  }
  const syncDirectory = (path: string) => withOriginalFile(path,
    original => open(original, 'r'), original => original.sync());
  async function createOriginal(path: string, wire: string, parent: string) {
    current();
    if (frame === undefined && Buffer.byteLength(wire, 'utf8') > maximum) fail('LocalAccountInitializationLimit');
    if (frame !== undefined) {
      const bytes = BigInt(Buffer.byteLength(wire, 'utf8'));
      frame.prepare(0n, 128n + 3n * bytes);
    }
    try {
      await withOriginalFile(path, original => open(original, 'wx', 0o600), async handle => {
        current(); await handle.writeFile(wire, 'utf8'); await handle.sync(); current();
      });
    } catch (cause) {
      if ((cause as NodeJS.ErrnoException | undefined)?.code !== 'EEXIST') throw cause;
      if (await readOptional(path) !== wire) fail('LocalAccountInitializationConflict', cause);
    }
    await syncDirectory(parent); current();
  }
  const parse = (wire: string): unknown => {
    frame?.nativeJson(wire);
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
    catch (cause) { if ((cause as NodeJS.ErrnoException | undefined)?.code !== 'ENOENT') throw cause; }
    frame?.record(BigInt(principal.length) + 256n, 16n, 3n);
    intentWire = canonicalJson({version: 'actql-local-account-initialization/0.1',
      record_id: randomUUID(), account_id: 'local-' + randomUUID(), principal});
    await createOriginal(intentPath, intentWire, root);
  }
  // The exact key and scalar checks below establish this persisted intent shape.
  const intent = parse(intentWire) as InitializationIntent;
  if (!exact(intent, ['version', 'record_id', 'account_id', 'principal']) ||
      intent.version !== 'actql-local-account-initialization/0.1' || intent.principal !== principal ||
      ![intent.record_id, intent.account_id].every(value => typeof value === 'string' &&
        value.length > 0 && value.length <= 128)) fail('LocalAccountInitializationInvalid');
  frame?.prepare(0n, 256n + 3n * BigInt(Buffer.byteLength(intentWire, 'utf8')));
  const initializationCid = bytesCid(Buffer.from(intentWire, 'utf8'));
  if (adopted !== undefined && (adopted.initialization_cid !== initializationCid ||
      adopted.account_id !== intent.account_id || adopted.record_id !== intent.record_id)) {
    fail('LocalAccountInitializationChanged');
  }
  if (adopted !== undefined && await readOptional(join(root, 'publication', 'store.json')) === undefined) {
    fail('LocalAccountAdoptedStateMissing');
  }
  let flight: Promise<Adoption<Authorization>> | undefined;
  return Object.freeze({adopt(moon: Runtime, subjects: Subjects, store: Store) {
    if (flight !== undefined) return flight;
    // Retain the actual Store before any current/metadata await. This does
    // not infer ownership from status: current() checks the nominal exclusion.
    const originalStore = store, originalStatus = store.status;
    flight = Promise.resolve().then(async () => {
      const initialFrame = frame;
      const adoptionFrame = construction?.begin();
      if (adoptionFrame !== undefined) frame = adoptionFrame;
      try {
      current();
      if (typeof originalStatus !== 'function' ||
          Reflect.apply(originalStatus, originalStore, []).closed !== false) {
        fail('LocalAccountInitializationChanged');
      }
      frame?.record(1024n, 48n, 4n);
      const profile = moon.clientProgramLocalStandardAccountProfile();
      const identity = {profile_id: runtimeField(profile, 0), profile_version: runtimeField(profile, 1),
        profile_cid: runtimeField(profile, 2)};
      if (identity.profile_id !== 'actql-local-standard' || identity.profile_version !== '0.1' ||
          typeof runtimeField(profile, 3) !== 'string' ||
          contentCid(parse(runtimeField(profile, 3) as string)) !== identity.profile_cid) {
        fail('LocalAccountProfileUnavailable');
      }
      if (frame !== undefined) {
        let units = BigInt(intent.account_id.length + principal.length + subjects.controlConnection.length);
        for (const connection of subjects.configuredConnections) units += BigInt(connection.length);
        for (const task of subjects.modelTasks) units += BigInt(task[0].length + task[1].length);
        if (subjects.requestTarget !== undefined) units += BigInt(subjects.requestTarget[0].length + subjects.requestTarget[1].length);
        if (subjects.signingKeyResource !== undefined) units += BigInt(subjects.signingKeyResource.length);
        frame.record(units + 512n, 48n + 8n * BigInt(subjects.configuredConnections.length + subjects.modelTasks.length), 6n);
      }
      const materialize = frame === undefined ? moon.clientProgramLocalStandardAccountConfiguration
        : moon.clientProgramLocalStandardAccountConfigurationPrepared;
      // Selection and the final reservation argument use the same frame test.
      const generated = Reflect.apply(materialize as (...args: [...AccountArguments, Frame['core']?]) => unknown, moon, [

        intent.account_id, principal, subjects.controlConnection, subjects.configuredConnections,
        subjects.modelTasks.map(runtimeTupleFromFields as (fields: TupleFields) => Record<string, unknown>),
        subjects.requestTarget === undefined ? undefined : runtimeTupleFromFields(subjects.requestTarget as TupleFields),
        subjects.signingKeyResource, ...(frame === undefined ? [] : [frame.core])]);
      frame?.assert();
      if (generated === undefined) fail('LocalAccountConstructionUnavailable');
      const configuration = checked(generated);
      if (typeof configuration !== 'string') fail('InvalidHostRuntimeResult');
      const subjectCid = contentCid(subjects);
      frame?.record(BigInt(configuration.length) + 1024n, 48n, 6n);
      const configurationCid = contentCid(parse(configuration));
      const materialWire = canonicalJson({profile: identity, subjectCid, configuration,
        initializationCid, configurationCid});
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
      const account = frame === undefined ? moon.executionAuthorizationAdmit(currentWire) : frame.admit(moon, currentWire);
      frame?.nativeJson(currentWire);
      const state = JSON.parse(moon.executionAuthorizationAccountJson(account));
      if (state.state !== 'admitted' || state.account_id !== intent.account_id) {
        fail('LocalAccountConfigurationRejected');
      }
      const record = {record_id: intent.record_id, account_id: intent.account_id,
        configuration_cid: configurationCid, initialization_cid: initializationCid,
        subject_cid: subjectCid, profile: identity};
      await adoptHostRootAccount(root, preparedOriginal, record);
      current();
      if (Reflect.apply(originalStatus, originalStore, []).closed !== false) {
        fail('LocalAccountInitializationChanged');
      }
      return Object.freeze({...operatorAuthorization, accountConfig: configPath,
        siteKey: subjects.controlConnection}) as Adoption<Authorization>;
      } catch (cause) {adoptionFrame?.failure(cause); throw cause;}
      finally {
        // Bootstrap values live with this same durable preparation until Host
        // close; a rejected/partial child is never refunded by Promise failure.
        adoptionFrame?.hold(); adoptionFrame?.finish(true);
        frame = initialFrame;
      }
    });
    return flight;
  }});
}
