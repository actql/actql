///|
/// Input preparation under the normal checked Program owner. The existing
/// Local chain owns intermediate completions until the model consumer ends.
/// No ModelTask provider is invoked by input preparation.
struct ClientInferInputExecution {
  mut prefix : @local.ManagedProviderExecution?
  mut retained_input : ClientInferRetainedInput?
  mut sequence : @execution.GeneratedSequence?
  producer_inputs : Array[@local.ManagedProviderInput]
  infer_step : Int
  owner : @lower.BoundPrepared
  target : @pipeline.Target
  expressions : @lower.PreparedInferInputs
  limits : @execution.InferPreparationLimits
  control : @bounded.Control
  mut mapping : @execution.InferRowsPreparation?
  mut rows : @execution.PreparedInferRows?
  mut completed_input : @execution.CompletedOutput?
  mut prefix_done : Bool
  mut stopped : Bool
  mut cancelled : Bool
  mut reclaimed : Bool
  mut work : Int64
}

///|
pub(all) enum ClientInferInputIssue {
  UnsupportedProgram
  InvalidLimits
  Preparation(@lower.InferInputIssue)
  Local(@connector.FixedComputeIssue)
  Mapping(@execution.InferPreparationIssue)
  ProducerRead(@execution.ProducerReadIssue)
  ProducerBinding(@execution.ProducerBindingIssue)
  Capture(@query.CapturedSourceIssue)
  RetainedInput(ClientInferRetainedInputIssue)
}

///|
pub enum ClientInferInputPoll {
  Continue(work~ : Int64)
  Complete(@execution.PreparedInferRows, work~ : Int64)
  Stopped(work~ : Int64)
  Failed(ClientInferInputIssue, work~ : Int64)
}

///|
/// Start only a source-free, exact checked prefix. The installed registry is
/// admitted by the same preparation used by ordinary Local execution.
pub fn start_client_infer_input(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  mapping : @execution.InferPreparationLimits,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  if mapping.max_work < 0 || execution.max_work < 0 {
    return Err(InvalidLimits)
  }
  // This entry owns an empty input list. Acquired prefixes must be started
  // with their actual captured input owner, never through the empty route.
  if @publication_host.client_infer_prefix_owner(prepared, task, step) is None {
    return Err(UnsupportedProgram)
  }
  guard prepare_client_infer_prefix(
      prepared,
      task,
      step,
      installed_contracts,
      values_body,
      fragment_body~,
      ordered_body~,
    )
    is Some(sequence) else {
    return Err(UnsupportedProgram)
  }
  start_client_infer_input_sequence(
    sequence,
    step,
    [],
    execution,
    measurement,
    mapping,
  )
}

///|
/// Start the Local segment after source capture without replaying the scan.
/// The caller owns the capture until this input execution is reclaimed.
pub fn start_client_acquired_infer_input(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  source : @query.CapturedInputSource,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  mapping : @execution.InferPreparationLimits,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  guard @publication_host.client_acquired_infer_prefix_owner(
      prepared, task, step,
    )
    is Some(owner) &&
    @publication_host.prepare_client_query_acquisition(prepared, task, 0)
    is Ok(query) &&
    @sourceviews.query_acquisition_capture(query) is @pipeline.Step(capture) &&
    capture + 1 < step else {
    return Err(UnsupportedProgram)
  }
  guard prepare_client_infer_prefix(
      prepared,
      task,
      step,
      installed_contracts,
      values_body,
      fragment_body~,
      ordered_body~,
    )
    is Some(prefix) else {
    return Err(UnsupportedProgram)
  }
  start_client_captured_infer_input_sequence(
    owner, prefix, capture, step, source, execution, measurement, mapping,
  )
}

