import {types as nodeTypes} from 'node:util';
import {effectLedgerImplementationBounds} from './effect-ledger-implementation-bounds.mjs';

type Operation = Readonly<{operation: string; extent: object}>;
type CapturedCallback = (...args: never[]) => unknown;
type Construction = Readonly<{operationIndex: number; inputExtent?: CapturedCallback}>;
type OwnedConstruction = Readonly<{receiver: object; method: CapturedCallback; capacity: object}>;
type SavedControlCodec = Readonly<{maxEntryBytes: number; maxResponseBytes?: number; fallbackCapacity: object}>;
type CredentialOperation = Readonly<{
  phase: string;
  operationIndex: number;
  maxRequestBytes: number;
  maxResponseBytes: number;
  maxTargetBytes?: number;
  perRow?: boolean;
  slot?: string;
  resource?: string;
  responseExtent?: CapturedCallback;
  discardResponseProjection?: true;
}>;
type OwnedReadOperation = Readonly<{phase: string; operationIndex: number}>;
type PhysicalWrite = Readonly<{operationIndex: number; transferBytes: bigint;
  inputExtent?: (bytes: number, requestUnits: number) => unknown}>;
export type InstalledEffectPlanRecipe = Readonly<{
  memberOperations: readonly Operation[];
  rowOperations: readonly Operation[];
  controlsPerRow?: object;
  savedControlCodec?: SavedControlCodec;
  requestConstruction?: Construction;
  requestFinalization?: Readonly<{operationIndex: number}>;
  captureConstruction?: Construction;
  recoveryConstruction?: Construction;
  footprintConstruction?: Construction;
  grantConstruction?: OwnedConstruction;
  projectConstruction?: OwnedConstruction;
  credentialOperations?: readonly CredentialOperation[];
  ownedReadOperations?: readonly OwnedReadOperation[];
  physicalWrite?: PhysicalWrite;
}>;

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;

export {fail as rejectInstalledEffectPlan, text as installedEffectPlanText};

