import assert from 'node:assert/strict';
export const driverPath='src/connectors/local/driver/managed_dispatch.mbt';
export const scratchRetirementPath='src/connectors/local/driver/scratch_retirement.mbt';
export const inputStopPath='src/connectors/local/driver/input_stop.mbt';
export const bridgeReclamationPath='src/execution_relation/managed_producer_bridge.mbt';
export const importReclamationPath='src/execution_relation/completed_output_import.mbt';
export const strategyPath='src/physical_strategy_host/task_execution.mbt';
const clean=s=>s.replace(/\/\/[^\n]*/g,'').replace(/\s+/g,'').replace(/,\)/g,')');
export function blockAfter(source,anchor) {
  assert.equal(source.split(anchor).length,2,`Changed unique owner boundary ${anchor}`);
  const begin=source.indexOf('{',source.indexOf(anchor)+anchor.length);assert(begin>=0);
  let depth=0;
  for(let i=begin;i<source.length;i++) {
    if(source[i]==='{')depth++;else if(source[i]==='}'&&--depth===0)return source.slice(begin,i+1);
  }
  assert.fail('Unbalanced owner boundary');
}
// The caller may return Local scratch while the SAME provider keeps an
// independently accepted completion. Full cleanup and retention are distinct.
const release=`{
  let observe = fn() {
    if provider_execution.val is Some(active) {
      let cursor = @local.managed_provider_cleanup_continuation(active)
      if cursor > provider_reclamation_steps.val {
        provider_reclamation_steps.val = cursor
      }
    }
  }
  observe()
  let released = release_local_managed_provider_scratch(provider_execution,
    provider_completion_retained,
    live.val && settled.val && (ordinary.val is Some(_) || carrier.val is Some(_)),
    final_provider_work,)
  observe()
  released
}`;
const providerScratch=`{
  guard provider.val is Some(active) else { return true }
  if !@local.managed_provider_stopped(active) { return false }
  match @local.cleanup_managed_provider(active) {
    Ok(true) => {
      final_work.val = @local.managed_provider_cumulative_work(active)
      provider.val = None
      true
    }
    Ok(false) => if completed && (retained_completion.val ||
      @local.managed_provider_retained_completion(active)) {
      final_work.val = @local.managed_provider_cumulative_work(active)
      retained_completion.val = true
      true
    } else { false }
    Err(_) => false
  }
}`;
const retainedCompletion=`{
  (execution.stopped)() &&
  execution.retained_completion.map(check => check()).unwrap_or(false)
}`;
const scratch=`{
    ( disposed.val || (settled.val && finalization_ready.val) || (settled.val && carrier.val is Some(_)) ) &&
    scratch_uses.val == 0 && (provider_execution.val is None || provider_completion_retained.val) &&
    (live.val || input_stop.phase == Stopped) &&
    scratch_retirement.phase == Retired &&
    ( !disposed.val || retained.val is Some(_) ||
      (ordinary.val is None && finalization_payload.val is None && finalization_available.val is None &&
       finalization_receipt.val is None && finalization_material.val is None && finalization_completed.val is None) ) &&
    finalization_values.val is None && finalization_retention.val is None && finalization_stream.val is None &&
    finalization_result_preparation.val is None && relation_snapshot_cancel.val is None
  }`;
