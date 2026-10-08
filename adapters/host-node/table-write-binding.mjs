import {checked} from '../host-common/runtime-result.mjs';

// Project admitted facts; never parse a Program independently in the Host.
export function checkedTableWriteBinding(moon, prepared, stageIndex, effectId, maxWork) {
  return checked(moon.clientProgramEffectTableWriteBinding(
    prepared, stageIndex, effectId, maxWork));
}

export function verifyTableWriteBinding(target, binding) {
  if (binding === undefined) return;
  const expected = target.expectedTable;
  if (!['create', 'create_or_replace'].includes(binding._0) ||
      binding._0 === 'create' && binding._1 !== 'create' ||
      binding._1 !== target.action || binding._4 !== target.capabilityCid ||
      binding._5 !== target.installationBindingCid ||
      (binding._1 === 'create'
        ? expected !== null || binding._2 !== undefined || binding._3 !== undefined
        : expected?.table_uuid !== binding._2 || expected?.generation_cid !== binding._3)) {
    throw Object.assign(new Error('InstalledTableWriteBindingChanged'),
      {code: 'InstalledTableWriteBindingChanged'});
  }
}