export function captureInstalledEffectPlanRecipe(recipe: object, maxOperations: number): InstalledEffectPlanRecipe;
export function captureInstalledEffectPlanRecipe(recipe: unknown, maxOperations: number): InstalledEffectPlanRecipe | undefined;
export function captureInstalledEffectPlanRecipe(recipe: unknown, maxOperations: number): InstalledEffectPlanRecipe | undefined {
  if (recipe === undefined) return undefined;
  if (recipe === null || typeof recipe !== 'object' || nodeTypes.isProxy(recipe)) fail('InvalidInstalledEffectPlanRecipe');
  if (!Number.isSafeInteger(maxOperations) || maxOperations < 1) fail('InvalidInstalledEffectPlanRecipe');
  const own = (value: unknown, names: readonly string[]) => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value) ||
        !Object.isFrozen(value)) fail('InvalidInstalledEffectPlanRecipe');
    const fields = Object.getOwnPropertyDescriptors(value);
    if (Reflect.ownKeys(fields).length !== names.length ||
        names.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    return fields;
  };
  const fields = own(recipe, ['memberOperations', 'rowOperations',
    ...(Object.hasOwn(recipe, 'controlsPerRow') ? ['controlsPerRow'] : []),
    ...(Object.hasOwn(recipe, 'savedControlCodec') ? ['savedControlCodec'] : []),
    ...(Object.hasOwn(recipe, 'requestConstruction') ? ['requestConstruction'] : []),
    ...(Object.hasOwn(recipe, 'requestFinalization') ? ['requestFinalization'] : []),
    ...(Object.hasOwn(recipe, 'captureConstruction') ? ['captureConstruction'] : []),
    ...(Object.hasOwn(recipe, 'recoveryConstruction') ? ['recoveryConstruction'] : []),
    ...(Object.hasOwn(recipe, 'footprintConstruction') ? ['footprintConstruction'] : []),
    ...(Object.hasOwn(recipe, 'grantConstruction') ? ['grantConstruction'] : []),
    ...(Object.hasOwn(recipe, 'projectConstruction') ? ['projectConstruction'] : []),
    ...(Object.hasOwn(recipe, 'credentialOperations') ? ['credentialOperations'] : []),
    ...(Object.hasOwn(recipe, 'ownedReadOperations') ? ['ownedReadOperations'] : []),
    ...(Object.hasOwn(recipe, 'physicalWrite') ? ['physicalWrite'] : [])]);
  const operations = (name: 'memberOperations' | 'rowOperations'): readonly Operation[] => {
    const values = fields[name].value;
    if (!Array.isArray(values) || values.length > maxOperations) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    const entries = own(values, ['length', ...Array.from({length: values.length}, (_, index) => String(index))]);
    return Object.freeze(Array.from({length: values.length}, (_, index) => {
      const entry = own(entries[String(index)].value, ['operation', 'extent']);
      const operation: unknown = entry.operation.value, extent: unknown = entry.extent.value;
      if (!text(operation) || extent === null || typeof extent !== 'object' ||
          nodeTypes.isProxy(extent)) fail('InvalidInstalledEffectPlanRecipe');
      return Object.freeze({operation, extent});
    }));
  };
  const memberOperations = operations('memberOperations'), rowOperations = operations('rowOperations');
  const controlsPerRow: object | undefined = fields.controlsPerRow?.value;
  if (fields.controlsPerRow !== undefined && (controlsPerRow === null || typeof controlsPerRow !== 'object' ||
      nodeTypes.isProxy(controlsPerRow))) fail('InvalidInstalledEffectPlanRecipe');
  let savedControlCodec: SavedControlCodec | undefined;
  if (fields.savedControlCodec !== undefined) {
    const value = fields.savedControlCodec.value;
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    const codec = own(value, ['maxEntryBytes', 'fallbackCapacity',
      ...(Object.hasOwn(value, 'maxResponseBytes') ? ['maxResponseBytes'] : [])]);
    const maxEntryBytes: number = codec.maxEntryBytes.value, fallbackCapacity: unknown = codec.fallbackCapacity.value;
    const maxResponseBytes: number | undefined = codec.maxResponseBytes?.value;
    if (controlsPerRow === undefined || !Number.isSafeInteger(maxEntryBytes) || maxEntryBytes < 1 ||
        maxEntryBytes > effectLedgerImplementationBounds.maxEntryBytes || fallbackCapacity === null ||
        typeof fallbackCapacity !== 'object' || nodeTypes.isProxy(fallbackCapacity) ||
        (codec.maxResponseBytes !== undefined && (!Number.isSafeInteger(maxResponseBytes) || maxResponseBytes! < 1 ||
          maxResponseBytes! > effectLedgerImplementationBounds.maxResponseBytes))) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    savedControlCodec = Object.freeze({maxEntryBytes, fallbackCapacity,
      ...(maxResponseBytes === undefined ? {} : {maxResponseBytes})});
  }
  if (memberOperations.length + rowOperations.length === 0 ||
      memberOperations.length + rowOperations.length > maxOperations) fail('InvalidInstalledEffectPlanRecipe');
  let requestConstruction: Construction | undefined;
  if (fields.requestConstruction !== undefined) {
    const selected = own(fields.requestConstruction.value, ['operationIndex',
      ...(Object.hasOwn(fields.requestConstruction.value, 'inputExtent') ? ['inputExtent'] : [])]);
    const operationIndex: number = selected.operationIndex.value;
    if (!Number.isSafeInteger(operationIndex) || operationIndex < 0 || operationIndex >= rowOperations.length) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    const inputExtent: CapturedCallback | undefined = selected.inputExtent?.value;
    if (inputExtent !== undefined && (typeof inputExtent !== 'function' || nodeTypes.isProxy(inputExtent) ||
        nodeTypes.isAsyncFunction(inputExtent))) fail('InvalidInstalledEffectPlanRecipe');
    requestConstruction = Object.freeze({operationIndex, ...(inputExtent === undefined ? {} : {inputExtent})});
  }
  let requestFinalization: InstalledEffectPlanRecipe['requestFinalization'];
  if (fields.requestFinalization !== undefined) {
    const selected = own(fields.requestFinalization.value, ['operationIndex']);
    const operationIndex: number = selected.operationIndex.value;
    if (!Number.isSafeInteger(operationIndex) || operationIndex < 0 || operationIndex >= rowOperations.length ||
        requestConstruction === undefined || operationIndex === requestConstruction.operationIndex) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    requestFinalization = Object.freeze({operationIndex});
  }
  const memberConstruction = (name: string): Construction | undefined => {
    if (fields[name] === undefined) return undefined;
    const selected = own(fields[name].value, ['operationIndex',
      ...(Object.hasOwn(fields[name].value, 'inputExtent') ? ['inputExtent'] : [])]);
    const operationIndex: number = selected.operationIndex.value;
    if (!Number.isSafeInteger(operationIndex) || operationIndex < 0 || operationIndex >= memberOperations.length) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    const inputExtent: CapturedCallback | undefined = selected.inputExtent?.value;
    if (inputExtent !== undefined && (typeof inputExtent !== 'function' || nodeTypes.isProxy(inputExtent) ||
        nodeTypes.isAsyncFunction(inputExtent))) fail('InvalidInstalledEffectPlanRecipe');
    return Object.freeze({operationIndex, ...(inputExtent === undefined ? {} : {inputExtent})});
  };
  const captureConstruction = memberConstruction('captureConstruction');
  const recoveryConstruction = memberConstruction('recoveryConstruction');
  const footprintConstruction = memberConstruction('footprintConstruction');
  const ownedConstruction = (name: string): OwnedConstruction | undefined => {
    if (fields[name] === undefined) return undefined;
    const selected = own(fields[name].value, ['receiver', 'method', 'capacity']);
    const receiver: unknown = selected.receiver.value, method: CapturedCallback = selected.method.value,
      capacity: unknown = selected.capacity.value;
    if (receiver === null || typeof receiver !== 'object' || nodeTypes.isProxy(receiver) ||
        typeof method !== 'function' || nodeTypes.isProxy(method) || nodeTypes.isAsyncFunction(method) ||
        capacity === null || typeof capacity !== 'object' || nodeTypes.isProxy(capacity)) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    return Object.freeze({receiver, method, capacity});
  };
  const grantConstruction = ownedConstruction('grantConstruction');
  const projectConstruction = ownedConstruction('projectConstruction');
  if (footprintConstruction !== undefined && (footprintConstruction.inputExtent !== undefined ||
      footprintConstruction.operationIndex === captureConstruction?.operationIndex ||
      footprintConstruction.operationIndex === recoveryConstruction?.operationIndex ||
      !memberOperations[footprintConstruction.operationIndex].operation.endsWith('.footprint'))) fail('InvalidInstalledEffectPlanRecipe');
  if (recoveryConstruction !== undefined && (captureConstruction === undefined ||
      recoveryConstruction.operationIndex === captureConstruction.operationIndex)) fail('InvalidInstalledEffectPlanRecipe');
  let credentialOperations: readonly CredentialOperation[] | undefined;
  if (fields.credentialOperations !== undefined) {
    const values = fields.credentialOperations.value;
    // Several independently authorized physical reads can belong to one
    // existing phase. Every named slot still selects a DISTINCT original
    // member/row operation below; the existing total-operation bound remains.
    if (!Array.isArray(values) || values.length < 1 || values.length > maxOperations ||
        values.length > memberOperations.length + rowOperations.length) fail('InvalidInstalledEffectPlanRecipe');
    const entries = own(values, ['length', ...Array.from({length: values.length}, (_, index) => String(index))]);
    const phases = new Map<string, 'named' | 'single'>(), slots = new Set<string>(), indexes = new Set([
      ...(requestConstruction === undefined ? [] : [`row:${requestConstruction.operationIndex}`]),
      ...(requestFinalization === undefined ? [] : [`row:${requestFinalization.operationIndex}`]),
      ...(captureConstruction === undefined ? [] : [`member:${captureConstruction.operationIndex}`]),
      ...(recoveryConstruction === undefined ? [] : [`member:${recoveryConstruction.operationIndex}`]),
      ...(footprintConstruction === undefined ? [] : [`member:${footprintConstruction.operationIndex}`]),
    ]);
    credentialOperations = Object.freeze(Array.from({length: values.length}, (_, index) => {
      const original = entries[String(index)].value;
      if (original === null || typeof original !== 'object' || nodeTypes.isProxy(original)) fail('InvalidInstalledEffectPlanRecipe');
      const entry = own(original, ['phase', 'operationIndex', 'maxRequestBytes', 'maxResponseBytes',
        ...(Object.hasOwn(original, 'maxTargetBytes') ? ['maxTargetBytes'] : []),
        ...(Object.hasOwn(original, 'perRow') ? ['perRow'] : []),
        ...(Object.hasOwn(original, 'slot') ? ['slot'] : []),
        ...(Object.hasOwn(original, 'resource') ? ['resource'] : []),
        ...(Object.hasOwn(original, 'responseExtent') ? ['responseExtent'] : []),
        ...(Object.hasOwn(original, 'discardResponseProjection') ? ['discardResponseProjection'] : [])]);
      const phase: string = entry.phase.value, operationIndex: number = entry.operationIndex.value,
        perRow: boolean = entry.perRow === undefined ? true : entry.perRow.value,
        maxRequestBytes: number = entry.maxRequestBytes.value, maxResponseBytes: number = entry.maxResponseBytes.value;
      const maxTargetBytes: number | undefined = entry.maxTargetBytes?.value;
      if (typeof phase !== 'string') fail('InvalidInstalledEffectPlanRecipe');
      const describe = ['capture-describe', 'apply-describe', 'resume-describe'].includes(phase);
      const target = ['capture-target', 'apply-target', 'resume-target'].includes(phase);
      const slot: string | undefined = entry.slot?.value, resource: string | undefined = entry.resource?.value;
      if (entry.maxTargetBytes !== undefined &&
          ((phase !== 'write' && (!target || slot !== 'target' || resource !== undefined)) ||
          !Number.isSafeInteger(maxTargetBytes) || maxTargetBytes! < 1 || maxTargetBytes! > 2147483647)) {
        fail('InvalidInstalledEffectPlanRecipe');
      }
      const named = slot !== undefined;
      const writeBranch = phase === 'write' && (slot === 'absent' || slot === 'present');
      if (named && (!describe && !target && !writeBranch || !text(slot) || !slot.isWellFormed() ||
          /[\u0000-\u001f\u007f]/u.test(slot)) ||
          resource !== undefined && (writeBranch || !named || !text(resource) || !resource.isWellFormed() ||
            /[\u0000-\u001f\u007f]/u.test(resource))) fail('InvalidInstalledEffectPlanRecipe');
      const row = ['capture-check', 'apply-check', 'resume-check', 'write-check', 'write', 'apply-confirm', 'resume-confirm',
        'capture-target', 'apply-target', 'resume-target'].includes(phase);
      const selected = perRow ? rowOperations : memberOperations;
      const key = `${perRow ? 'row' : 'member'}:${operationIndex}`;
      const phaseSlot = phase + '\0' + (slot ?? '');
      if (typeof perRow !== 'boolean' || (!describe && !row) || describe === perRow ||
          phases.has(phase) && (!named || phases.get(phase) !== 'named') || slots.has(phaseSlot) ||
          !Number.isSafeInteger(operationIndex) || operationIndex < 0 || operationIndex >= selected.length ||
          indexes.has(key) || ![maxRequestBytes,maxResponseBytes].every(value =>
            Number.isSafeInteger(value) && value > 0)) {
        fail('InvalidInstalledEffectPlanRecipe');
      }
      const responseExtent: CapturedCallback | undefined = entry.responseExtent?.value;
      if (responseExtent !== undefined && (typeof responseExtent !== 'function' || nodeTypes.isProxy(responseExtent) ||
          nodeTypes.isAsyncFunction(responseExtent))) fail('InvalidInstalledEffectPlanRecipe');
      const discardResponseProjection: true | undefined = entry.discardResponseProjection?.value;
      if (discardResponseProjection !== undefined &&
          (discardResponseProjection !== true || responseExtent === undefined)) fail('InvalidInstalledEffectPlanRecipe');
      phases.set(phase, named ? 'named' : 'single'); slots.add(phaseSlot); indexes.add(key);
      return Object.freeze({phase, operationIndex, maxRequestBytes, maxResponseBytes,
        ...(maxTargetBytes === undefined ? {} : {maxTargetBytes}),
        ...(entry.perRow === undefined ? {} : {perRow}),
        ...(slot === undefined ? {} : {slot}),
        ...(resource === undefined ? {} : {resource}),
        ...(responseExtent === undefined ? {} : {responseExtent}),
        ...(discardResponseProjection === undefined ? {} : {discardResponseProjection})});
    }));
    if (!phases.has('write')) fail('InvalidInstalledEffectPlanRecipe');
    if (phases.get('write') === 'named') {
      const absent = credentialOperations.find(entry => entry.phase === 'write' && entry.slot === 'absent');
      const present = credentialOperations.find(entry => entry.phase === 'write' && entry.slot === 'present');
      if (absent === undefined || present === undefined ||
          rowOperations[absent.operationIndex].operation === rowOperations[present.operationIndex].operation) {
        fail('InvalidInstalledEffectPlanRecipe');
      }
    }
  }
  let physicalWrite: PhysicalWrite | undefined;
  if (fields.physicalWrite !== undefined) {
    const original = fields.physicalWrite.value;
    const selected = own(original, ['operationIndex', 'transferBytes',
      ...(Object.hasOwn(original, 'inputExtent') ? ['inputExtent'] : [])]);
    const operationIndex: number = selected.operationIndex.value, transferBytes: unknown = selected.transferBytes.value;
    if (credentialOperations !== undefined || !Number.isSafeInteger(operationIndex) || operationIndex < 0 ||
        operationIndex >= rowOperations.length || operationIndex === requestConstruction?.operationIndex ||
        typeof transferBytes !== 'bigint' || transferBytes < 0n) fail('InvalidInstalledEffectPlanRecipe');
    const inputExtent: PhysicalWrite['inputExtent'] = selected.inputExtent?.value;
    if (selected.inputExtent !== undefined && (typeof inputExtent !== 'function' ||
        nodeTypes.isProxy(inputExtent) || nodeTypes.isAsyncFunction(inputExtent))) fail('InvalidInstalledEffectPlanRecipe');
    physicalWrite = Object.freeze({operationIndex, transferBytes,
      ...(inputExtent === undefined ? {} : {inputExtent})});
  }
  let ownedReadOperations: readonly OwnedReadOperation[] | undefined;
  if (fields.ownedReadOperations !== undefined) {
    const values = fields.ownedReadOperations.value;
    if (!Array.isArray(values) || values.length < 1 || values.length > 3 || credentialOperations !== undefined) {
      fail('InvalidInstalledEffectPlanRecipe');
    }
    const phases = new Set<string>(), indexes = new Set([requestConstruction?.operationIndex,
      requestFinalization?.operationIndex, physicalWrite?.operationIndex]);
    ownedReadOperations = Object.freeze(values.map(value => {
      const entry = own(value, ['phase', 'operationIndex']);
      const phase: string = entry.phase.value, operationIndex: number = entry.operationIndex.value;
      if (!['capture-target', 'apply-target', 'resume-target'].includes(phase) || phases.has(phase) ||
          !Number.isSafeInteger(operationIndex) || operationIndex < 0 || operationIndex >= rowOperations.length ||
          indexes.has(operationIndex)) fail('InvalidInstalledEffectPlanRecipe');
      phases.add(phase); indexes.add(operationIndex);
      return Object.freeze({phase, operationIndex});
    }));
  }
  return Object.freeze({memberOperations, rowOperations,
    ...(ownedReadOperations === undefined ? {} : {ownedReadOperations}),
    ...(savedControlCodec === undefined ? {} : {savedControlCodec}),
    ...(controlsPerRow === undefined ? {} : {controlsPerRow}),
    ...(requestConstruction === undefined ? {} : {requestConstruction}),
    ...(requestFinalization === undefined ? {} : {requestFinalization}),
    ...(captureConstruction === undefined ? {} : {captureConstruction}),
    ...(recoveryConstruction === undefined ? {} : {recoveryConstruction}),
    ...(footprintConstruction === undefined ? {} : {footprintConstruction}),
    ...(grantConstruction === undefined ? {} : {grantConstruction}),
    ...(projectConstruction === undefined ? {} : {projectConstruction}),
    ...(credentialOperations === undefined ? {} : {credentialOperations}),
    ...(physicalWrite === undefined ? {} : {physicalWrite})});
}

