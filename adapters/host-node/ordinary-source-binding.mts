// Host-private retention of ordinary installed reads. Target semantics remain
// with the installed preparation owner, not a provider dispatcher here.
import {canonicalJson} from '../../packages/sdk/host-port.mjs';

export const BOUND_SOURCE_INVENTORY = 'actql-client-bound-source-inventory/0.1';
export const BOUND_SOURCE_SUBMISSION = 'actql-remote-bound-source-submission/0.1';
type InstallationBinding = Readonly<{
  connectorId: string; connectorRegistration: string; connectorRevision: string; bindingCid: string;
}>;
type CandidateRecord = Readonly<Record<string, unknown>>;
type CandidateOccurrence = CandidateRecord & Readonly<{checkedSource?: CandidateRecord | null}>;
type PreparedSource = Readonly<{checkedSource: unknown; readTuple: unknown; physicalBinding: unknown}>;
type SourceBindingAdapter<Prepared> = Readonly<{
  ordinaryRecoveryBinding?: (prepared: Prepared) => unknown;
}>;
type Source<Occurrence extends object, Prepared extends PreparedSource> = Readonly<{
  occurrence: Occurrence; prepared: Prepared; adapter: SourceBindingAdapter<Prepared>;
}>;
const fail: () => never = () => { throw Object.assign(new Error('InstalledSourcePreparationMismatch'),
  {code: 'InstalledSourcePreparationMismatch'}); };
const keys = (value: unknown, expected: string): value is Record<string, unknown> => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join(',') === expected.split(',').sort().join(',');
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0 &&
  value.length <= 256 && !/[\u0000-\u001f\u007f]/u.test(value);
const ordinaryText = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const cid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
export function validInstallationBinding(binding: unknown): binding is InstallationBinding {
  return keys(binding, 'connectorId,connectorRegistration,connectorRevision,bindingCid') &&
    [binding.connectorId, binding.connectorRegistration, binding.connectorRevision].every(text) &&
    cid(binding.bindingCid);
}
export function validBoundSourceOccurrence(item: CandidateOccurrence | null | undefined, index: number) {
  const source = item?.checkedSource;
  const whole = Object.hasOwn(source ?? {}, 'sourceInput');
  const coordinates = whole
    ? keys(item, 'stage,input,task,checkedSource,readTuple,physicalBinding,installationBinding' +
        (Object.hasOwn(item ?? {}, 'computeTask') ? ',computeTask' : '')) &&
      [item.stage, item.input, item.task, item.computeTask ?? item.task].every(value => Number.isSafeInteger(value) && (value as number) >= 0) &&
      item.task === index
    : keys(item, 'stage,input,task,checkedSource,readTuple,physicalBinding,installationBinding') &&
      item.stage === index && item.input === 0 && item.task === index;
  const identity = whole
    ? keys(source, 'sourceInput,sourceRef,sourceContractCid,carrierSchemaContractCid,sourceDataPolicyCid,dataClassification,sourceViewContractCid') &&
      Array.isArray(source.sourceInput) && source.sourceInput.length === 2 && source.sourceInput.every(cid)
    : keys(source, 'requirementCid,sourceRef,sourceContractCid,carrierSchemaContractCid,sourceDataPolicyCid,dataClassification,sourceViewContractCid,inputContractCid,outputContractCid') &&
      [source.requirementCid, source.inputContractCid, source.outputContractCid].every(cid);
  return coordinates && identity &&
    [source!.sourceContractCid, source!.carrierSchemaContractCid,
      source!.sourceDataPolicyCid, source!.sourceViewContractCid].every(cid) && ordinaryText(source!.sourceRef) &&
    ['public', 'internal', 'confidential', 'restricted', 'unknown'].includes(source!.dataClassification as string) &&
    keys(item!.readTuple, 'connection,resource,operation') &&
    [item!.readTuple.connection, item!.readTuple.resource].every(ordinaryText) && item!.readTuple.operation === 'read' &&
    validInstallationBinding(item!.installationBinding) &&
    item!.physicalBinding !== null && typeof item!.physicalBinding === 'object' &&
    !Array.isArray(item!.physicalBinding) && Object.keys(item!.physicalBinding).length > 0;
}

export function ordinarySourceDescriptors<Occurrence extends object, Prepared extends PreparedSource>(
  sources: readonly Source<Occurrence, Prepared>[]): Array<Occurrence &
    Pick<Prepared, 'checkedSource' | 'readTuple' | 'physicalBinding'> & Readonly<{installationBinding?: unknown}>> {
  const bound = sources.map(source => typeof source.adapter.ordinaryRecoveryBinding === 'function');
  if (bound.some(Boolean) && !bound.every(Boolean)) fail();
  return sources.map(({occurrence, prepared, adapter}) => ({...occurrence,
    checkedSource: prepared.checkedSource, readTuple: prepared.readTuple,
    physicalBinding: prepared.physicalBinding,
    ...(bound.every(Boolean) ? {installationBinding: adapter.ordinaryRecoveryBinding!(prepared)} : {}),
  }) as Occurrence & Pick<Prepared, 'checkedSource' | 'readTuple' | 'physicalBinding'> &
    Readonly<{installationBinding?: unknown}>);
}

// Compare against the original captured binding. Missing owner capability is
// not permission to reinterpret a saved bound read as a legacy or keyed read.
export function verifyOrdinarySourceBinding<Prepared>(adapter: SourceBindingAdapter<Prepared>, prepared: Prepared, original: unknown) {
  if (!validInstallationBinding(original) || typeof adapter.ordinaryRecoveryBinding !== 'function') fail();
  const actual = adapter.ordinaryRecoveryBinding(prepared);
  if (!validInstallationBinding(actual) || canonicalJson(actual, {dataKeys: true}) !==
      canonicalJson(original, {dataKeys: true})) fail();
}
