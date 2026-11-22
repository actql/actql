import {types as nodeTypes} from 'node:util';
import {declaredRowUpdateKinds} from '../host-common/owned-invocation-context.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';

type DriverCallback = (...args: never[]) => unknown;
type DriverCandidate = Readonly<{
  kinds?: unknown;
  prepareRequest?: unknown;
  requestFacts?: unknown;
  writeOperation?: unknown;
  send?: unknown;
  prepareUpdateWrite?: unknown;
  operation?: unknown;
  project?: unknown;
  footprint?: unknown;
  describe?: unknown;
  recheckRequests?: unknown;
  issueCapability?: unknown;
  observeTargets?: unknown;
  recoveryEntry?: unknown;
  recoverRequests?: unknown;
  recoverMemberRequests?: unknown;
  requestCid?: unknown;
  checkRequest?: unknown;
  confirmResponse?: unknown;
  finalizeRequest?: unknown;
  capabilityRequestCid?: unknown;
  assertRequestFinalized?: unknown;
  admitTargetReadApproval?: unknown;
  prepareRequestChild?: unknown;
  prepareRecoveredContentChild?: unknown;
  confirmation?: unknown;
  check?: Readonly<{resource?: unknown; operation?: unknown}> | null;
  targetRead?: Readonly<{operation?: unknown}> | null;
}>;
type CheckedDriver = DriverCandidate & Readonly<{
  prepareRequest: DriverCallback;
  requestFacts: DriverCallback;
  project: DriverCallback;
  footprint: DriverCallback;
}>;
type BoundHook<Driver> = Readonly<{
  resource: string; operation: string; request: DriverCallback; receiver: Driver;
}>;
type EffectResources = {
  bindRunOriginal(facts: unknown): unknown;
  assertCurrent(original: unknown): unknown;
  limits(original: unknown): unknown;
};
type DriverControls = Readonly<{
  fail(code: string): never;
  text(value: unknown): value is string;
  optionalFunction(value: unknown): boolean;
  kinds: readonly string[];
  guarded(kind: unknown): boolean;
}>;

