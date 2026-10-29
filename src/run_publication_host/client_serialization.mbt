///|
pub(all) enum ClientSerializationPreparationIssue {
  MissingTask
  OutsideTask
  Barrier(@lower.SerializationPreparationIssue)
}

///|
/// Enumerate checked task occurrences, not authored syntax indices. Repeated
/// task occurrences retain their own coordinates and later borrowing duties.
pub fn prepared_client_serialization_occurrences(
  owner : PreparedClientProgram,
) -> Array[(Int, Int)] {
  client_graph_serialization_occurrences(owner.graph)
}

///|
/// Enumerate the original checked Effect graph without exposing an Effect-free
/// owner or manufacturing another preparation for physical task selection.
pub fn prepared_client_effect_serialization_occurrences(
  owner : PreparedClientEffectComputation,
) -> Array[(Int, Int)] {
  client_graph_serialization_occurrences(
    @strategy.checked_effect_computation_graph(owner.graph),
  )
}

///|
fn client_graph_serialization_occurrences(
  graph : @strategy.CheckedDAG,
) -> Array[(Int, Int)] {
  let occurrences = []
  for task in 0..<@strategy.graph_task_count(graph) {
    guard @strategy.graph_task_owner(graph, task) is Some(preparation) else {
      continue
    }
    let pipeline = @lower.pipeline(@lower.bound_preparation(preparation))
    let count = @pipeline.step_count(pipeline)
    guard client_task_output_step(graph, task, count) is Some(last) else {
      continue
    }
    let first = @strategy.graph_task_selected_step(graph, task).unwrap_or(0)
    for step in first..<(last + 1) {
      if @pipeline.serialization_order(pipeline, step) is Some(_) {
        occurrences.push((task, step))
      }
    }
  }
  occurrences
}

///|
pub(all) enum ClientSerializationPrefixIssue {
  Preparation(ClientSerializationPreparationIssue)
  ExternalInput
  Fragment(ClientTaskFragmentIssue)
}

///|
pub(all) enum ClientSerializationInputIssue {
  ForeignInput
  InputUnavailable
  RepresentationUnavailable
  InvalidRow
  RowLimit
  ProfileMismatch
  InputOrderUnfulfilled
  Encoding(@publication.ContentSerializationIssue)
}

///|
/// An exact borrowed completion paired with its existing byte cursor. This is
/// not another execution/cleanup owner: the original driver retains the input
/// and the Store reservation. Row progress remains in ContentByteEncoder.
struct ClientSerializationInput {
  barrier : @lower.PreparedSerialization
  input : @execution.CompletedOutput
  encoder : @publication.ContentByteEncoder
  rows : Int
}

///|
pub fn bind_client_serialization_completed_input(
  barrier : @lower.PreparedSerialization,
  input : @execution.CompletedOutput,
  encoder : @publication.ContentByteEncoder,
) -> Result[ClientSerializationInput, ClientSerializationInputIssue] {
  let rows = match
    validate_client_serialization_completed_input(barrier, input, encoder) {
    Ok(rows) => rows
    Err(issue) => return Err(issue)
  }
  match
    @publication.bind_content_byte_input(encoder, rows, () => {
      @execution.completed_output_available(input)
    }) {
    Ok(_) => ()
    Err(issue) => return Err(Encoding(issue))
  }
  Ok({ barrier, input, encoder, rows, })
}

///|
pub fn client_serialization_input_rows(value : ClientSerializationInput) -> Int {
  value.rows
}

///|
/// Only the next original row may enter this cursor. Busy, failed or repeated
/// calls cannot advance that ordinal or duplicate/omit rows in the completion.
pub fn start_client_serialization_input_row(
  value : ClientSerializationInput,
  row : Int,
) -> Result[Unit, ClientSerializationInputIssue] {
  if row != @publication.content_byte_completed_rows(value.encoder) {
    return Err(InvalidRow)
  }
  start_client_serialization_completed_row(
    value.barrier,
    value.input,
    row,
    value.encoder,
  )
}