const ownedScratch=`{
  if !(disposed.val || (settled.val && (finalization_ready.val || carrier.val is Some(_)))) ||
    scratch_uses.val != 0 || (provider_execution.val is Some(_) && !provider_completion_retained.val) ||
    relation_snapshot_cancel.val is Some(_) ||
    (!live.val && input_stop.phase != Stopped) {
    return
  }
  if !advance_local_managed_scratch_retirement(scratch_retirement, bridges, retained_imports,
    reads, finalization_cids, finalization_issuers,) {
    return
  }
  if finalization_values.val is Some(values) {
    @execution.dispose_managed_output_values_scratch(values)
    finalization_reclamation_steps.val = @execution.managed_output_values_reclamation_steps(values)
    if !@execution.managed_output_values_scratch_released(values) {
      return
    }
  }
  finalization_values.val = None
  finalization_retention.val = None
  finalization_stream.val = None
  finalization_result_preparation.val = None
  if disposed.val && retained.val is None {
    release_output_aliases()
  }
}`;
const rootSlice=`{
  let mut steps = 0
  while steps < 64 {
    match cursor.phase {
      Bridges => if cursor.index < bridges.length() {
        bridges[cursor.index].val = None
        cursor.index += 1
      } else { cursor.phase = Imports; cursor.index = 0 }
      Imports => if cursor.index < imports.length() {
        imports[cursor.index].val = None
        cursor.index += 1
      } else { cursor.phase = Reads; cursor.index = 0 }
      Reads => if cursor.index < reads.length() {
        reads[cursor.index] = None
        cursor.index += 1
      } else { cursor.phase = Cids; cursor.index = 0 }
      Cids => if cursor.index < cids.length() {
        cids[cursor.index] = None
        cursor.index += 1
      } else { cursor.phase = Issuers; cursor.index = 0 }
      Issuers => if !issuers.is_empty() {
        issuers.pop() |> ignore
      } else { issuers.shrink_to_fit(); cursor.phase = Retired }
      Retired => return true
    }
    steps += 1
    cursor.steps += 1L
  }
  cursor.phase == Retired
}`.replaceAll(';','');
// The same owner retains accounting refusal across later physical-pending
// observations and fences synchronous reentry before touching the owned task.
const retirementObservation=`{
  let previous = execution.cleanup_observation
  match previous {
    CleanupChecking => return Ok(false)
    CleanupReady | CleanupRefused(_) => ()
  }
  execution.cleanup_observation = CleanupChecking
  let observed = release_task_execution_owned(run, execution)
  let result = match (observed, previous) {
    (Ok(false), CleanupRefused(issue)) => Err(issue)
    _ => observed
  }
  execution.cleanup_observation = match result {
    Err(issue) => CleanupRefused(issue)
    Ok(true) => CleanupReady
    Ok(false) => previous
  }
  result
}`;
const retirement=`{
  if !execution.execution_settled || !task_execution_matches(run, execution) {
    return Ok(false)
  }
  if !execution.disposed {
    if !task_done(run, execution.task) {
      return Ok(false)
    }
    let scratch_released = task_execution_scratch_released(execution)
    if !task_execution_matches(run, execution) {
      return Ok(execution.hooks is None)
    }
    if scratch_released && @resources.reservation_open(execution.reservation) {
      match @resources.settle_execution_reservation(run.ledger, execution.reservation,
        remaining_execution=0L,) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
    return Ok(false)
  }
  let scratch_released = task_execution_scratch_released(execution)
  if !task_execution_matches(run, execution) {
    return Ok(execution.hooks is None)
  }
  let retention_released = if scratch_released {
    task_execution_retention_released(execution)
  } else {
    false
  }
  if !task_execution_matches(run, execution) {
    return Ok(execution.hooks is None)
  }
  if !scratch_released || !retention_released {
    if @resources.reservation_open(execution.reservation) {
      match @resources.settle_execution_reservation(run.ledger, execution.reservation,
        remaining_execution=if scratch_released { 0L } else { execution.scratch },)
      {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
    return Ok(false)
  }
  if execution.failed_holding is Some(holding) {
    let released = @resources.release_allocation(run.ledger, holding)
    if !task_execution_matches(run, execution) {
      return Ok(execution.hooks is None)
    }
    match released {
      Err(issue) => return Err(issue)
      Ok(_) => execution.failed_holding = None
    }
  }
  if @resources.reservation_open(execution.reservation) {
    let settled = @resources.settle_reservation(run.ledger, execution.reservation,)
    if !task_execution_matches(run, execution) {
      return Ok(execution.hooks is None)
    }
    match settled {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  match release_captured_task_retention(run, execution.task) {
    Err(issue) => return Err(issue)
    Ok(false) => return Ok(false)
    Ok(true) => ()
  }
  captured_cleanup_confirmed(run, execution)
  run.executions[execution.task] = None
  let hooks = execution.hooks.unwrap()
  execution.hooks = None
  execution.resident = None
  execution.admitted_managed_inputs = None
  task_execution_released(hooks)
  collect_captured_retention(run)
  Ok(true)
}`;
const stopInputs=`{
  if live.val { return true }
  if scratch_retirement.phase == Retired {
    input_stop.phase = Stopped
    return true
  }
  advance_local_managed_input_stop(input_stop, bridges, retained_imports,
    bridge => @execution.advance_close_managed_producer_bridge(bridge, 1),
    importer => @execution.advance_cancel_completed_output_import(importer, 1),)
}`;
const inputSlice=`{
  if cursor.advancing { return false }
  cursor.advancing = true
  let mut steps = 0
  while steps < 64 {
    match cursor.phase {
      Bridges => if cursor.index < bridges.length() {
        let input = bridges[cursor.index].val
        if input is Some(bridge) && !close_bridge(bridge) { () }
        else { cursor.index += 1 }
      } else { cursor.phase = Imports; cursor.index = 0 }
      Imports => if cursor.index < imports.length() {
        let input = imports[cursor.index].val
        if input is Some(importer) && !cancel_import(importer) { () }
        else { cursor.index += 1 }
      } else { cursor.phase = Stopped }
      Stopped => break
    }
    steps += 1
  }
  cursor.advancing = false
  cursor.phase == Stopped
}`.replaceAll(';','');
const cancelInputs=`{
  live.val = false
  cancel_finalization()
  if provider_execution.val is Some(active) {
    @local.cancel_managed_provider(active) |> ignore
  }
  stop_owned_inputs() |> ignore
}`;
const disposeInputs=cancelInputs.replace('  stop_owned_inputs() |> ignore',
  '  disposed.val = true\n  stop_owned_inputs() |> ignore\n  release_owned_scratch()');