///|
/// Consume the original capture with the supplied immutable prefix. Selecting
/// its suffix neither regenerates a sequence nor replays the acquired scan.
fn start_client_captured_infer_input_sequence(
  owner : @lower.BoundPrepared,
  prefix : @execution.GeneratedSequence,
  capture : Int,
  step : Int,
  source : @query.CapturedInputSource,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  mapping : @execution.InferPreparationLimits,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  guard @execution.select_generated_sequence_range(
      prefix,
      capture + 1,
      step - 1,
    )
    is Some(sequence) else {
    return Err(UnsupportedProgram)
  }
  let inputs : Array[@local.ManagedProviderInput] = []
  for consumer in (capture + 1)..<step {
    guard @lower.node_at(@lower.bound_preparation(owner), consumer)
      is Some(node) else {
      return Err(UnsupportedProgram)
    }
    for port in 0..<@lower.node_input_count(node) {
      guard @lower.node_input_target(node, port) is Some(@pipeline.Step(target)) else {
        return Err(UnsupportedProgram)
      }
      if target > capture {
        continue
      }
      let bound = match
        @query.bind_captured_source_operation(source, owner, consumer, port) {
        Ok(bound) => bound
        Err(issue) => return Err(Capture(issue))
      }
      let read = match
        @execution.prepare_producer_read(
          owner,
          bound,
          execution.rows.operation_entries,
          measurement.max_bytes,
        ) {
        Ok(read) => read
        Err(issue) => return Err(ProducerRead(issue))
      }
      inputs.push(@local.managed_provider_relation_input(read))
    }
  }
  start_client_infer_input_sequence(
    sequence, step, inputs, execution, measurement, mapping,
  )
}

///|
fn start_client_infer_input_sequence(
  sequence : @execution.GeneratedSequence,
  step : Int,
  inputs : Array[@local.ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  mapping : @execution.InferPreparationLimits,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  if mapping.max_work < 0 || execution.max_work < 0 {
    return Err(InvalidLimits)
  }
  let owner = @execution.generated_sequence_owner(sequence)
  guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) &&
    @lower.node_input_target(node, 0) is Some(target) else {
    return Err(UnsupportedProgram)
  }
  let expressions = match
    @lower.prepare_infer_inputs(
      infer,
      @lower.parameter_bindings(owner),
      @publication_host.client_standard_values_sequence_limits().expressions,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ClientInferInputIssue::Preparation(issue))
  }
  guard @local.local_bounded_relation_provider(execution, measurement, sequence)
    is Some(provider) else {
    return Err(UnsupportedProgram)
  }
  // Retain the exact snapshot passed to the provider before its start can
  // reenter. Later caller mutation cannot replace this completed input proof.
  let inputs = inputs.copy()
  let prefix = match
    @local.start_managed_provider_with_inputs_and_execution(
      provider,
      sequence,
      inputs,
      execution.rows.max_rows,
      measurement.max_bytes,
      execution,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Local(issue))
  }
  Ok({
    prefix: Some(prefix),
    retained_input: None,
    sequence: Some(sequence),
    producer_inputs: inputs,
    infer_step: step,
    owner,
    target,
    expressions,
    limits: mapping,
    control: @bounded.control(),
    mapping: None,
    rows: None,
    completed_input: None,
    prefix_done: false,
    stopped: false,
    cancelled: false,
    reclaimed: false,
    work: 0L,
  })
}