// Select immutable recipe DATA only. A slot cannot issue a grant, make an
// observation current, share another slot's token or enlarge its bounds.
export function selectInstalledEffectCredentialOperation(recipe: InstalledEffectPlanRecipe | undefined, phase: string,
  slot?: string): CredentialOperation | undefined {
  return recipe?.credentialOperations?.find(entry => entry.phase === phase && entry.slot === slot);
}

type WriteBranchPreview = Readonly<{before?: Readonly<{state: string}>; target_guard?: Readonly<{state: string}>}>;

// The caller supplies the already admitted original Preview row.
export function selectInstalledEffectWriteBranch(recipe: InstalledEffectPlanRecipe | undefined, kind: string,
  previewRow: WriteBranchPreview | undefined): CredentialOperation | undefined {
  if (selectInstalledEffectCredentialOperation(recipe, 'write', 'absent') === undefined) return undefined;
  const presence = previewRow?.before?.state;
  const guard = previewRow?.target_guard?.state;
  if (kind !== 'upsert' || (presence === 'absent' ? guard !== 'not_applicable'
      : presence !== 'present' || guard !== 'version')) fail('InvalidInstalledEffectWriteBranch');
  const selected = selectInstalledEffectCredentialOperation(recipe, 'write', presence);
  if (selected === undefined) fail('InvalidInstalledEffectWriteBranch');
  return selected;
}

