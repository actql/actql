///|
/// Adapt the existing bounded sort, identity scan and Content encoder to one
/// registered Relation-chain child. This is not another Run or ledger owner.
/// Physical Store work is retained by its installed port while Local yields.
pub(all) struct ClientLocalContentPhysicalPort {
  cancel : () -> Bool
  stopped : () -> Bool
  cleanup : () -> Result[Bool, @connector.FixedComputeIssue]
}

///|
struct ClientLocalContentStep {
  barrier : @lower.PreparedSerialization
  sort : @local.ManagedProviderExecution?
  mut borrowed : @execution.CompletedOutput?
  encoder : @publication.ContentByteEncoder
  workspace : ClientSerializationWorkspaceLimits
  physical : ClientLocalContentPhysicalPort
  max_work : Int
  mut input : @publication_host.ClientSerializationInput?
  mut identity : @execution.CompletedRelationIdentityScan?
  mut receipt : @execution.CompletedRelationExportReceipt?
  mut row : Int
  mut ready : Bool
  mut piece : String?
  mut revision : Int
  mut bytes : @publication.ContentByteCompletion?
  mut generation : @publication_host.ClientSerializationGeneration?
  mut output : @execution.CompletedOutput?
  mut phase : Int
  mut cancelled : Bool
  mut cleaned : Bool
  mut physical_cleaned : Bool
  mut sort_cleaned : Bool
}

///|
fn client_content_step_matches(
  sequence : @execution.GeneratedSequence,
  barrier : @lower.PreparedSerialization,
) -> Bool {
  let step = @lower.serialization_step(barrier)
  physical_equal(
    @execution.generated_sequence_owner(sequence),
    @lower.serialization_owner(barrier),
  ) &&
  @execution.generated_sequence_step_count(sequence) == 1 &&
  @execution.generated_sequence_step_index_at(sequence, 0) == Some(step) &&
  @execution.generated_sequence_step_at(sequence, 0)
  is Some(@lower.SerializationBoundary(actual)) &&
  actual == step
}