///|
/// The common task driver supplies exact producer reads for a composed Unit.
/// Reuse the component's Local-prefix and Infer-row mapping owners; finished
/// caller-authored rows are not an accepted input to this operation.
pub fn start_client_composed_infer_input(
  occurrence : @publication_host.ClientInferOccurrence,
  sequence : @execution.GeneratedSequence,
  inputs : Array[@local.ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  mapping : @execution.InferPreparationLimits,
  keyed? : @publication_host.ClientKeyedLookupInput? = None,
  captured? : (
    @publication_host.PreparedClientProgram,
    @query.CapturedInputSource,
  )? = None,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  if !physical_equal(
      @publication_host.client_infer_occurrence_preparation(occurrence),
      @execution.generated_sequence_owner(sequence),
    ) ||
    (
      @execution.generated_sequence_step_count(sequence) != step &&
      !(keyed is Some(_) &&
      @execution.generated_sequence_step_count(sequence) > step)
    ) {
    return Err(UnsupportedProgram)
  }
  // The installed keyed root can borrow the retained full sequence with its
  // explicit producer vector. The original lookup and every supplied port are
  // checked below before selecting the JOIN-to-Model range once. Other entries
  // still require an exact prefix; later occurrences never enter this executor.
  for index in 0..<step {
    if @execution.generated_sequence_step_index_at(sequence, index) !=
      Some(index) {
      return Err(UnsupportedProgram)
    }
  }
  if captured is Some((prepared, source)) {
    guard inputs.is_empty() &&
      keyed is None &&
      @publication_host.client_infer_occurrence_matches(occurrence, prepared) &&
      @publication_host.client_acquired_infer_prefix_owner(prepared, 0, step)
      is Some(owner) &&
      @publication_host.prepare_client_query_acquisition(prepared, 0, 0)
      is Ok(query) &&
      @sourceviews.query_acquisition_capture(query) is @pipeline.Step(capture) &&
      capture + 1 < step else {
      return Err(UnsupportedProgram)
    }
    return start_client_captured_infer_input_sequence(
      owner, sequence, capture, step, source, execution, measurement, mapping,
    )
  }
  if keyed is Some(lookup) {
    let composed = @publication_host.client_composed_keyed_lookup_sources(
      lookup, occurrence,
    )
    let originals_match = match composed {
      None => inputs.is_empty()
      // The installed keyed root supplies no duplicate producer vector: this
      // original lookup already retains both admitted inputs and the complete
      // composed Source association. The same checked join-input handoff below
      // verifies its live originals before execution. Explicit supplied vectors
      // still need every original binding check; empty DATA alone grants none.
      Some(_) if inputs.is_empty() => true
      // One original joined Result can retain several Source ancestors. Only
      // its actual Host/direct-output binding selects this two-port branch;
      // a count, equal Result or raw Source cannot stand in for that binding.
      Some(_) if inputs.length() == 2 &&
        inputs[0] is @local.RelationInput(left) &&
        @publication_host.client_composed_keyed_lookup_result_input_matches(
          lookup, occurrence, left,
        ) => {
        guard inputs[1] is @local.SuppliedRelationInput(read) &&
          @publication_host.finish_client_keyed_lookup_input(lookup)
          is Ok(original) else {
          return Err(UnsupportedProgram)
        }
        // A representation rebind preserves logical binding identity while
        // retaining its own physical availability. Check that supplied read,
        // then keep the existing final lookup/owner fence after callbacks.
        @execution.producer_read_available(left) &&
        @execution.supplied_relation_read_same_binding(read, original) &&
        @execution.supplied_relation_read_available(read)
      }
      Some(sources) => {
        guard inputs.length() == sources.length() + 1 &&
          @publication_host.finish_client_keyed_lookup_input(lookup)
          is Ok(original) else {
          return Err(UnsupportedProgram)
        }
        // This is the ordered managed-producer vector, not the pipeline's
        // raw Source input ordinal. Imported Result ports may precede a
        // keyed Source whose raw ordinal is zero. The join receiver below
        // checks the SAME original right read at its actual operation port.
        let slot = sources.length()
        let mut matched = true
        for index, input in inputs {
          match input {
            @local.RelationInput(read) if index < sources.length() =>
              if !@publication_host.client_composed_keyed_lookup_source_read_matches(
                  lookup, occurrence, index, read,
                ) {
                matched = false
              }
            @local.SuppliedRelationInput(read) if index < slot =>
              if !@publication_host.client_composed_keyed_lookup_source_supplied_read_matches(
                  lookup, occurrence, index, read,
                ) {
                matched = false
              }
            @local.SuppliedRelationInput(read) if index == slot =>
              if !@execution.supplied_relation_read_same_binding(read, original) ||
                !@execution.supplied_relation_read_available(read) {
                matched = false
              }
            _ => matched = false
          }
        }
        matched
      }
    }

    // The existing lookup owns both admitted inputs. Execute only the suffix
    // after its acquired filter/select prefix; never replay a Source scan.
    let acquisition = @publication_host.client_keyed_lookup_acquisition(lookup)
    let (task, stage, _) = @publication_host.client_infer_occurrence_coordinates(
      occurrence,
    )
    guard originals_match &&
      @publication_host.client_keyed_acquisition_coordinates(acquisition)
      is Some((source_stage, source_task, join)) &&
      source_stage == stage &&
      source_task == task &&
      join < step &&
      physical_equal(
        @publication_host.client_keyed_acquisition_owner(acquisition),
        @publication_host.client_infer_occurrence_preparation(occurrence),
      ) &&
      @publication_host.prepare_client_keyed_lookup_join_inputs(
        lookup, sequence,
      )
      is Ok((_, left, right)) &&
      @execution.select_generated_sequence_range(sequence, join, step - 1)
      is Some(selected) else {
      return Err(UnsupportedProgram)
    }
    let prior_work = if composed is Some(_) {
      @publication_host.client_composed_keyed_lookup_prefix_work(
        lookup, occurrence,
      ).unwrap()
    } else {
      0L
    }
    if prior_work < 0L || prior_work > execution.max_work.to_int64() {
      return Err(InvalidLimits)
    }
    return start_client_infer_input_sequence(
      selected,
      step,
      [
        @local.managed_provider_relation_input(left),
        @local.managed_provider_supplied_relation_input(right),
      ],
      { ..execution, max_work: execution.max_work - prior_work.to_int(), },
      measurement,
      mapping,
    ).map(active => {
      active.work = prior_work
      active
    })
  }
  start_client_infer_input_sequence(
    sequence, step, inputs, execution, measurement, mapping,
  )
}

///|
/// Consume an authentic completion at this checked Model occurrence without
/// replaying its producer. The caller retains that producer's existing custody
/// through Model settlement; cleanup here releases only the mapping, not the
/// borrowed output. A structurally equal Program or caller-authored rows cannot
/// substitute for the exact owner and input target checked below.
pub fn start_client_completed_infer_input(
  occurrence : @publication_host.ClientInferOccurrence,
  output : @execution.CompletedOutput,
  limits : @execution.InferPreparationLimits,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  if limits.max_work < 0 {
    return Err(InvalidLimits)
  }
  let owner = @publication_host.client_infer_occurrence_preparation(occurrence)
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) &&
    @lower.node_input_target(node, 0) is Some(target) else {
    return Err(UnsupportedProgram)
  }
  let expressions = match
    @lower.prepare_infer_inputs(
      infer,
      @lower.parameter_bindings(owner),
      @publication_host.client_standard_values_sequence_limits().expressions,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let bound = match
    @execution.bind_infer_completed_input(expressions, owner, target, output) {
    Ok(value) => value
    Err(issue) => return Err(Mapping(issue))
  }
  let control = @bounded.control()
  let mapping = match
    @execution.start_infer_rows_preparation(control, bound, limits) {
    Ok(value) => value
    Err(issue) => return Err(Mapping(issue))
  }
  Ok({
    prefix: None,
    retained_input: None,
    sequence: None,
    producer_inputs: [],
    infer_step: step,
    owner,
    target,
    expressions,
    limits,
    control,
    mapping: Some(mapping),
    rows: None,
    completed_input: Some(output),
    prefix_done: true,
    stopped: false,
    cancelled: false,
    reclaimed: false,
    work: 0L,
  })
}

///|
/// Only the mapped rows actually completed by this input execution can select
/// its acquisition output contract. Equal checked programs are not sufficient.
pub fn client_infer_completion_preparation(
  active : ClientInferInputExecution,
  rows : @execution.PreparedInferRows,
) -> @execution.CompletionPreparation? {
  guard !active.reclaimed &&
    active.rows is Some(actual) &&
    physical_equal(actual, rows) else {
    return None
  }
  match active.sequence {
    Some(sequence) =>
      @execution.prepare_infer_completion(sequence, rows, active.infer_step)
    None =>
      @execution.prepare_completed_infer_completion(rows, active.infer_step)
  }
}

///|
/// The generation owner supplies its authentic Content metadata completion.
/// Execute only the selected checked suffix (for example key validation) and
/// then use the same Infer mapper. Earlier coordinates cannot run as Compute.
pub fn start_client_serialized_infer_input(
  occurrence : @publication_host.ClientInferOccurrence,
  sequence : @execution.GeneratedSequence,
  serialization_step : Int,
  output : @execution.CompletedOutput,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  mapping : @execution.InferPreparationLimits,
) -> Result[ClientInferInputExecution, ClientInferInputIssue] {
  let owner = @publication_host.client_infer_occurrence_preparation(occurrence)
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  if !physical_equal(owner, @execution.generated_sequence_owner(sequence)) ||
    serialization_step < 0 ||
    serialization_step + 1 >= step ||
    @execution.generated_sequence_step_count(sequence) !=
    step - serialization_step - 1 ||
    !@execution.completed_output_matches_port(
      output,
      owner,
      @pipeline.Step(serialization_step),
    ) {
    return Err(UnsupportedProgram)
  }
  guard @lower.sequence_step(
      @execution.generated_prepared_sequence(sequence),
      serialization_step,
    )
    is Some(@lower.CompletedProducerBoundary(_)) else {
    return Err(UnsupportedProgram)
  }
  let inputs : Array[@local.ManagedProviderInput] = []
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    let consumer = serialization_step + 1 + index
    guard @execution.generated_sequence_step_index_at(sequence, index) ==
      Some(consumer) &&
      @lower.node_at(@lower.bound_preparation(owner), consumer) is Some(node) else {
      return Err(UnsupportedProgram)
    }
    for port in 0..<@lower.node_input_count(node) {
      guard @lower.node_input_target(node, port) is Some(@pipeline.Step(target)) else {
        return Err(UnsupportedProgram)
      }
      if target > serialization_step {
        continue
      }
      let bound = match
        @execution.bind_completed_operation_input(
          owner, consumer, port, owner, output,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ProducerBinding(issue))
      }
      let read = match
        @execution.prepare_producer_read(
          owner,
          bound,
          execution.rows.operation_entries,
          measurement.max_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ProducerRead(issue))
      }
      inputs.push(@local.managed_provider_relation_input(read))
    }
  }
  start_client_infer_input_sequence(
    sequence, step, inputs, execution, measurement, mapping,
  )
}