export function createInstalledRowEffectDriverControls({fail, text, optionalFunction, kinds, guarded}: DriverControls) {
  const reject: DriverControls['fail'] = fail;

  function captureEffectResources(receiver: unknown): Readonly<EffectResources> | undefined {
    if (receiver === undefined) return undefined;
    const methods: Partial<EffectResources> = {};
    for (const name of ['bindRunOriginal', 'assertCurrent', 'limits'] as const) {
      const field = receiver === null || typeof receiver !== 'object'
        ? undefined : Object.getOwnPropertyDescriptor(receiver, name);
      if (field === undefined || !Object.hasOwn(field, 'value') ||
          typeof field.value !== 'function') reject('InstalledEffectResourcesUnavailable');
      const method = field.value as (...args: unknown[]) => unknown;
      methods[name] = (...args: unknown[]) => Reflect.apply(method, receiver, args);
    }
    return Object.freeze(methods) as EffectResources;
  }

  function requireSynchronousEffectResource<Value>(value: Value): Exclude<Value, PromiseLike<unknown>> {
    if (typeof (value as {then?: unknown} | null | undefined)?.then === 'function') {
      void Promise.resolve(value).catch(() => {});
      reject('InstalledEffectResourcesUnavailable');
    }
    return value as Exclude<Value, PromiseLike<unknown>>;
  }

  // Reobserve a legacy driver's kinds at each owner check. An admitted
  // declaration has the one fixed UPDATE kind from its selected write slot.
  function installedEffectKinds({owned, updateWriteSlot}: {owned: {kinds?: readonly string[]}; updateWriteSlot?: unknown}) {
    return updateWriteSlot === undefined ? owned.kinds : declaredRowUpdateKinds;
  }

  function installedEffectWriteOperation<Member>(driver: {writeOperation?: (member: Member) => unknown; operation?: unknown},
      member: Member, updateWriteSlot: unknown) {
    return updateWriteSlot === undefined ? driver.writeOperation!(member) : driver.operation;
  }

  function checkDriver(driver: DriverCandidate | null | undefined, declaredUpdate = false): CheckedDriver {
    const supportedKinds = declaredUpdate ? declaredRowUpdateKinds : driver?.kinds;
    if (driver === null || typeof driver !== 'object' ||
        !Array.isArray(supportedKinds) || supportedKinds.length === 0 ||
        supportedKinds.some(kind => !kinds.includes(kind)) ||
        typeof driver.prepareRequest !== 'function' ||
        typeof driver.requestFacts !== 'function' ||
        (declaredUpdate
          ? !Object.isFrozen(driver) || ![Object.prototype, null].includes(Object.getPrototypeOf(driver)) ||
            'kinds' in driver || 'writeOperation' in driver ||
            'send' in driver || !text(Object.getOwnPropertyDescriptor(driver, 'operation')?.value) ||
            typeof Object.getOwnPropertyDescriptor(driver, 'prepareUpdateWrite')?.value !== 'function' ||
            nodeTypes.isProxy(driver.prepareUpdateWrite) || nodeTypes.isAsyncFunction(driver.prepareUpdateWrite)
          : typeof driver.writeOperation !== 'function' || typeof driver.send !== 'function') ||
        typeof driver.project !== 'function' ||
        typeof driver.footprint !== 'function' ||
        ![driver.describe, driver.recheckRequests, driver.issueCapability,
          driver.observeTargets, driver.recoveryEntry, driver.recoverRequests,
          driver.recoverMemberRequests,
          driver.requestCid, driver.checkRequest, driver.confirmResponse, driver.finalizeRequest,
          driver.capabilityRequestCid, driver.assertRequestFinalized,
          driver.admitTargetReadApproval, driver.prepareRequestChild,
          driver.prepareRecoveredContentChild].every(optionalFunction) ||
        (driver.check !== undefined && (!text(driver.check?.resource) ||
          !text(driver.check.operation) ||
          typeof driver.checkRequest !== 'function')) ||
        (supportedKinds.some(guarded) && (!text(driver.targetRead?.operation) ||
          typeof driver.observeTargets !== 'function' ||
          typeof driver.recoverRequests !== 'function' ||
          typeof driver.requestCid !== 'function')) ||
        (supportedKinds.includes('command') &&
          (typeof driver.recheckRequests !== 'function' ||
            typeof driver.recoveryEntry !== 'function' ||
            typeof driver.recoverRequests !== 'function' ||
            typeof driver.requestCid !== 'function')) ||
        ((driver.recoveryEntry === undefined) !==
          (driver.recoverRequests === undefined)) ||
        (driver.recoverMemberRequests !== undefined &&
          driver.recoverRequests === undefined) ||
        ((driver.finalizeRequest === undefined) !== (driver.capabilityRequestCid === undefined)) ||
        ((driver.finalizeRequest === undefined) !== (driver.assertRequestFinalized === undefined)) ||
        ((driver.confirmation === undefined) !== (driver.confirmResponse === undefined)) ||
        // Recovery identifies each rebuilt request by `requestCid`.
        (driver.recoverRequests !== undefined &&
          typeof driver.requestCid !== 'function')) {
      reject('InvalidInstalledRowEffectDriver');
    }
    return driver as CheckedDriver;
  }

  // Optional fixed CREATE check repeated immediately before its mutation. This
  // captures the original pure descriptor/callback, not a read decision/grant.
  // The corresponding DISTINCT physical occurrence must already be declared.
  function captureBeforeSendCheck<Driver extends {kinds?: readonly string[]}>(driver: Driver,
      recipe: InstalledEffectPlanRecipe | undefined): BoundHook<Driver> | undefined {
    const selected = recipe?.credentialOperations?.find(entry => entry.phase === 'write-check');
    const checkField = Object.getOwnPropertyDescriptor(driver, 'check');
    const check = checkField !== undefined && Object.hasOwn(checkField, 'value') ? checkField.value : undefined;
    if (check === undefined) {
      if (selected !== undefined) reject('InstalledEffectWriteCheckUnavailable');
      return undefined;
    }
    if (nodeTypes.isProxy(check)) reject('InvalidInstalledEffectWriteCheck');
    const flag = Object.getOwnPropertyDescriptor(check, 'beforeSend');
    if (flag === undefined || (Object.hasOwn(flag, 'value') && flag.value === false)) {
      if (selected !== undefined) reject('InstalledEffectWriteCheckUnavailable');
      return undefined;
    }
    if (!Object.hasOwn(flag, 'value') || flag.value !== true || !Object.isFrozen(check) ||
        !Object.hasOwn(checkField!, 'value') || selected === undefined ||
        driver.kinds!.length !== 1 || driver.kinds![0] !== 'create') reject('InvalidInstalledEffectWriteCheck');
    const fields = Object.getOwnPropertyDescriptors(check);
    const request = Object.getOwnPropertyDescriptor(driver, 'checkRequest');
    if (Reflect.ownKeys(fields).length !== 3 ||
        ['resource','operation','beforeSend'].some(name => !Object.hasOwn(fields[name] ?? {}, 'value')) ||
        !text(fields.resource.value) || !text(fields.operation.value) ||
        !request || !Object.hasOwn(request, 'value') || typeof request.value !== 'function' ||
        recipe!.rowOperations[selected.operationIndex].operation !== fields.operation.value) {
      reject('InvalidInstalledEffectWriteCheck');
    }
    return Object.freeze({resource: fields.resource.value, operation: fields.operation.value,
      request: request.value as DriverCallback, receiver: driver});
  }

  // Original fixed read hook, not a credential or mutation capability. Initial
  // and cold confirmation must each have its own existing physical occurrence.
  function captureResponseConfirmation<Driver extends object>(driver: Driver,
      recipe: InstalledEffectPlanRecipe | undefined): BoundHook<Driver> | undefined {
    const phases = ['apply-confirm', 'resume-confirm'];
    const selected = recipe?.credentialOperations?.filter(entry => phases.includes(entry.phase)) ?? [];
    const field = Object.getOwnPropertyDescriptor(driver, 'confirmation');
    if (field === undefined) {
      if (selected.length !== 0) reject('InstalledEffectConfirmationUnavailable');
      return undefined;
    }
    if (!Object.hasOwn(field, 'value') || field.value === null || typeof field.value !== 'object' ||
        nodeTypes.isProxy(field.value) || !Object.isFrozen(field.value)) reject('InvalidInstalledEffectConfirmation');
    const fields = Object.getOwnPropertyDescriptors(field.value);
    const request = Object.getOwnPropertyDescriptor(driver, 'confirmResponse');
    if (Reflect.ownKeys(fields).length !== 4 ||
        ['resource', 'operation', 'maxRequestBytes', 'maxResponseBytes'].some(name =>
          !Object.hasOwn(fields[name] ?? {}, 'value')) ||
        !text(fields.resource.value) || !text(fields.operation.value) ||
        ![fields.maxRequestBytes.value, fields.maxResponseBytes.value].every(value => Number.isSafeInteger(value) && value > 0) ||
        !request || !Object.hasOwn(request, 'value') || typeof request.value !== 'function') {
      reject('InvalidInstalledEffectConfirmation');
    }
    const used = new Set((recipe?.credentialOperations ?? [])
      .filter(entry => !phases.includes(entry.phase)).map(entry => entry.operationIndex));
    for (const original of [recipe?.requestConstruction, recipe?.requestFinalization]) {
      if (original !== undefined) used.add(original.operationIndex);
    }
    for (const phase of phases) {
      const matches = selected.filter(entry => entry.phase === phase);
      const entry = matches[0], index = entry?.operationIndex as number;
      if (matches.length !== 1 || !Number.isSafeInteger(index) || index < 0 ||
          index >= (recipe?.rowOperations?.length ?? 0) || used.has(index) ||
          recipe!.rowOperations[index].operation !== fields.operation.value ||
          ![entry.maxRequestBytes, entry.maxResponseBytes].every(value => Number.isSafeInteger(value) && value > 0) ||
          entry.maxRequestBytes < fields.maxRequestBytes.value || entry.maxResponseBytes < fields.maxResponseBytes.value) {
        reject('InstalledEffectConfirmationPlanUnavailable');
      }
      used.add(index);
    }
    return Object.freeze({resource: fields.resource.value, operation: fields.operation.value,
      request: request.value as DriverCallback, receiver: driver});
  }

  return {captureEffectResources, requireSynchronousEffectResource, installedEffectKinds,
    installedEffectWriteOperation, checkDriver, captureBeforeSendCheck, captureResponseConfirmation};
}
