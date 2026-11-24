import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';

type Runtime = Readonly<{
  clientProgramEffectTableWriteBinding(prepared: unknown, stageIndex: number, effectId: string,
    maxWork: number): unknown;
}>;
type WriteTarget = Readonly<{action: string; capabilityCid: string; installationBindingCid?: string;
  expectedTable: Readonly<{table_uuid: string; generation_cid: string}> | null}>;

// Project admitted facts; never parse a Program independently in the Host.
export function checkedTableWriteBinding(moon: Runtime, prepared: unknown, stageIndex: number,
  effectId: string, maxWork: number) {
  return checked(moon.clientProgramEffectTableWriteBinding(
    prepared, stageIndex, effectId, maxWork));
}

export function verifyTableWriteBinding(target: WriteTarget, binding: unknown) {
  if (binding === undefined) return;
  const expected = target.expectedTable;
  if (!(['create', 'create_or_replace'] as readonly unknown[]).includes(runtimeField(binding, 0)) ||
      runtimeField(binding, 0) === 'create' && runtimeField(binding, 1) !== 'create' ||
      runtimeField(binding, 1) !== target.action || runtimeField(binding, 4) !== target.capabilityCid ||
      runtimeField(binding, 5) !== target.installationBindingCid ||
      (runtimeField(binding, 1) === 'create'
        ? expected !== null || runtimeField(binding, 2) !== undefined || runtimeField(binding, 3) !== undefined
        : expected?.table_uuid !== runtimeField(binding, 2) || expected?.generation_cid !== runtimeField(binding, 3))) {
    throw Object.assign(new Error('InstalledTableWriteBindingChanged'),
      {code: 'InstalledTableWriteBindingChanged'});
  }
}