///|
/// Borrow the actual pre-INFER completion while its existing prefix owner
/// retains it. This does not copy rows or transfer cleanup responsibility.
pub fn client_infer_completed_input(
  active : ClientInferInputExecution,
) -> @execution.CompletedOutput? {
  guard !active.reclaimed &&
    active.completed_input is Some(output) &&
    @execution.completed_output_available(output) else {
    return None
  }
  Some(output)
}

///|
/// Seal the exact external reads retained by this prefix owner after it has
/// completed. The caller cannot supply substitute reads or completed rows.
/// The copied per-input control inventory uses the existing input allowance;
/// Artifact bodies remain borrowed from their original publication owner.
pub fn client_infer_completed_result_artifact_input(
  active : ClientInferInputExecution,
  occurrence : @publication_host.ClientInferOccurrence,
  plan : @publication_host.ClientInferPlanGraph,
  import_index : Int,
  artifact : @publication_host.ClientEffectLocalResultArtifact,
  manifest : @publication_host.ClientEffectLocalManifest,
) -> Result[
  @publication_host.ClientInferResultArtifactInput,
  @publication_host.ClientInferCallScopeIssue,
] {
  guard client_infer_completed_input_provenance(active)
    is Some((output, sequence, bindings, proof)) else {
    return Err(@publication_host.ForeignInput)
  }
  @publication_host.prepare_client_infer_fixed_result_artifact_input(
    occurrence, plan, import_index, output, sequence, bindings, proof, artifact,
    manifest,
  )
}