///|
/// Resolve finite Host ceilings against the author guards using the checked
/// profile. This is not resource reservation or an input/order completion.
pub fn start_client_serialization_encoder(
  barrier : @lower.PreparedSerialization,
  max_rows~ : Int,
  max_bytes~ : Int,
  max_value_nodes~ : Int,
  max_value_depth~ : Int,
  max_frames~ : Int,
) -> Result[
  @publication.ContentByteEncoder,
  @publication.ContentSerializationIssue,
] {
  if max_rows < 0 || max_bytes < 0 {
    return Err(ContentInvalidLimits)
  }
  let (row_guard, byte_guard) = @lower.serialization_author_guards(barrier)
  let rows = match row_guard {
    Some(value) if value < max_rows.to_int64() => value.to_int()
    _ => max_rows
  }
  let bytes = match byte_guard {
    Some(value) if value < max_bytes.to_int64() => value.to_int()
    _ => max_bytes
  }
  @publication.start_content_byte_encoder(
    @pipeline.serialization_profile(@lower.serialization_checked(barrier)),
    max_rows=rows,
    max_bytes=bytes,
    max_value_nodes~,
    max_value_depth~,
    max_frames~,
  )
}

///|
/// Select an exact checked barrier inside this task's owned range. This is
/// preparation, not execution: retaining input, physical budget, Store custody
/// and ReferenceIssuer evidence must be admitted before byte generation.
pub fn prepare_client_serialization(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  max_work~ : Int,
) -> Result[@lower.PreparedSerialization, ClientSerializationPreparationIssue] {
  prepare_client_graph_serialization(owner.graph, task, step, max_work~)
}

///|
/// Borrow the same checked Effect task. This does not create a pure Program,
/// another admission or permission to generate/write bytes.
pub fn prepare_client_effect_serialization(
  owner : PreparedClientEffectComputation,
  task : Int,
  step : Int,
  max_work~ : Int,
) -> Result[@lower.PreparedSerialization, ClientSerializationPreparationIssue] {
  prepare_client_graph_serialization(
    @strategy.checked_effect_computation_graph(owner.graph),
    task,
    step,
    max_work~,
  )
}

///|
fn prepare_client_graph_serialization(
  graph : @strategy.CheckedDAG,
  task : Int,
  step : Int,
  max_work~ : Int,
) -> Result[@lower.PreparedSerialization, ClientSerializationPreparationIssue] {
  guard @strategy.graph_task_owner(graph, task) is Some(preparation) else {
    return Err(MissingTask)
  }
  let count = @pipeline.step_count(
    @lower.pipeline(@lower.bound_preparation(preparation)),
  )
  guard client_task_output_step(graph, task, count) is Some(last) else {
    return Err(OutsideTask)
  }
  let first = @strategy.graph_task_selected_step(graph, task).unwrap_or(0)
  if step < first || step > last {
    return Err(OutsideTask)
  }
  @lower.prepare_serialization(preparation, step, max_work~).map_err(issue => {
    Barrier(issue)
  })
}

///|
/// Lower the actual checked input, not the adjacent authored step. An external
/// input needs its existing capture/producer binding; it is not recomputed here.
/// This fragment is computation evidence, not permission to issue a ContentRef.
pub fn issue_prepared_client_serialization_prefix_fragment(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  max_preparation_work : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentNode, ClientSerializationPrefixIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(Fragment(InvalidLimits))
  }
  let barrier = match
    prepare_client_serialization(
      owner,
      task,
      step,
      max_work=max_preparation_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let terminal = match
    @pipeline.serialization_order_input(@lower.serialization_order(barrier)) {
    Step(index) => index
    Input(_) => return Err(ExternalInput)
  }
  let first = @strategy.graph_task_selected_step(owner.graph, task).unwrap_or(0)
  let selected = @strategy.graph_task_selected_step(owner.graph, task)
  if terminal < first && selected != Some(step) {
    return Err(ExternalInput)
  }
  if @pipeline.serialization_sort(@lower.serialization_checked(barrier))
    is Some(_) {
    guard @lower.node_at(
        @lower.bound_preparation(@lower.serialization_owner(barrier)),
        step,
      )
      is Some(output) else {
      return Err(Fragment(MissingOutput))
    }
    // Preserve the real checked Source/producer ports using the same task
    // emitter as acquired Compute. Only the internal sort is included here;
    // no acquisition, byte generation or capture inventory is fabricated.
    let construction = match
      construct_client_task_pipeline_prefix(
        @lower.serialization_owner(barrier),
        step,
        @lower.node_id(output),
        selected,
        Some(step),
        true,
        sequence_limits,
        max_wire_bytes,
        max_nodes,
        max_depth,
        serialization_input=Some(barrier),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Fragment(Pipeline(issue)))
    }
    return issue_client_task_fragment_body(
      @lower.serialization_owner(barrier),
      @pipeline.Step(step),
      selected,
      "task_" + task.to_string() + "_before_serialize_" + step.to_string(),
      construction,
      max_wire_bytes,
      max_nodes,
      max_depth,
      serialization_input=Some(barrier),
    ).map_err(issue => Fragment(issue))
  }
  issue_client_compute_prefix_fragment_for_owner(
    @lower.serialization_owner(barrier),
    step - 1,
    terminal,
    "task_" + task.to_string() + "_before_serialize_" + step.to_string(),
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map_err(issue => Fragment(issue))
}

