///|
/// Authenticated metadata borrowed from the existing Model input Store. This
/// is not a completion or another retention owner: the original Content family
/// readmits its rows only after the common task reservation succeeds.
pub struct ClientRetainedContentOutput {
  generation : @publication_host.ClientSerializationGeneration
  run : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  store_cid : String
  binding : String
  descriptor_wire : String
  rows : Array[String]
  available : () -> Bool
}

///|
pub fn prepare_client_retained_content_output(
  generation : @publication_host.ClientSerializationGeneration,
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  store_cid : String,
  binding : String,
  descriptor_wire : String,
  rows : Array[String],
  available : () -> Bool,
) -> Result[ClientRetainedContentOutput, ClientInferRetainedInputIssue] {
  guard client_content_completion_binding(
      generation, run, definition, store_cid,
    ) ==
    Some(binding) &&
    @publication_host.client_serialization_generation_output_for(
      generation, run,
    )
    is None &&
    @publication_host.client_compiled_run_serialization(run) is Some(component) else {
    return Err(BindingMismatch)
  }
  let descriptor = match
    read_client_infer_retained_input_descriptor(descriptor_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if descriptor.output_step != component.step ||
    descriptor.rows != 1 ||
    descriptor.columns != 5 ||
    rows.length() != 1 ||
    rows[0].length() > 1000000 {
    return Err(BindingMismatch)
  }
  if !available() {
    return Err(CustodyUnavailable)
  }
  Ok({
    generation,
    run,
    definition,
    store_cid,
    binding,
    descriptor_wire,
    rows: rows.copy(),
    available,
  })
}

///|
fn client_retained_content_capacity() -> @execution.ExecutionCapacity? {
  // Admission and representation conversion can overlap. Neither conversion
  // may discard the exact stored original until the imported output is live.
  guard @local.local_import_retention_capacity({
      max_rows: 100,
      values: source_capture_values(),
      wire: source_capture_wire(),
      row: source_capture_decode(),
      max_batch_bytes: 1000000,
    })
    is Some(importing) &&
    client_content_completion_export_capacity() is Some(metadata) else {
    return None
  }
  @execution.add_execution_capacity(
    // Eight conservative fixed control slots cover the transient cumulative
    // counter, reporting closures, limited-value record and failure/result
    // branches. They do not retain another row or another physical owner.
    @execution.execution_capacity(importing, 2L * importing + 8L * 64L).unwrap(),
    metadata,
  )
}

///|
fn restore_client_content_output(
  metadata : ClientRetainedContentOutput,
  prefix : @execution.GeneratedSequence,
  barrier : @lower.PreparedSerialization,
  value_work_limit : Int,
  report_work : (Int64) -> Unit,
) -> Result[ClientInferRetainedInput, ClientInferRetainedInputIssue] {
  guard (metadata.available)() &&
    client_content_completion_binding(
      metadata.generation,
      metadata.run,
      metadata.definition,
      metadata.store_cid,
    ) ==
    Some(metadata.binding) &&
    @publication_host.client_compiled_run_serialization(metadata.run)
    is Some(component) &&
    physical_equal(
      @lower.serialization_owner(component.barrier),
      @lower.serialization_owner(barrier),
    ) &&
    component.step == @lower.serialization_step(barrier) &&
    @publication_host.client_serialization_generation_capture_for(
      metadata.generation,
      metadata.run,
      metadata.definition,
    )
    is Some(generation) &&
    @publication.bound_content_generation_reference_reissuer(generation)
    is Some(issuer) &&
    @execution.prepare_retained_serialization_completion(prefix, barrier)
    is Some(preparation) else {
    return Err(BindingMismatch)
  }
  restore_client_retained_completion(
    preparation,
    component.step,
    metadata.binding,
    metadata.binding,
    metadata.descriptor_wire,
    metadata.rows,
    () => {
      (metadata.available)() &&
      @publication_host.client_serialization_generation_capture_for(
        metadata.generation,
        metadata.run,
        metadata.definition,
      )
      is Some(_)
    },
    reference_issuer=issuer,
    value_work_limit=Some(value_work_limit),
    report_work~,
  )
}

///|
fn client_retained_content_execution(
  metadata : ClientRetainedContentOutput,
  prefix : @execution.GeneratedSequence,
  barrier : @lower.PreparedSerialization,
  physical : ClientLocalContentPhysicalPort,
  max_work : Int,
) -> Result[@local.ManagedProviderExecution, @connector.FixedComputeIssue] {
  let descriptor = match
    read_client_infer_retained_input_descriptor(metadata.descriptor_wire) {
    Ok(value) => value
    Err(_) => return Err(@connector.Execution(@execution.InputSet))
  }
  start_client_retained_content_readmission(
    descriptor.values.work,
    max_work,
    metadata.available,
    physical,
    (value_work_limit, report_work) => {
      restore_client_content_output(
        metadata, prefix, barrier, value_work_limit, report_work,
      )
    },
  )
}

///|
/// This is the original managed child start boundary, shared with focused
/// admission tests. Reject the finite three-pass envelope before calling the
/// authenticated read; failure debt still belongs to the same managed owner.
fn start_client_retained_content_readmission(
  value_work : Int,
  max_work : Int,
  available : () -> Bool,
  physical : ClientLocalContentPhysicalPort,
  restore : (Int, (Int64) -> Unit) -> Result[
    ClientInferRetainedInput,
    ClientInferRetainedInputIssue,
  ],
) -> Result[@local.ManagedProviderExecution, @connector.FixedComputeIssue] {
  guard client_retained_content_admission_work(value_work, max_work) is Some(_) else {
    return Err(@connector.Execution(@execution.InputLimit))
  }
  let actual_work = Ref(0L)
  let retained = restore(value_work, work => actual_work.val = work)
  // Even a failed atomic admission can have consumed logical work. Give the
  // existing managed owner that debt before exposing the failure; do not
  // manufacture the successful three-pass total for an incomplete read.
  if retained is Err(_) && actual_work.val == 0L {
    return Err(@connector.Execution(@execution.InputSet))
  }
  Ok(
    client_retained_content_handoff(
      retained,
      available,
      physical,
      actual_work.val,
    ),
  )
}

///|
fn client_retained_content_admission_work(
  value_work : Int,
  max_work : Int,
) -> Int64? {
  if value_work < 0 || max_work < 0 {
    return None
  }
  // Retained-content validation measures one stream. CompletedOutputImport
  // then measures BOTH its receiving row buffer and its verification stream.
  // Int64 multiplication is safe for any nonnegative Int value. The final
  // handoff consumes one more unit; no encoder/Source/model work is claimed.
  let work = 3L * value_work.to_int64()
  if work + 1L > max_work.to_int64() {
    None
  } else {
    Some(work)
  }
}

///|
/// Adapt the actual readmission's completed output to the existing managed
/// owner. Already-consumed admission work remains observable during stopping;
/// this function neither validates rows nor creates another retention owner.
fn client_retained_content_handoff(
  completion : Result[ClientInferRetainedInput, ClientInferRetainedInputIssue],
  available : () -> Bool,
  physical : ClientLocalContentPhysicalPort,
  admission_work : Int64,
) -> @local.ManagedProviderExecution {
  let retained = match completion {
    Ok(value) => Some(value)
    Err(_) => None
  }
  let cancelled = Ref(false)
  let failed = Ref(retained is None)
  let completed = Ref(false)
  let cleaned = Ref(false)
  // The existing readmission owner performs atomic bounded row admission.
  // Retain its actual consumed-work debt until the enclosing chain has
  // observed every delta; this is NOT incremental parsing or validation.
  let unreported = Ref(admission_work)
  @local.managed_provider_execution(
    quantum => {
      if quantum <= 0 || cleaned.val {
        return Err(@connector.InvalidLimits)
      }
      if completed.val {
        return Err(@connector.InvalidLimits)
      }
      if !cancelled.val &&
        (
          failed.val ||
          !available() ||
          (match retained {
            Some(value) => !@execution.completed_output_available(value.output)
            None => true
          })
        ) {
        failed.val = true
        cancelled.val = true
        (physical.cancel)() |> ignore
      }
      let delta = Int64::min(unreported.val, quantum.to_int64())
      unreported.val -= delta
      if cancelled.val {
        return if unreported.val > 0L {
          Ok(@local.managed_provider_continue(0L, delta))
        } else if failed.val {
          Ok(
            @local.managed_provider_failed(
              @connector.Execution(@execution.InputSet),
              0L,
              delta,
            ),
          )
        } else {
          Ok(@local.managed_provider_stopped_poll(0L, delta))
        }
      }
      if delta > 0L {
        return Ok(@local.managed_provider_continue(0L, delta))
      }
      // A failed read has no completion to hand off, even after draining work.
      match retained {
        Some(value) => {
          completed.val = true
          Ok(@local.managed_provider_complete(value.output, 1L, 1L))
        }
        None =>
          Ok(
            @local.managed_provider_failed(
              @connector.Execution(@execution.InputSet),
              0L,
              0L,
            ),
          )
      }
    },
    () => {
      cancelled.val = true
      (physical.cancel)()
    },
    () => {
      unreported.val == 0L &&
      (cancelled.val || completed.val) &&
      (physical.stopped)()
    },
    () => {
      if cleaned.val {
        return Ok(true)
      }
      if unreported.val > 0L ||
        !(cancelled.val || completed.val) ||
        !(physical.stopped)() {
        return Ok(false)
      }
      match (physical.cleanup)() {
        Ok(true) => {
          // Successful handoff transfers the output view to the original
          // chain. Child cleanup must not revoke that receiving view; its
          // authenticated enclosing custody still controls availability.
          if !completed.val && retained is Some(value) {
            close_client_infer_retained_input(value) |> ignore
          }
          cleaned.val = true
          Ok(true)
        }
        value => value
      }
    },
  )
}