///|
// Keep the closed provider's exact completed external-port proof together.
// This is input custody only; Artifact/manifest/occurrence admission stays
// at the existing publication owner after the same original proof is retained.
fn client_infer_completed_input_provenance(
  active : ClientInferInputExecution,
) -> (
  @execution.CompletedOutput,
  @execution.GeneratedSequence,
  Array[(Int, Int, @execution.FixedRelationRead)],
  @execution.CompletedSegmentInputs,
)? {
  guard !active.reclaimed &&
    !active.cancelled &&
    active.prefix_done &&
    active.sequence is Some(sequence) &&
    client_infer_completed_input(active) is Some(output) else {
    return None
  }
  let bindings : Array[(Int, Int, @execution.FixedRelationRead)] = []
  let count = @execution.generated_sequence_step_count(sequence)
  let mut work = 0
  for position in 0..<count {
    guard @execution.generated_sequence_step_index_at(sequence, position)
      is Some(step) &&
      @lower.node_at(@lower.bound_preparation(active.owner), step) is Some(node) else {
      return None
    }
    for port in 0..<@lower.node_input_count(node) {
      if work >= active.limits.max_work {
        return None
      }
      work += 1
      let mut selected = None
      for input in active.producer_inputs {
        if work >= active.limits.max_work {
          return None
        }
        work += 1
        let read = match input {
          @local.RelationInput(read) if @execution.producer_read_matches_operation_input(
              read,
              active.owner,
              step,
              port,
            ) => Some(@execution.fixed_completed_relation_read(read))
          @local.SuppliedRelationInput(read) if @execution.supplied_relation_read_matches_operation_input(
              read,
              active.owner,
              step,
              port,
            ) => Some(@execution.fixed_supplied_relation_read(read))
          _ => None
        }
        if read is Some(read) {
          if selected is Some(_) {
            return None
          }
          selected = Some(read)
        }
      }
      if selected is Some(read) {
        bindings.push((step, port, read))
      }
    }
  }
  guard @execution.retain_completed_fixed_segment_inputs(
      output,
      sequence,
      bindings,
      active.limits.max_work,
    )
    is Some(proof) else {
    return None
  }
  Some((output, sequence, bindings, proof))
}

