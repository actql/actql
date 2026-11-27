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
        index,
        work,
        business.model_work,
        limits,
        prefix,
        suffix,
        inputs,
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
  works : Array[@local_host.NativeClientMockModelWork],
  limits : @infer.Limits,
  prefix : @execution.GeneratedSequence,
  suffix : @execution.GeneratedSequence?,
  inputs : Array[@local_compute.ManagedProviderInput],
) -> Result[@infer.Execution, @local_host.NativeClientMockModelIssue] {
  let sources = self.whole_inputs.bind(values => values.sources.get(index))
  let graph = self.graphs[index]
  let (task, _, _) = @run_host.client_infer_occurrence_coordinates(
    graph.occurrence,
  )
  let count = @run_host.client_infer_occurrence_result_import_count(
    graph.occurrence,
  )
  let bindings = if sources is Some(_) && count > 0 {
    guard self.whole_inputs is Some(original) &&
      original.pending is Some((selected, bindings)) &&
      selected == task &&
      bindings.length() == count else {
      return Err(ForeignOriginal)
    }
    match
      work.check_model_output_dependency_ports(
        works,
        self.completions,
        bindings,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    // Local supplies its task inputs in the same order checked at staging.
    // Refuse a different Read before opening the Model child, even when it
    // was made from the same Result. The completed prefix will still prove
    // which original input it actually consumed before issuing CallScope.
    for index, (slot, _, _, position, read) in bindings {
      guard slot == index &&
        inputs.get(position) is Some(@local_compute.RelationInput(actual)) &&
        physical_equal(actual, read) &&
        @execution.producer_read_available(actual) else {
        return Err(ForeignOriginal)
      }
    }
    if !self.whole_result_inputs_current(original, task, bindings) {
      return Err(ForeignOriginal)
    }
    Some((original, bindings))
  } else {
    None
  }
  guard self.reads[index] is None &&
    (self.requirements is Some(_) || sources is Some(_)) else {
    return Err(ForeignOriginal)
  }
  let scope = self.scopes[index]
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
      sources~,
      input_body_read=Some(read),
      inputs~,
      compiled_prefix=true,
      compiled_suffix=suffix,
    )
  })
  .bind(_ => work.borrow_opened_original_model())
  .bind(active => {
    if bindings is Some((original, bindings)) {
      for (slot, artifact, manifest, _, _) in bindings {
        match
          @infer.bind_whole_result_artifact_input(
            active,
            slot,
            artifact,
            manifest,
            reader=work.model_output_dependency_reader(slot),
          ) {
          Err(issue) => return Err(Model(issue))
          Ok(_) => ()
        }
      }
      if !self.whole_result_inputs_current(original, task, bindings) {
        return Err(ForeignOriginal)
      }
      original.pending = None
    }
    Ok(active)
  })
}

///|
fn LocalCommandModelRun::whole_result_inputs_current(
  self : Self,
  original : LocalCommandWholeModelInputs,
  task : Int,
  bindings : @local_host.NativeWholeModelResultInputs,
) -> Bool {
  self.whole_inputs is Some(current) &&
  physical_equal(current, original) &&
  current.pending is Some((selected, retained)) &&
  selected == task &&
  physical_equal(retained, bindings)
}