// A composed generic owner keeps its original codec and full control quote.
export function installedEffectSavedControlEntryLimit(recipes: readonly (InstalledEffectPlanRecipe | undefined)[]) {
  return Math.max(...recipes.map(recipe => recipe?.savedControlCodec?.maxEntryBytes ??
    effectLedgerImplementationBounds.maxEntryBytes));
}
export function installedEffectSavedControlResponseLimit(recipes: readonly (InstalledEffectPlanRecipe | undefined)[]) {
  return Math.max(...recipes.map(recipe => recipe?.savedControlCodec?.maxResponseBytes ??
    effectLedgerImplementationBounds.maxResponseBytes));
}
export function installedEffectRecipeForControlEntryLimit(recipe: InstalledEffectPlanRecipe | undefined, maxEntryBytes: number,
  maxResponseBytes: number = effectLedgerImplementationBounds.maxResponseBytes): InstalledEffectPlanRecipe | undefined {
  const codec = recipe?.savedControlCodec;
  return codec !== undefined && (maxEntryBytes > codec.maxEntryBytes ||
    maxResponseBytes > (codec.maxResponseBytes ?? effectLedgerImplementationBounds.maxResponseBytes))
    ? Object.freeze({...recipe!, controlsPerRow: recipe!.savedControlCodec!.fallbackCapacity}) : recipe;
}