const bridgeReclaim=`{
  bridge.admitted.buffer.deferred_reclamation = true
  close_managed_producer_bridge(bridge)
  if bridge.handed_off { return true }
  if quantum <= 0 || bridge.admitted.buffer.reading { return false }
  bridge.rows.val = None
  if bridge.admitted.buffer.open || !bridge.admitted.buffer.rows.is_empty() ||
    !bridge.admitted.buffer.presence_rows.is_empty() {
    revoke_admitted_buffer(bridge.admitted.buffer)
  }
  advance_admitted_buffer_reclamation(bridge.admitted.buffer, quantum)
}`;
const importReclaim=`{
  if value.completed { return true }
  value.admitted.buffer.deferred_reclamation = true
  value.stream.buffer.deferred_reclamation = true
  cancel_completed_output_import(value) |> ignore
  if quantum <= 0 || value.reading || value.admitted.buffer.reading ||
    value.stream.reading || value.stream.buffer.reading { return false }
  if !advance_admitted_buffer_reclamation(value.admitted.buffer, quantum) {
    return false
  }
  advance_admitted_buffer_reclamation(value.stream.buffer, quantum)
}`;
// These are correspondence premises for the existing conditional model, not
// another capacity allowance or a proof of physical file/import reclamation.
const cancelSnapshot=`{
  if stream.val is Some(value) { @execution.cancel_completed_output_export(value) }
  if receipt.val is Some(value) { @execution.cancel_completed_export_receipt(value) }
  if importing.val is Some(value) { @execution.cancel_completed_output_import(value) |> ignore }
  restored.val = None
  phase.val = Failed
  cleanup_references(64)
}`;
const snapshotCleanup=`{
  if quantum <= 0 { return false }
  if stream.val is Some(value) {
    if !@execution.advance_cancel_completed_output_export(value, quantum) { return false }
    stream.val = None
  }
  if receipt.val is Some(value) {
    if !@execution.advance_cancel_completed_export_receipt(value, quantum) { return false }
    receipt.val = None
  }
  if stored.val is Some(value) {
    if !storage_released() { return false }
    if @execution.completed_output_retained_material(value) is Some(material) &&
      !@execution.advance_retained_output_reference_reclamation(material, quantum) { return false }
    stored.val = None
  }
  true
}`;
const snapshotFinish=`{
  guard live.val && phase.val == Restored && storage_released() &&
    stored.val is None && stream.val is None && receipt.val is None &&
    restored.val is Some(value) else { return Err(Configuration(InvalidLimits)) }
  ordinary.val = Some(value)
  restored.val = None
  relation_snapshot_cancel.val = None
  phase.val = Finished
  snapshot_ready.val = true
  Ok(())
}`;
const cleanupPrefix=`{
  if scratch_uses.val != 0 { return false }
  if !stop_owned_inputs() { return false }
  if !release_provider_scratch() { return false }
  if relation_snapshot_cancel.val is Some(cancel) {
    if !cancel() { return false }
    relation_snapshot_cancel.val = None
  }
  release_owned_scratch()
`;
// Callback detachment does not replace the independent physical storage
// predicate or the existing common Owner's fallible cleanup observation.
const cleanupSuffix=`
  if !snapshot_storage_released.val.map(check => check()).unwrap_or(true) {
    return false
  }
  @strategy.refresh_task_execution_cleanup(setup.run, execution).unwrap_or(false,)
}`;
const cancelFinalization=`{
  finalization_cancelled.val = true
  if relation_snapshot_cancel.val is Some(cancel) {
    if cancel() { relation_snapshot_cancel.val = None }
  }
  if finalization_completed.val is Some(completed) && !finalization_ready.val {
    @execution.revoke_unpublished_managed_completed_output(completed) |> ignore
  }
  if finalization_values.val is Some(values) { @execution.cancel_managed_output_values(values) |> ignore }
  if finalization_retention.val is Some(port) { @execution.cancel_managed_output_retention_port(port) |> ignore }
  if finalization_stream.val is Some(stream) { @execution.cancel_completed_output_export(stream) }
  if finalization_result_preparation.val is Some(preparation) {
    @execution.cancel_completed_result_relation_export(preparation) |> ignore
  }
}`;
export function checkDriverRetirementSource(read) {
  const driver=read(driverPath).toString(),strategy=read(strategyPath).toString();
  const roots=read(scratchRetirementPath).toString();
  const inputs=read(inputStopPath).toString();
  const bridge=read(bridgeReclamationPath).toString();
  const importer=read(importReclamationPath).toString();
  assert.equal(clean(blockAfter(driver,'let release_provider_scratch = fn()')),clean(release),'Changed provider stop/cleanup/work/root retirement ordering');
  assert.equal(clean(blockAfter(roots,'fn release_local_managed_provider_scratch(')),clean(providerScratch),'Changed same-provider pending/error/retained-completion custody');
  const provider=read('src/connectors/local/managed_provider.mbt').toString();
  assert.equal(clean(blockAfter(provider,'pub fn managed_provider_retained_completion(')),clean(retainedCompletion),'Changed stopped same-provider retained-completion observation');
  assert.match(driver,/let provider_completion_retained = Ref\(false\)/,'Completion handoff must start absent');
  const retention=clean(blockAfter(driver,'retention_released: fn()'));
  assert(retention.includes('provider_execution.valisNone&&relation_released&&'), 'Retained completion cannot acknowledge whole provider cleanup');

  assert.equal(clean(blockAfter(driver,'scratch_released: fn()')),clean(scratch),'Changed installed driver scratch witness');
  assert.equal(clean(blockAfter(driver,'let release_owned_scratch = fn()')),clean(ownedScratch),'Changed installed incremental root retirement guard');
  assert.equal(clean(blockAfter(driver,'let stop_owned_inputs = fn()')),clean(stopInputs),'Changed installed input revocation boundary');
  assert.equal(clean(blockAfter(driver,'\n          cancel: fn()')),clean(cancelInputs),'Changed immediate cancellation boundary');
  assert.equal(clean(blockAfter(driver,'dispose: fn()')),clean(disposeInputs),'Changed disposal custody boundary');
  assert.equal(clean(blockAfter(inputs,'advance_local_managed_input_stop(')),clean(inputSlice),'Changed bounded input revocation slice');
  assert.equal(clean(blockAfter(inputs,'fn local_managed_input_stop(')),clean('{ { phase: Bridges, index: 0, advancing: false, } }'),'Changed initial input revocation phase');
  assert.equal(clean(blockAfter(bridge,'advance_close_managed_producer_bridge(')),clean(bridgeReclaim),'Changed bridge buffer reclamation owner');
  assert.equal(clean(blockAfter(importer,'advance_cancel_completed_output_import(')),clean(importReclaim),'Changed import buffer reclamation owner');
  assert.equal((driver.match(/deferred_reclamation=true/g)??[]).length,3,'Changed bounded input/snapshot import preparation');
  assert.equal((driver.match(/retained_imports\.push\(importing\)/g)??[]).length,1,'Changed snapshot import custody registration');
  const snapshot=blockAfter(driver,'prepare_relation_snapshot: fn(storage_released)');
  assert.equal(clean(blockAfter(snapshot,'relation_snapshot_cancel.val = Some(fn()')),clean(cancelSnapshot),'Changed snapshot cancellation/capture custody');
  assert.equal(clean(blockAfter(snapshot,'let cleanup_references = fn(quantum : Int)')),clean(snapshotCleanup),'Changed snapshot storage/reference cleanup completion');
  assert.equal(clean(blockAfter(snapshot,'finish: () =>')),clean(snapshotFinish),'Changed successful snapshot finalization custody transfer');
  assert.equal(clean(blockAfter(driver,'let cancel_finalization = fn()')),clean(cancelFinalization),'Changed pending snapshot cancellation retry custody');
  const cleanup=clean(blockAfter(driver,'cleanup_refresh: fn()'));
  assert(cleanup.startsWith(clean(cleanupPrefix)),
    'Changed cleanup callback/input/provider/snapshot retirement ordering');
  assert(cleanup.endsWith(clean(cleanupSuffix)),
    'Changed snapshot storage or common Owner cleanup completion witness');
  assert.match(driver.replace(/\s+/g,' '),/let relation_snapshot_cancel : Ref\[\(\(\) -> Bool\)\?\] = Ref\(None\)/);
  assert.deepEqual([...driver.matchAll(/relation_snapshot_cancel\.val\s*=\s*([^\n]+)/g)].map(m=>m[1].trim()),
    ['None','Some(fn() {','None','None'],'Unreviewed snapshot callback root replacement');
  assert.equal(clean(blockAfter(roots,'fn local_managed_scratch_retirement(')),clean('{ { phase: Bridges, index: 0, steps: 0L, } }'),'Changed initial scratch retirement phase');
  assert.equal(clean(blockAfter(roots,'advance_local_managed_scratch_retirement(')),clean(rootSlice),'Changed bounded scratch root retirement slice');
  assert.equal(clean(blockAfter(roots,'fn local_managed_input_writes_open(')),clean('{ live && !settled && !disposed }'),'Changed late input write rejection');
  assert.equal((driver.match(/let scratch_retirement = local_managed_scratch_retirement\(\)/g)??[]).length,1,'Changed installed scratch cursor construction');
  // The sixth guard rechecks the same bridge after import grow/current. The
  // shared mutation scope must already enclose the earlier transfer/current;
  // counting a new call alone cannot admit a weakened guard or per-copy latch.
  assert.equal((driver.match(/local_managed_input_writes_open\(/g)??[]).length,6,'Changed import/bridge write guards');
  assert.equal(clean(blockAfter(driver,'fn[A] with_local_managed_import_mutation(')),clean(`{
    if active.val { return Err(Configuration(InputUnavailable)) }
    active.val = true
    let result = action()
    active.val = false
    result
  }`),'Changed shared import mutation fence');
  assert.equal((driver.match(/let import_mutating = Ref\(false\)/g)??[]).length,1,
    'Every input copy must use the same Task mutation fence');
  const inputTransfer=blockAfter(driver,'transfers.push(LocalManagedInputTransfer::');
  const append=blockAfter(inputTransfer,'append: row =>');
  const importMutation=blockAfter(append,'with_local_managed_import_mutation(import_mutating, fn()');
  assert.equal(clean(append),clean(`{ with_local_managed_import_mutation(import_mutating, fn() ${importMutation}) }`),
    'Current, transfer, grow, counter commit and append must stay inside the fence');
  const mutation=clean(importMutation);
  assert.equal((mutation.match(/local_managed_input_writes_open\(/g)??[]).length,2,
    'Managed append must retain both initial and after-grow write guards');
  const currentBridge=clean(`guard local_managed_input_writes_open(live.val, settled.val, disposed.val) &&
    handle.val is Some(current) && physical_equal(current, bridge) else {
      return Err(Configuration(InputUnavailable))
    }`);
  const ordered=[
    mutation.indexOf('local_managed_input_writes_open('),
    mutation.indexOf('@strategy.charge_task_execution_transfer('),
    mutation.indexOf('local_managed_import_next_extent('),
    mutation.indexOf('reserve_import(next)'),
    mutation.indexOf(currentBridge),
    mutation.indexOf('copied_rows.val=rows'),
    mutation.indexOf('@execution.append_managed_producer_bridge_wire('),
  ];
  assert(ordered.every((at,index)=>at>=0&&(index===0||at>ordered[index-1])),
    'Original import calculation/current/bridge checks must precede counter commit and copy');
  assert.equal(clean(blockAfter(strategy,'fn release_task_execution(')),clean(retirementObservation),'Changed common cleanup reentry/refusal observation boundary');
  assert.equal(clean(blockAfter(strategy,'fn release_task_execution_owned(')),clean(retirement),'Changed common reservation retirement boundary');
  assert.match(driver.replace(/\s+/g,' '),/let provider_execution : Ref\[@local\.ManagedProviderExecution\?\] = Ref\(None\)/);
  assert.deepEqual([...driver.matchAll(/provider_execution\.val\s*=\s*([^\n]+)/g)].map(m=>m[1].trim()),['Some(started)'],'Unreviewed provider root replacement');
  return {scope:'exact reviewed driver scratch-root and common reservation retirement boundaries',
    retainsProviderUntilStoppedAndCleanupSuccess:true,clearsProviderAfterCleanupSuccess:true,
    retainedCompletionKeepsSameCleanupOwner:true,retentionRequiresProviderAbsent:true,
    cachesFinalProviderWorkBeforeDroppingRoot:true,incrementalScratchRootRetirement:true,
    retainsAccountingRefusalAcrossPending:true,fencesSynchronousCleanupReentry:true,
    settlesOwnedHoldingsBeforeClearingTask:true,
    incrementalInputRevocation:true,incrementalPrivateImportRows:true,
    snapshotCustody:{pendingCancelRetainsCallback:true,retirementRequiresCallbackAbsent:true,
      cleanupRetryBeforeRootRetirement:true,successfulFinishRequiresReleasedStorage:true,
      pendingImporterRemainsRegistered:true},
    wholePhysicalLifetimeUpper:false,ledgerGenerationCorrespondence:false};
}