///|
/// The original task reserves this actual family envelope before invoking
/// start. No prefix attempt or second reservation is created by this child.
pub fn client_effect_content_local_provider(
  prepared : @publication_host.PreparedClientEffectComputation,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace : ClientSerializationWorkspaceLimits,
  physical : ClientLocalContentPhysicalPort,
  retain : (ClientLocalContentStep) -> Bool,
  recovery? : ClientRetainedContentOutput? = None,
) -> @local.ManagedProvider? {
  guard @publication_host.prepare_client_effect_serialization(
      prepared,
      task,
      step,
      max_work=10000,
    )
    is Ok(barrier) &&
    prepare_client_effect_serialization_prefix(
      prepared, task, step, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Some(prefix) else {
    return None
  }
  client_content_local_provider_owned(
    barrier, prefix, task, execution, measurement, workspace, physical, retain, recovery,
  )
}

///|
// The checked Pure/Model path uses the same Content child, encoder, physical
// piece ACK and cleanup Owner as Effect computation. This factory is not an
// original-Scope admission or a normal physical profile supplier.
pub fn client_content_local_provider(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace : ClientSerializationWorkspaceLimits,
  physical : ClientLocalContentPhysicalPort,
  retain : (ClientLocalContentStep) -> Bool,
  recovery? : ClientRetainedContentOutput? = None,
) -> @local.ManagedProvider? {
  guard @publication_host.prepare_client_serialization(
      prepared,
      task,
      step,
      max_work=10000,
    )
    is Ok(barrier) &&
    prepare_client_serialization_prefix_owned(
      Pure(prepared),
      task,
      step,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
    )
    is Some(prefix) else {
    return None
  }
  client_content_local_provider_owned(
    barrier, prefix, task, execution, measurement, workspace, physical, retain, recovery,
  )
}

///|
fn client_content_local_provider_owned(
  barrier : @lower.PreparedSerialization,
  prefix : @execution.GeneratedSequence,
  task : Int,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace : ClientSerializationWorkspaceLimits,
  physical : ClientLocalContentPhysicalPort,
  retain : (ClientLocalContentStep) -> Bool,
  recovery : ClientRetainedContentOutput?,
) -> @local.ManagedProvider? {
  let step = @lower.serialization_step(barrier)
  if recovery is Some(metadata) {
    guard client_content_completion_binding(
        metadata.generation,
        metadata.run,
        metadata.definition,
        metadata.store_cid,
      ) ==
      Some(metadata.binding) &&
      @publication_host.client_compiled_run_serialization(metadata.run)
      is Some(component) &&
      component.task == task &&
      component.step == step &&
      physical_equal(
        @lower.serialization_owner(component.barrier),
        @lower.serialization_owner(barrier),
      ) &&
      client_retained_content_capacity() is Some(capacity) else {
      return None
    }
    let opened = Ref(false)
    return Some(
      @local.managed_provider_with_inputs(
        sequence => client_content_step_matches(sequence, barrier),
        sequence => {
          if client_content_step_matches(sequence, barrier) {
            Some(capacity)
          } else {
            None
          }
        },
        (sequence, inputs, max_rows, _, limits) => {
          if opened.val ||
            !client_content_step_matches(sequence, barrier) ||
            max_rows < 1 {
            return Err(@connector.ComputeUnsupported)
          }
          guard inputs is [@local.RelationInput(read)] &&
            @execution.producer_read_matches_operation_input(
              read,
              @lower.serialization_owner(barrier),
              step,
              0,
            ) else {
            return Err(@connector.Execution(@execution.InputSet))
          }
          match
            client_retained_content_execution(
              metadata,
              prefix,
              barrier,
              physical,
              limits.max_work,
            ) {
            Ok(value) => {
              opened.val = true
              Ok(value)
            }
            Err(issue) => Err(issue)
          }
        },
      ),
    )
  }
  let sort = if @pipeline.serialization_sort(
      @lower.serialization_checked(barrier),
    )
    is Some(_) {
    guard @execution.select_generated_sequence_step(prefix, step)
      is Some(sequence) &&
      @local.local_bounded_relation_provider(execution, measurement, sequence)
      is Some(provider) &&
      @local.managed_provider_capacity(provider, sequence) is Some(capacity) else {
      return None
    }
    Some((sequence, provider, capacity))
  } else {
    None
  }
  let sort_capacity = match sort {
    Some((_, _, capacity)) => capacity
    None => @execution.execution_capacity(0L, 0L).unwrap()
  }
  guard client_serialization_workspace_capacity(workspace)
    is Some(workspace_capacity) &&
    add_client_serialization_workspace_capacity(
      sort_capacity, workspace_capacity,
    )
    is Some(capacity) else {
    return None
  }
  // Explicit envelope for this adapter's roots, pending-piece slot and phase
  // handles, in addition to the existing sort/identity/encoder allowances.
  guard @execution.execution_capacity(32L * 256L, 32L * 256L) is Some(handles) &&
    add_client_serialization_workspace_capacity(capacity, handles)
    is Some(capacity) &&
    client_content_completion_export_capacity() is Some(completion_export) &&
    add_client_serialization_workspace_capacity(capacity, completion_export)
    is Some(capacity) else {
    return None
  }
  let opened = Ref(false)
  Some(
    @local.managed_provider_with_inputs(
      sequence => client_content_step_matches(sequence, barrier),
      sequence => {
        if client_content_step_matches(sequence, barrier) {
          Some(capacity)
        } else {
          None
        }
      },
      (sequence, inputs, max_rows, max_value_bytes, limits) => {
        if opened.val ||
          !client_content_step_matches(sequence, barrier) ||
          max_rows < workspace.export_limits.max_rows {
          return Err(@connector.ComputeUnsupported)
        }
        guard inputs is [@local.RelationInput(read)] &&
          @execution.producer_read_matches_operation_input(
            read,
            @lower.serialization_owner(barrier),
            step,
            0,
          ) else {
          return Err(@connector.Execution(@execution.InputSet))
        }
        let encoder = match
          @publication_host.start_client_serialization_encoder(
            barrier,
            max_rows=workspace.export_limits.max_rows,
            max_bytes=workspace.generation_bytes,
            max_value_nodes=workspace.generation_nodes,
            max_value_depth=workspace.generation_depth,
            max_frames=workspace.generation_frames,
          ) {
          Ok(value) => value
          Err(_) => return Err(@connector.Execution(@execution.InputLimit))
        }
        let (child, borrowed) = match sort {
          Some((sequence, provider, _)) =>
            match
              @local.start_managed_provider_with_inputs_and_execution(
                provider, sequence, inputs, max_rows, max_value_bytes, limits,
              ) {
              Ok(value) => (Some(value), None)
              Err(issue) => return Err(issue)
            }
          None => {
            guard @execution.serialization_completed_producer_input(
                barrier, read,
              )
              is Some(output) else {
              return Err(@connector.Execution(@execution.InputSet))
            }
            (None, Some(output))
          }
        }
        opened.val = true
        let active : ClientLocalContentStep = {
          barrier,
          sort: child,
          borrowed,
          encoder,
          workspace,
          physical,
          max_work: limits.max_work,
          input: None,
          identity: None,
          receipt: None,
          row: 0,
          ready: false,
          piece: None,
          revision: 0,
          bytes: None,
          generation: None,
          output: None,
          phase: 0,
          cancelled: false,
          cleaned: false,
          physical_cleaned: false,
          sort_cleaned: false,
        }
        if !retain(active) {
          // No allocated child is discarded. The same returned execution retains
          // stop and cleanup responsibility even when Host handoff is refused.
          active.cancelled = true
          (physical.cancel)() |> ignore
          if child is Some(child) {
            @local.cancel_managed_provider(child) |> ignore
          }
        }
        Ok(
          @local.managed_provider_execution(
            quantum => advance_client_content_step(active, quantum),
            () => {
              active.cancelled = true
              @publication.cancel_content_byte_encoder(active.encoder)
              if active.sort is Some(child) {
                @local.cancel_managed_provider(child) |> ignore
              }
              (active.physical.cancel)()
            },
            () => {
              active.sort.map(@local.managed_provider_stopped).unwrap_or(true) &&
              (active.physical.stopped)() &&
              (active.cancelled || active.phase >= 4)
            },
            () => cleanup_client_content_step(active),
          ),
        )
      },
    ),
  )
}

///|
fn fail_client_content_step(
  active : ClientLocalContentStep,
  issue : @connector.FixedComputeIssue,
  work : Int64,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  active.phase = 9
  @publication.cancel_content_byte_encoder(active.encoder)
  Ok(@local.managed_provider_failed(issue, work, work))
}

///|
fn advance_client_content_step(
  active : ClientLocalContentStep,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  if quantum <= 0 || active.cleaned {
    return Err(@connector.InvalidLimits)
  }
  if active.cancelled {
    if active.sort is Some(child) && !@local.managed_provider_stopped(child) {
      @local.cancel_managed_provider(child) |> ignore
      let poll = match @local.advance_managed_provider(child, 1) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      return match poll {
        Complete(_, progress~, work~)
        | Failed(_, progress~, work~)
        | Stopped(progress~, work~) =>
          if (active.physical.stopped)() {
            Ok(@local.managed_provider_stopped_poll(progress, work))
          } else {
            Ok(@local.managed_provider_waiting(progress, work))
          }
        value => Ok(value)
      }
    }
    return if (active.physical.stopped)() {
      Ok(@local.managed_provider_stopped_poll(0L, 0L))
    } else {
      Ok(@local.managed_provider_waiting(0L, 0L))
    }
  }
  if active.phase >= 4 {
    return Err(@connector.InvalidLimits)
  }
  // Zero-work phase transitions never become an invented Continue(1).
  // The next actual bounded cursor runs in this same call instead.
  for _ in 0..<4 {
    match active.phase {
      0 => {
        let poll = match active.sort {
          Some(child) =>
            match @local.advance_managed_provider(child, quantum) {
              Ok(value) => value
              Err(issue) => return Err(issue)
            }
          None => {
            guard active.borrowed is Some(output) else {
              return Err(@connector.Execution(@execution.InputSet))
            }
            @local.managed_provider_complete(output, 0L, 0L)
          }
        }
        match poll {
          Complete(output, progress~, work~) => {
            let input = match
              @publication_host.bind_client_serialization_completed_input(
                active.barrier,
                output,
                active.encoder,
              ) {
              Ok(value) => value
              Err(_) =>
                return fail_client_content_step(
                  active,
                  @connector.Execution(@execution.InputSet),
                  work,
                )
            }
            let limits = active.workspace.export_limits
            let scan = match
              @publication_host.start_client_serialization_input_identity(
                input,
                limits.values,
                limits.payload_wire,
                limits.logical_wire,
                limits.schema,
                active.max_work,
                active.workspace.identity_slots,
              ) {
              Ok(value) => value
              Err(_) =>
                return fail_client_content_step(
                  active,
                  @connector.Execution(@execution.InputLimit),
                  work,
                )
            }
            active.input = Some(input)
            active.borrowed = None
            active.identity = Some(scan)
            active.phase = 1
            if work > 0L {
              return Ok(@local.managed_provider_continue(progress, work))
            }
          }
          Failed(_, ..) | Stopped(..) => {
            active.phase = 9
            return Ok(poll)
          }
          value => return Ok(value)
        }
      }
      1 => {
        let scan = active.identity.unwrap()
        let before = @execution.completed_relation_identity_scan_work(scan)
        let (complete, work) = match
          @execution.advance_completed_relation_identity_scan(scan, quantum) {
          Ok(value) => value
          Err(_) =>
            return fail_client_content_step(
              active,
              @connector.Execution(@execution.InputSet),
              @execution.completed_relation_identity_scan_work(scan) - before,
            )
        }
        if complete {
          match
            @execution.finish_completed_relation_identity_scan(
              active.identity.unwrap(),
            ) {
            Ok(receipt) => active.receipt = Some(receipt)
            Err(_) =>
              return fail_client_content_step(
                active,
                @connector.Execution(@execution.InputSet),
                work.to_int64(),
              )
          }
          active.identity = None
          active.phase = 2
        }
        if work > 0 {
          return Ok(
            @local.managed_provider_continue(work.to_int64(), work.to_int64()),
          )
        }
      }
      2 => {
        if active.piece is Some(_) {
          return Ok(@local.managed_provider_settling(0, 0L, 0L))
        }
        if active.ready {
          let input = active.input.unwrap()
          if active.row ==
            @publication_host.client_serialization_input_rows(input) {
            match @publication.finish_content_bytes(active.encoder) {
              Ok(value) => active.bytes = Some(value)
              Err(_) =>
                return fail_client_content_step(
                  active,
                  @connector.Execution(@execution.InputSet),
                  0L,
                )
            }
            active.phase = 3
            return Ok(@local.managed_provider_settling(1, 0L, 0L))
          }
          if @publication_host.start_client_serialization_input_row(
              input,
              active.row,
            )
            is Err(_) {
            return fail_client_content_step(
              active,
              @connector.Execution(@execution.InputSet),
              0L,
            )
          }
          active.row += 1
          active.ready = false
        }
        let (piece, work, ready) = match
          @publication.advance_content_bytes(
            active.encoder,
            Int::min(quantum, 64),
          ) {
          @publication.ContentBytesContinue(piece, work~) =>
            (piece, work, false)
          @publication.ContentBytesReady(piece, work~) => (piece, work, true)
          @publication.ContentBytesFailed(_, work~) =>
            return fail_client_content_step(
              active,
              @connector.Execution(@execution.InputSet),
              work.to_int64(),
            )
        }
        active.ready = ready
        if !piece.is_empty() {
          if active.revision == 2147483647 {
            return fail_client_content_step(
              active,
              @connector.InvalidLimits,
              work.to_int64(),
            )
          }
          active.revision += 1
          active.piece = Some(piece)
          return Ok(
            @local.managed_provider_settling(
              0,
              work.to_int64(),
              work.to_int64(),
            ),
          )
        }
        if work > 0 {
          return Ok(
            @local.managed_provider_continue(work.to_int64(), work.to_int64()),
          )
        }
      }
      3 => {
        if active.output is Some(output) {
          active.phase = 4
          return Ok(@local.managed_provider_complete(output, 0L, 0L))
        }
        return Ok(@local.managed_provider_settling(1, 0L, 0L))
      }
      _ => return Err(@connector.InvalidLimits)
    }
  }
  Err(@connector.InvalidLimits)
}

///|
pub fn client_local_content_pending_piece(
  active : ClientLocalContentStep,
) -> (Int, String)? {
  if active.cancelled || active.cleaned {
    None
  } else {
    active.piece.map(piece => (active.revision, piece))
  }
}

///|
/// The physical writer confirms this exact volatile piece only after append.
/// An unknown append must retain its original Store handle, not acknowledge it.
pub fn acknowledge_client_local_content_piece(
  active : ClientLocalContentStep,
  revision : Int,
) -> Bool {
  if active.cancelled ||
    active.cleaned ||
    active.piece is None ||
    revision != active.revision {
    return false
  }
  active.piece = None
  true
}

///|
pub fn client_local_content_generation_input(
  active : ClientLocalContentStep,
) -> (
  @publication_host.ClientSerializationInput,
  @execution.CompletedRelationExportReceipt,
  @publication.ContentByteEncoder,
)? {
  if active.cancelled ||
    active.cleaned ||
    active.phase != 3 ||
    active.piece is Some(_) {
    return None
  }
  Some((active.input.unwrap(), active.receipt.unwrap(), active.encoder))
}

///|
pub fn client_local_content_byte_completion(
  active : ClientLocalContentStep,
) -> @publication.ContentByteCompletion? {
  if active.cancelled || active.cleaned || active.phase != 3 {
    None
  } else {
    active.bytes
  }
}

///|
pub fn client_local_content_step_generation(
  active : ClientLocalContentStep,
) -> @publication_host.ClientSerializationGeneration? {
  if active.cancelled || active.cleaned {
    None
  } else {
    active.generation
  }
}

///|
pub fn complete_client_local_content_step(
  active : ClientLocalContentStep,
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  evidence : @publication_host.ClientSerializationInputEvidence,
  candidate : @publication.GeneratedContentReference,
  content : @admitted.CheckedValue,
  available : () -> Bool,
  limits : @execution.ValueLimits,
  max_name_bytes : Int,
) -> Result[
  @publication_host.ClientSerializationGeneration,
  @publication_host.ClientSerializationGenerationIssue,
] {
  guard client_local_content_generation_input(active) is Some((input, _, _)) else {
    return Err(ForeignInput)
  }
  let generation = match
    @publication_host.complete_client_serialization_generation(
      run, definition, input, evidence, candidate, content, available, limits, max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @publication_host.client_serialization_generation_output_for(
      generation, run,
    )
    is Some(output) else {
    return Err(ForeignRun)
  }
  active.generation = Some(generation)
  active.output = Some(output)
  // A positive generation is observed by the existing chain on its next poll.
  // No completion is synthesized from byte counts or a physical digest.
  active.phase = 3
  Ok(generation)
}

///|
fn cleanup_client_content_step(
  active : ClientLocalContentStep,
) -> Result[Bool, @connector.FixedComputeIssue] {
  if active.cleaned {
    return Ok(true)
  }
  if !active.cancelled && active.phase < 4 {
    return Ok(false)
  }
  if !active.sort.map(@local.managed_provider_stopped).unwrap_or(true) ||
    !(active.physical.stopped)() {
    return Ok(false)
  }
  if !active.physical_cleaned {
    match (active.physical.cleanup)() {
      Ok(true) => active.physical_cleaned = true
      result => return result
    }
  }
  if !active.sort_cleaned {
    if active.sort is Some(child) {
      match @local.cleanup_managed_provider(child) {
        Ok(true) => active.sort_cleaned = true
        result => return result
      }
    } else {
      active.sort_cleaned = true
    }
  }
  @publication.cancel_content_byte_encoder(active.encoder)
  if active.identity is Some(identity) {
    @execution.cancel_completed_relation_identity_scan(identity) |> ignore
  }
  active.identity = None
  active.input = None
  active.borrowed = None
  active.receipt = None
  active.piece = None
  // The family must not retain completed output/proof/byte roots after its
  // actual physical and sort cleanup. Independently escaped generation views
  // still borrow their separate live byte holding; do not revoke that custody.
  active.bytes = None
  active.generation = None
  active.output = None
  active.cleaned = true
  Ok(true)
}