///|
/// Each call advances exactly one existing child. A child transition does not
/// drain the next phase in the same call, preserving the caller's quantum.
pub fn advance_client_infer_input(
  active : ClientInferInputExecution,
  quantum : Int,
) -> Result[ClientInferInputPoll, ClientInferInputIssue] {
  if quantum <= 0 || active.stopped || active.reclaimed {
    return Err(InvalidLimits)
  }
  if active.cancelled && active.mapping is None && active.prefix_done {
    active.stopped = true
    return Ok(Stopped(work=active.work))
  }
  if !active.prefix_done {
    guard active.prefix is Some(prefix) else { return Err(InvalidLimits) }
    let poll = match @local.advance_managed_provider(prefix, quantum) {
      Ok(value) => value
      Err(issue) => {
        active.stopped = @local.managed_provider_stopped(prefix)
        return Err(Local(issue))
      }
    }
    match poll {
      @local.Continue(work~, ..) => {
        active.work += work
        Ok(Continue(work=active.work))
      }
      @local.Complete(output, work~, ..) => {
        active.work += work
        active.prefix_done = true
        active.completed_input = Some(output)
        if active.cancelled {
          active.stopped = true
          return Ok(Stopped(work=active.work))
        }
        let bound = match
          @execution.bind_infer_completed_input(
            active.expressions,
            active.owner,
            active.target,
            output,
          ) {
          Ok(value) => value
          Err(issue) => {
            active.stopped = true
            return Ok(Failed(Mapping(issue), work=active.work))
          }
        }
        active.mapping = match
          @execution.start_infer_rows_preparation(
            active.control,
            bound,
            active.limits,
          ) {
          Ok(value) => Some(value)
          Err(issue) => {
            active.stopped = true
            return Ok(Failed(Mapping(issue), work=active.work))
          }
        }
        Ok(Continue(work=active.work))
      }
      @local.Failed(issue, work~, ..) => {
        active.work += work
        active.stopped = true
        Ok(Failed(Local(issue), work=active.work))
      }
      @local.Stopped(work~, ..) => {
        active.work += work
        active.stopped = true
        Ok(Stopped(work=active.work))
      }
      @local.Waiting(work~, ..) | @local.Settling(_, work~, ..) => {
        // The checked Compute-only prefix cannot own a Model call. Reject an
        // unexpected pause without pretending its physical owner has stopped.
        active.work += work
        @local.cancel_managed_provider(prefix) |> ignore
        active.stopped = @local.managed_provider_stopped(prefix)
        Err(UnsupportedProgram)
      }
      @local.CarrierComplete(_, work~, ..) => {
        active.work += work
        active.stopped = true
        Ok(Failed(UnsupportedProgram, work=active.work))
      }
    }
  } else {
    guard active.mapping is Some(mapping) else { return Err(InvalidLimits) }
    match @execution.advance_infer_rows_preparation(mapping, quantum) {
      Ok(@execution.InferRowsContinue(work~)) =>
        Ok(Continue(work=active.work + work))
      Ok(@execution.InferRowsComplete(rows, work~)) => {
        active.rows = Some(rows)
        active.work += work
        active.stopped = true
        Ok(Complete(rows, work=active.work))
      }
      Ok(@execution.InferRowsStopped(_, work~)) => {
        active.work += work
        active.stopped = true
        Ok(Stopped(work=active.work))
      }
      Err(issue) => {
        active.stopped = true
        Ok(Failed(Mapping(issue), work=active.work))
      }
    }
  }
}

