import assert from 'node:assert/strict';
export const driverPath='src/connectors/local/driver/managed_dispatch.mbt';
export const strategyPath='src/physical_strategy/task_execution.mbt';
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
const release=`{
    match provider_execution.val {
      None => true
      Some(active) => {
        if !@local.managed_provider_stopped(active) ||
          !@local.cleanup_managed_provider(active).unwrap_or(false) {
          return false
        }
        final_provider_work.val = @local.managed_provider_cumulative_work(active)
        provider_execution.val = None
        true
      }
    }
  }`;
const scratch=`{
    ( disposed.val || (settled.val && finalization_ready.val) || (settled.val && carrier.val is Some(_)) ) &&
    scratch_uses.val == 0 && provider_execution.val is None &&
    bridges.all(handle => handle.val is None) && retained_imports.all(handle => handle.val is None) &&
    reads.all(read => read is None) &&
    ( !disposed.val || retained.val is Some(_) ||
      (ordinary.val is None && finalization_payload.val is None && finalization_available.val is None &&
       finalization_receipt.val is None && finalization_material.val is None && finalization_completed.val is None) ) &&
    finalization_values.val is None && finalization_retention.val is None && finalization_stream.val is None &&
    finalization_result_preparation.val is None && finalization_cids.all(cid => cid is None) && finalization_issuers.is_empty()
  }`;
const retirement=`{
  if !execution.disposed || !execution.execution_settled || !task_execution_matches(run, execution) {
    return
  }
  let scratch_released = task_execution_scratch_released(execution)
  if !scratch_released || !task_execution_retention_released(execution) {
    if @resources.reservation_open(execution.reservation) {
      @resources.settle_execution_reservation(run.ledger, execution.reservation,
        remaining_execution=if scratch_released { 0L } else { execution.scratch },)
      |> ignore
    }
    return
  }
  if execution.failed_holding is Some(holding) {
    @resources.release_allocation(run.ledger, holding) |> ignore
    execution.failed_holding = None
  }
  if @resources.reservation_open(execution.reservation) {
    @resources.settle_reservation(run.ledger, execution.reservation) |> ignore
  }
  captured_cleanup_confirmed(run, execution)
  run.executions[execution.task] = None
  let hooks = execution.hooks.unwrap()
  execution.hooks = None
  execution.resident = None
  execution.admitted_managed_inputs = None
  task_execution_released(hooks)
  collect_captured_retention(run)
}`;
export function checkDriverRetirementSource(read) {
  const driver=read(driverPath).toString(),strategy=read(strategyPath).toString();
  assert.equal(clean(blockAfter(driver,'let release_provider_scratch = fn()')),clean(release),'Changed provider stop/cleanup/work/root retirement ordering');
  assert.equal(clean(blockAfter(driver,'scratch_released: fn()')),clean(scratch),'Changed installed driver scratch witness');
  assert.equal(clean(blockAfter(strategy,'fn release_task_execution(')),clean(retirement),'Changed common reservation retirement boundary');
  assert.match(driver.replace(/\s+/g,' '),/let provider_execution : Ref\[@local\.ManagedProviderExecution\?\] = Ref\(None\)/);
  assert.deepEqual([...driver.matchAll(/provider_execution\.val\s*=\s*([^\n]+)/g)].map(m=>m[1].trim()),['None','Some(started)'],'Unreviewed provider root replacement');
  return {scope:'exact reviewed driver scratch-root and common reservation retirement boundaries',
    retainsProviderUntilStoppedAndCleanupSuccess:true,clearsProviderAfterCleanupSuccess:true,
    cachesFinalProviderWorkBeforeDroppingRoot:true,wholePhysicalLifetimeUpper:false,ledgerGenerationCorrespondence:false};
}
