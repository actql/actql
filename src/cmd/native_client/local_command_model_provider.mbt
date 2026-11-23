///|
// Register only the compile-selected task. The deferred callbacks borrow the
// current command slot; the module does not retain a second Read or Work.
fn LocalCommandPreparationOriginal::configured_native_model_provider(
  self : Self,
  business : LocalCommandBusinessOriginal,
  selection : LocalCommandModelCompilation,
  index : Int,
  prefix : @execution.GeneratedSequence,
  suffix : @execution.GeneratedSequence?,
) -> @local_compute.ManagedProvider {
  let limits = selection.bounds[index]
  let graph = selection.graphs[index]
  @infer.composed_local_provider(
    graph.occurrence,
    limits,
    inputs => {
      guard business.model_run is Some(model) &&
        business.model_work.get(index) is Some(work) &&
        physical_equal(model.graphs[index], graph) else {
        return Err(@infer.InvalidAdvance)
      }
      let opened = model.open_model_component(
        index, work, limits, prefix, suffix, inputs,
      )
      match opened {
        Err(issue) => {
          self.retain_primary(CommandBusinessModel(issue))
          Err(@infer.InvalidAdvance)
        }
        Ok(value) => Ok(value)
      }
    },
    _ => @compute_sdk.ComputeUnsupported,
    retain_completed=active => {
      guard business.model_run is Some(model) &&
        model.completions[index] is None &&
        @infer.acquire_output(active) is Some(held) else {
        return false
      }
      model.completions[index] = Some(held)
      true
    },
    allow_cleanup=_ => business.model_work.get(index) is None,
    input_prefix=Some(
      // The original command retains Work and closes it before its Read.
      // Local must not independently reclaim a live Model/Store continuation.
      prefix,
    ),
    host_await_io=true,
    original_step=Some(
      (
        active => {
          guard business.model_work.get(index) is Some(work) else {
            return Err(@compute_sdk.ComputeUnsupported)
          }
          self.require_managed_model_step(work.enter_managed_model_step(active))
        },
        (active, advanced) => {
          guard business.model_work.get(index) is Some(work) else {
            return Err(@compute_sdk.ComputeUnsupported)
          }
          self.require_managed_model_step(
            work.leave_managed_model_step(active, advanced),
          )
        },
      ),
    ),
  )
}

///|
fn LocalCommandPreparationOriginal::require_managed_model_step(
  self : Self,
  result : Result[Unit, @local_host.NativeClientMockModelIssue],
) -> Result[Unit, @compute_sdk.FixedComputeIssue] {
  result.map_err(issue => {
    self.retain_primary(CommandBusinessModel(issue))
    @compute_sdk.ComputeUnsupported
  })
}

///|
fn LocalCommandModelRun::open_model_component(
  self : Self,
  index : Int,
  work : @local_host.NativeClientMockModelWork,
  limits : @infer.Limits,
  prefix : @execution.GeneratedSequence,
  suffix : @execution.GeneratedSequence?,
  inputs : Array[@local_compute.ManagedProviderInput],
) -> Result[@infer.Execution, @local_host.NativeClientMockModelIssue] {
  guard self.reads[index] is None else { return Err(ForeignOriginal) }
  let scope = self.scopes[index]
  let graph = self.graphs[index]
  let retained = limits.mapping.logical.max_live_value_bytes
  let execution = limits.identity.wire.max_bytes.to_int64()
  let read = match
    @run_host.prepare_client_model_read(scope, retained, execution) {
    Err(issue) =>
      return Err(
        @local_host.Model(@infer.OriginalCapacity(@run_host.Read(issue))),
      )
    Ok(value) => value
  }
  self.reads[index] = Some(read)
  @run_host.claim_client_model_read_preparation(
    read,
    self.compiled,
    self.definition,
    graph,
    retained,
    execution,
  )
  .map_err(issue => {
    @local_host.NativeClientMockModelIssue::Model(
      @infer.OriginalCapacity(@run_host.Read(issue)),
    )
  })
  .bind(consumer => {
    work.open(
      prefix,
      consumer,
      retained,
      execution,
      retained,
      execution,
      input_body_read=Some(read),
      inputs~,
      compiled_prefix=true,
      compiled_suffix=suffix,
    )
  })
  .bind(_ => work.borrow_opened_original_model())
}