///|
/// Read only the live completion of this exact input port. Dense and sparse
/// representations use their existing typed accessors; inability to read a
/// coordinate is never converted to absence or NULL. Sorting/order fulfillment,
/// reservation, Store custody and publication are still barrier obligations.
pub fn start_client_serialization_completed_row(
  barrier : @lower.PreparedSerialization,
  input : @execution.CompletedOutput,
  row : Int,
  encoder : @publication.ContentByteEncoder,
) -> Result[Unit, ClientSerializationInputIssue] {
  let rows = match
    validate_client_serialization_completed_input(barrier, input, encoder) {
    Ok(rows) => rows
    Err(issue) => return Err(issue)
  }
  if row < 0 || row >= rows {
    return Err(InvalidRow)
  }
  let checked = @lower.serialization_checked(barrier)
  let schema = @pipeline.serialization_input_schema(checked)
  @publication.start_content_runtime_row(
    encoder,
    column => {
      if !@execution.completed_output_available(input) {
        return @publication.ContentInputUnavailable
      }
      guard @schema.field_at(schema, column) is Some(field) else {
        return @publication.ContentInputUnavailable
      }
      if field.presence == @schema.Required {
        match @execution.completed_cell(input, row, column) {
          Some(Null) => @publication.ContentPresent(@values.null_value())
          Some(Number(number)) =>
            match @values.number_value(number) {
              Some(value) => @publication.ContentPresent(value)
              None => @publication.ContentInputUnavailable
            }
          Some(Boolean(boolean)) =>
            @publication.ContentPresent(@values.boolean_value(boolean))
          Some(Text(text)) => @publication.ContentText(text)
          Some(Captured(value)) => @publication.ContentPresent(value)
          None => @publication.ContentInputUnavailable
        }
      } else {
        match @execution.completed_presence_cell(input, row, column) {
          Ok(Absent) => @publication.ContentAbsent
          Ok(Present(value)) => @publication.ContentPresent(value)
          Err(_) => @publication.ContentInputUnavailable
        }
      }
    },
    () => @execution.completed_output_available(input),
  ).map_err(issue => Encoding(issue))
}

///|
fn validate_client_serialization_completed_input(
  barrier : @lower.PreparedSerialization,
  input : @execution.CompletedOutput,
  encoder : @publication.ContentByteEncoder,
) -> Result[Int, ClientSerializationInputIssue] {
  let owner = @lower.serialization_owner(barrier)
  let target = @pipeline.serialization_order_input(
    @lower.serialization_order(barrier),
  )
  if !@execution.completed_output_available(input) {
    return Err(InputUnavailable)
  }
  if @pipeline.serialization_sort(@lower.serialization_checked(barrier))
    is Some(_) {
    if !@execution.completed_output_matches_serialization_sort(input, barrier) {
      return Err(InputOrderUnfulfilled)
    }
  } else if !@execution.completed_output_matches_port(input, owner, target) {
    return Err(ForeignInput)
  }
  if !@execution.completed_has_cell_access(input) {
    return Err(RepresentationUnavailable)
  }
  let rows = @execution.completed_row_count(input)
  let (row_guard, _) = @lower.serialization_author_guards(barrier)
  if row_guard is Some(guard_value) && rows.to_int64() > guard_value {
    return Err(RowLimit)
  }
  let checked = @lower.serialization_checked(barrier)
  if !@publication.content_byte_profile_matches(
      encoder,
      @pipeline.serialization_profile(checked),
    ) {
    return Err(ProfileMismatch)
  }
  Ok(rows)
}