///|
pub fn cancel_client_infer_input(active : ClientInferInputExecution) -> Bool {
  if active.cancelled || active.stopped || active.reclaimed {
    return false
  }
  active.cancelled = true
  if active.prefix_done {
    @bounded.request_cancel(active.control) |> ignore
  } else if active.prefix is Some(prefix) {
    @local.cancel_managed_provider(prefix) |> ignore
  }
  true
}

///|
/// The ModelTask consumer must settle before its mapped rows and borrowed
/// prefix are reclaimed. This operation never starts or retries computation.
pub fn cleanup_client_infer_input(
  active : ClientInferInputExecution,
) -> Result[Bool, ClientInferInputIssue] {
  if active.reclaimed {
    return Ok(true)
  }
  if !active.stopped {
    return Ok(false)
  }
  if active.rows is Some(rows) {
    if !@execution.cleanup_prepared_infer_rows(rows) {
      return Ok(false)
    }
    active.rows = None
  }
  if active.mapping is Some(mapping) {
    match @execution.cleanup_infer_rows_preparation(mapping) {
      Ok(true) => ()
      Ok(false) => return Ok(false)
      Err(issue) => return Err(Mapping(issue))
    }
  }
  if active.prefix is Some(prefix) {
    match @local.cleanup_managed_provider(prefix) {
      Ok(true) => ()
      Ok(false) => return Ok(false)
      Err(issue) => return Err(Local(issue))
    }
  }
  if active.retained_input is Some(retained) {
    close_client_infer_retained_input(retained) |> ignore
  }
  // Detach the wrapper's borrowed roots only after every existing cleanup
  // owner has confirmed settlement. A pending or failed cleanup keeps the
  // same roots for retry; independently retained outputs keep their own uses.
  active.mapping = None
  active.prefix = None
  active.retained_input = None
  active.sequence = None
  active.producer_inputs.clear()
  active.reclaimed = true
  active.completed_input = None
  Ok(true)
}
