///|
// Borrowed originals of the existing prefix/lookup. The prefix reservation,
// captured Sources and Model Scope keep their original cleanup duties.
priv struct ClientComposedKeyedOriginal {
  scope : ClientModelReadScope
  compiled : ClientCompiledRun
  definition : @publication.PublicationContract
  plan : ClientInferPlanGraph
  keyed : ClientKeyedAcquisition
  sources : Array[@query.CapturedInputSource]
  captures : @row_host.RowCapturedInputs
  sequence : @execution.GeneratedSequence
  inputs : Array[(Int, Int, @execution.ProducerRead)]
  completed : @execution.CompletedSegmentInputs?
  direct_output : @execution.CompletedOutput?
  prefix : @resources.Reservation?
  prefix_work : Int64
  producers : ClientComposedKeyedProducerIndex
  host : @strategy.CapturedEffectRunDAG?
  host_sources : Array[@acquisition.SourceAcquisition]
}

///|
// Immutable slot metadata on the SAME completed lookup. The retained vector
// keeps its caller order; neither the index nor a task number proves output,
// currentness, a read grant or completion.
priv enum ClientComposedKeyedProducerIndex {
  NoProducers
  ProducerSlots(Array[ClientComposedKeyedProducer], Array[Int])
}

///|
// The caller backs the copied vector and exact Source/task index before this
// constructor. Both phases use the existing prefix's control reservation.
fn client_composed_keyed_index_producers(
  producers : Array[ClientComposedKeyedProducer],
  sources : Int,
  tasks : Int,
) -> ClientComposedKeyedProducerIndex? {
  if producers.is_empty() {
    return Some(NoProducers)
  }
  if sources < 0 || tasks < 0 || sources > 2147483647 - tasks {
    return None
  }
  let slots = Array::make(sources + tasks, -1)
  for index, producer in producers {
    if producer.slot < 0 ||
      producer.slot >= sources ||
      producer.task < 0 ||
      producer.task >= tasks ||
      slots[producer.slot] != -1 ||
      slots[sources + producer.task] != -1 {
      return None
    }
    slots[producer.slot] = index
    slots[sources + producer.task] = index
  }
  Some(ProducerSlots(producers.copy(), slots))
}

///|
fn client_composed_keyed_indexed_producer(
  index : ClientComposedKeyedProducerIndex,
  slot : Int,
) -> ClientComposedKeyedProducer? {
  match index {
    NoProducers => None
    ProducerSlots(producers, slots) => {
      guard slots.get(slot) is Some(position) &&
        position >= 0 &&
        producers.get(position) is Some(producer) &&
        producer.slot == slot else {
        return None
      }
      Some(producer)
    }
  }
}

///|
// A borrowed, actually executed Root result. The Source remains its original
// input observation; this record cannot turn that observation into a completed
// Stage. Its provider, reservation and exact input reads stay alive together.
struct ClientComposedKeyedProducer {
  scope : ClientModelReadScope
  compiled : ClientCompiledRun
  definition : @publication.PublicationContract
  plan : ClientInferPlanGraph
  keyed : ClientKeyedAcquisition
  source : @query.CapturedInputSource
  slot : Int
  task : Int
  sequence : @execution.GeneratedSequence
  inputs : Array[(Int, Int, @execution.ProducerRead)]
  completed : @execution.CompletedSegmentInputs
  reservation : @resources.Reservation
}

///|
// Select the original Source's enclosing Root, not its downstream consumer.
// This does not issue an output or replace any pending Compute completion.
pub fn prepare_client_composed_keyed_producer_inputs(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  keyed : ClientKeyedAcquisition,
  sources : Array[@query.CapturedInputSource],
  captures : @row_host.RowCapturedInputs,
  slot : Int,
  sequence : @execution.GeneratedSequence,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[Array[(Int, Int, @execution.ProducerRead)], ClientKeyedRequestIssue] {
  guard borrow_client_original_composed_keyed_ledger(
      scope, compiled, definition, plan, keyed, sources, captures,
    )
    is Ok(_) &&
    sources.get(slot) is Some(source) &&
    @row_host.row_captured_inputs_source_original_at(captures, slot) is Some(_) &&
    select_client_direct_acquisition_occurrences(plan.owner, 1000000)
    is Ok(direct) &&
    client_direct_acquisition_occurrence_at(direct, slot) is Some((_, _, task)) &&
    task != plan.task &&
    @strategy.graph_task_owner(plan.owner.graph, task) is Some(owner) &&
    physical_equal(owner, @execution.generated_sequence_owner(sequence)) &&
    @execution.generated_sequence_step_count(sequence) > 0 &&
    @execution.generated_sequence_step_index_at(
      sequence,
      @execution.generated_sequence_step_count(sequence) - 1,
    ).map(step => @pipeline.Step(step)) ==
    @lower.preparation_output_target(@lower.bound_preparation(owner)) else {
    return Err(ForeignLeft)
  }
  let inputs = []
  for position in 0..<@execution.generated_sequence_step_count(sequence) {
    let step = @execution.generated_sequence_step_index_at(sequence, position).unwrap()
    let node = @lower.node_at(@lower.bound_preparation(owner), step).unwrap()
    for port in 0..<@lower.node_input_count(node) {
      let target = @lower.node_input_target(node, port).unwrap()
      if target is @pipeline.Step(previous) {
        let mut internal = false
        for index in 0..<position {
          if @execution.generated_sequence_step_index_at(sequence, index) ==
            Some(previous) {
            internal = true
            break
          }
        }
        if internal {
          continue
        }
      }
      let bound = match
        @query.bind_captured_source_operation(source, owner, step, port) {
        Ok(value) => value
        Err(issue) => return Err(Capture(issue))
      }
      let read = match
        @execution.prepare_producer_read(
          owner, bound, max_entries, max_name_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Read(issue))
      }
      inputs.push((step, port, read))
    }
  }
  if inputs.is_empty() {
    return Err(ForeignLeft)
  }
  Ok(inputs)
}

///|
// Only the actual provider caller supplies this completed output. Exact
// segment-input provenance and the same Scope reservation are retained, not a
// schema-only or equal-row assertion. The caller funds this copied inventory.
pub fn retain_client_composed_keyed_producer(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  keyed : ClientKeyedAcquisition,
  sources : Array[@query.CapturedInputSource],
  captures : @row_host.RowCapturedInputs,
  slot : Int,
  sequence : @execution.GeneratedSequence,
  inputs : Array[(Int, Int, @execution.ProducerRead)],
  output : @execution.CompletedOutput,
  reservation : @resources.Reservation,
  max_work : Int,
) -> Result[ClientComposedKeyedProducer, ClientKeyedRequestIssue] {
  guard borrow_client_original_composed_keyed_ledger(
      scope,
      compiled,
      definition,
      plan,
      keyed,
      sources,
      captures,
      prefix=Some(reservation),
    )
    is Ok(_) &&
    sources.get(slot) is Some(source) &&
    @row_host.row_captured_inputs_source_original_at(captures, slot) is Some(_) &&
    select_client_direct_acquisition_occurrences(plan.owner, 1000000)
    is Ok(direct) &&
    client_direct_acquisition_occurrence_at(direct, slot) is Some((_, _, task)) &&
    task != plan.task &&
    @strategy.graph_task_owner(plan.owner.graph, task) is Some(owner) &&
    physical_equal(owner, @execution.generated_sequence_owner(sequence)) &&
    @lower.preparation_output_target(@lower.bound_preparation(owner))
    is Some(target) &&
    @execution.completed_output_matches_port(output, owner, target) &&
    !inputs.is_empty() &&
    inputs.all(value => {
      @query.captured_source_matches_segment_input(source, value.2)
    }) &&
    @execution.retain_completed_segment_inputs(
      output, sequence, inputs, max_work,
    )
    is Some(completed) else {
    return Err(ForeignLeft)
  }
  Ok({
    scope,
    compiled,
    definition,
    plan,
    keyed,
    source,
    slot,
    task,
    sequence,
    inputs: inputs.copy(),
    completed,
    reservation,
  })
}

///|
fn client_composed_keyed_producer_output(
  value : ClientComposedKeyedProducer,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  keyed : ClientKeyedAcquisition,
  sources : Array[@query.CapturedInputSource],
) -> @execution.CompletedOutput? {
  guard physical_equal(value.scope, scope) &&
    physical_equal(value.compiled, compiled) &&
    physical_equal(value.definition, definition) &&
    physical_equal(value.plan, plan) &&
    physical_equal(value.keyed, keyed) &&
    sources.get(value.slot) is Some(source) &&
    physical_equal(source, value.source) &&
    @query.captured_source_available(source) &&
    @resources.original_borrowed_reservation_available(
      scope.identity,
      scope.ledger,
      value.reservation,
    ) else {
    return None
  }
  @execution.completed_segment_inputs_output(
    value.completed,
    value.sequence,
    value.inputs,
  )
}

///|
pub fn select_client_effect_composed_model_keyed_acquisition(
  prepared : PreparedClientEffectComputation,
  plan : ClientInferPlanGraph,
) -> Result[ClientKeyedAcquisition?, ClientKeyedAcquisitionIssue] {
  guard client_infer_occurrence_matches_effect(plan.occurrence, prepared) else {
    return Err(ForeignPipeline)
  }
  if plan.keyed is Some(component) {
    let original = component.original.fragments.acquisition
    guard client_keyed_acquisition_matches_effect_program(original, prepared) else {
      return Err(ForeignPipeline)
    }
    return Ok(Some(original))
  }
  select_client_effect_model_keyed_acquisition(prepared, plan.occurrence)
}

///|
/// Select the same checked keyed occurrence before the first Model Plan. The
/// returned original is retained by that Plan; no rows, read or grant is issued.
pub fn select_client_effect_model_keyed_acquisition(
  prepared : PreparedClientEffectComputation,
  occurrence : ClientInferOccurrence,
) -> Result[ClientKeyedAcquisition?, ClientKeyedAcquisitionIssue] {
  guard client_infer_occurrence_matches_effect(occurrence, prepared) else {
    return Err(ForeignPipeline)
  }
  match client_composed_keyed_source_coordinates(occurrence.owner) {
    Err(issue) => Err(issue)
    Ok(None) => Ok(None)
    Ok(Some((stage, input, join))) => {
      if stage != occurrence.stage {
        return Ok(None)
      }
      if join >= occurrence.step {
        return Err(ForeignPipeline)
      }
      prepare_client_effect_keyed_acquisition(
        prepared,
        stage,
        input,
        1000000,
        join_step=Some(join),
      ).map(value => Some(value))
    }
  }
}

///|
// The same original checked inventory, not a Direct-only physical profile.
// Logical Source facts remain available to the saved provenance reader after
// the actual lookup has ended; they issue neither a request nor a Row owner.
fn client_composed_keyed_source_coordinates(
  owner : PreparedClientProgram,
) -> Result[(Int, Int, Int)?, ClientKeyedAcquisitionIssue] {
  let checked = @strategy.graph_program(owner.graph)
  let mut selected = None
  let count = @checked.source_execution_count(checked)
  if count > 1000000 {
    return Err(WorkLimit)
  }
  for index in 0..<count {
    let check = @checked.source_execution_at(checked, index).unwrap()
    if @checked.source_execution_kind(check) is @checked.KeyedRequest(binding) {
      if selected is Some(_) {
        return Err(ForeignPipeline)
      }
      let subject = @checked.source_execution_subject(check)
      selected = Some(
        (
          subject.stage,
          subject.input,
          @acquisition.keyed_join_step(binding.join),
        ),
      )
    }
  }
  Ok(selected)
}

///|
/// Immutable source identity for selecting an already-installed file reader
/// before the Request constructs its checked acquisition/Plan holders.
pub fn client_infer_occurrence_keyed_source_identity(
  occurrence : ClientInferOccurrence,
) -> (String, String)? {
  guard client_infer_occurrence_matches(occurrence, occurrence.owner) &&
    client_composed_keyed_source_coordinates(occurrence.owner)
    is Ok(Some((stage, input, step))) &&
    stage == occurrence.stage &&
    step < occurrence.step else {
    return None
  }
  let program = @strategy.graph_program(occurrence.owner.graph)
  for index in 0..<@checked.source_execution_count(program) {
    let original = @checked.source_execution_at(program, index).unwrap()
    let subject = @checked.source_execution_subject(original)
    if subject.stage == stage &&
      subject.input == input &&
      @checked.source_execution_kind(original) is @checked.KeyedRequest(_) {
      let policy = @environment.source_view_data_policy(
        subject.response_policy.authoritative,
      )
      return Some(
        (
          @environment.data_policy_source(policy),
          @acquisition.selected_cid(subject.source),
        ),
      )
    }
  }
  None
}

///|
fn client_keyed_left_single_source_matches(
  left : ClientKeyedLeftRead,
  source : @query.CapturedInputSource,
) -> Bool {
  left.composed is None &&
  left.source is Some(original) &&
  physical_equal(original, source)
}

///|
// The physical file locator may borrow the exact listing among the original
// prefix inputs. It still validates that listing's issued Resource/version.
fn client_keyed_left_source_matches(
  left : ClientKeyedLeftRead,
  source : @query.CapturedInputSource,
) -> Bool {
  if client_keyed_left_single_source_matches(left, source) {
    return true
  }
  left.source is None &&
  left.composed is Some(original) &&
  original.sources.any(value => physical_equal(value, source)) &&
  client_composed_keyed_original_current(original)
}

///|
pub fn borrow_client_original_composed_keyed_ledger(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  keyed : ClientKeyedAcquisition,
  sources : Array[@query.CapturedInputSource],
  captures : @row_host.RowCapturedInputs,
  prefix? : @resources.Reservation? = None,
) -> Result[@resources.Ledger, ClientModelReadPreparationIssue] {
  let owner = plan.owner
  let originals = []
  for slot in 0..<@row_host.row_captured_inputs_count(captures) {
    if @row_host.row_captured_inputs_source_original_at(captures, slot)
      is Some(original) {
      originals.push(original)
    }
  }
  let graph = if originals.is_empty() {
    Some(owner.graph)
  } else {
    @strategy.prepare_source_inputs_dag(owner.graph, originals).to_option()
  }
  guard client_model_origin_matches(scope.origin, compiled, definition, plan) &&
    client_compiled_run_matches(compiled, owner) &&
    check_client_compiled_run_definition(compiled, definition) is Ok(_) &&
    keyed.program is KeyedEffect(effect) &&
    compiled.compilation is Effects(allowed) &&
    physical_equal(allowed.compilation.owner, effect) &&
    physical_equal(keyed.owner, plan.occurrence.preparation) &&
    client_keyed_acquisition_coordinates(keyed) is Some((stage, task, join)) &&
    stage == plan.stage &&
    task == plan.task &&
    join < plan.source_ordinal &&
    graph is Some(graph) &&
    @strategy.graph_keyed_model_plan_inputs_complete(
      graph,
      task,
      plan.source_ordinal,
    ) &&
    select_client_direct_acquisition_occurrences(owner, 1000000) is Ok(direct) &&
    sources.length() == client_direct_acquisition_occurrence_count(direct) else {
    return Err(ForeignRun)
  }
  let identity = @checked.source_identity(@strategy.graph_program(owner.graph))
  for slot, source in sources {
    guard client_direct_acquisition_occurrence_at(direct, slot)
      is Some((stage, input, task)) &&
      @strategy.graph_task_owner(owner.graph, task) is Some(preparation) &&
      @query.captured_source_matches(source, identity, preparation) &&
      @row_host.row_captured_inputs_source_at(captures, slot) is Some(actual) &&
      physical_equal(source, actual) else {
      return Err(ForeignRun)
    }
    match @row_host.row_captured_inputs_source_original_at(captures, slot) {
      Some(original) =>
        if !client_source_acquisition_matches_program(
            owner, stage, input, original,
          ) ||
          !@query.captured_source_matches_input_acquisition(source, original) {
          return Err(ForeignRun)
        }
      None =>
        if task != slot ||
          @row_host.row_captured_input_requirement_at(captures, slot) is None {
          return Err(ForeignRun)
        }
    }
  }
  // Liveness can reenter. The actual census after those callbacks owns the
  // loan; no usage snapshot or successful quote can replace this witness.
  if !@resources.original_ledger_preparation_available(scope.identity) ||
    !@row_host.row_captured_inputs_borrowed_available(captures, scope.ledger) ||
    (
      prefix is Some(original) &&
      !@resources.original_borrowed_reservation_available(
        scope.identity,
        scope.ledger,
        original,
      )
    ) {
    return Err(Resource(@resources.ChangedOriginalState))
  }
  Ok(scope.ledger)
}

///|
pub fn retain_client_original_composed_keyed_captures(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  keyed : ClientKeyedAcquisition,
  rows : Array[@row_host.RowSourceCapture],
) -> Result[
  (
    @resources.Ledger,
    @row_host.RowCapturedInputs,
    Array[@query.CapturedInputSource],
  ),
  ClientModelReadPreparationIssue,
] {
  guard client_model_origin_matches(scope.origin, compiled, definition, plan) &&
    @row_host.retain_row_captured_inputs(rows, scope.ledger, 100000)
    is Some(captures) else {
    return Err(ForeignRun)
  }
  let sources = []
  for row in rows {
    match @row_host.row_capture_source(row) {
      Ok(source) => sources.push(source)
      Err(_) => return Err(ForeignRun)
    }
  }
  borrow_client_original_composed_keyed_ledger(
    scope, compiled, definition, plan, keyed, sources, captures,
  ).map(ledger => (ledger, captures, sources))
}

///|
// Actual adopted Run inputs may share their Ledger with retained preparation
// and fixed control originals. Borrow each exact Row pair, not a pristine
// whole-Ledger census. Checked Source/graph/Scope binding remains above.
pub fn borrow_client_original_composed_keyed_captures(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  keyed : ClientKeyedAcquisition,
  rows : Array[@row_host.RowSourceCapture],
) -> Result[
  (
    @resources.Ledger,
    @row_host.RowCapturedInputs,
    Array[@query.CapturedInputSource],
  ),
  ClientModelReadPreparationIssue,
] {
  guard client_model_origin_matches(scope.origin, compiled, definition, plan) &&
    @row_host.borrow_row_captured_inputs(rows, scope.ledger, 100000)
    is Some(captures) else {
    return Err(ForeignRun)
  }
  let sources = []
  for row in rows {
    match @row_host.row_capture_source(row) {
      Ok(source) => sources.push(source)
      Err(_) => return Err(ForeignRun)
    }
  }
  borrow_client_original_composed_keyed_ledger(
    scope, compiled, definition, plan, keyed, sources, captures,
  ).map(ledger => (ledger, captures, sources))
}

///|
pub fn borrow_client_original_composed_keyed_input_captures(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  keyed : ClientKeyedAcquisition,
  rows : Array[@row_host.RowCapturedInput],
  installed? : Bool = true,
) -> Result[
  (
    @resources.Ledger,
    @row_host.RowCapturedInputs,
    Array[@query.CapturedInputSource],
  ),
  ClientModelReadPreparationIssue,
] {
  guard client_model_origin_matches(scope.origin, compiled, definition, plan) else {
    return Err(ForeignRun)
  }
  let captures = if installed {
    @row_host.borrow_row_captured_input_originals(rows, scope.ledger, 100000)
  } else {
    @row_host.retain_row_captured_input_originals(rows, scope.ledger, 100000)
  }
  guard captures is Some(captures) else { return Err(ForeignRun) }
  let sources = []
  for row in rows {
    guard @row_host.row_captured_input_source(row) is Some(source) else {
      return Err(ForeignRun)
    }
    sources.push(source)
  }
  borrow_client_original_composed_keyed_ledger(
    scope, compiled, definition, plan, keyed, sources, captures,
  ).map(ledger => (ledger, captures, sources))
}

///|
fn client_composed_keyed_original_current(
  value : ClientComposedKeyedOriginal,
) -> Bool {
  client_model_origin_matches(
    value.scope.origin,
    value.compiled,
    value.definition,
    value.plan,
  ) &&
  client_composed_keyed_original_prefix_available(value) &&
  client_composed_keyed_original_output(value) is Some(_) &&
  value.host
  .map(host => {
    client_composed_keyed_host_inputs_match(
      host,
      value.plan,
      value.scope.ledger,
      value.sources,
      value.host_sources,
      value.inputs,
    )
  })
  .unwrap_or(true) &&
  value.sources.all(@query.captured_source_available) &&
  (match value.producers {
    NoProducers => true
    ProducerSlots(producers, _) =>
      producers.all(producer => {
        client_composed_keyed_producer_output(
          producer,
          value.scope,
          value.compiled,
          value.definition,
          value.plan,
          value.keyed,
          value.sources,
        )
        is Some(_)
      })
  }) &&
  @row_host.row_captured_inputs_borrowed_available(
    value.captures,
    value.scope.ledger,
  ) &&
  @resources.original_ledger_inventory_available(value.scope.identity)
}

///|
fn client_keyed_left_available(left : ClientKeyedLeftRead) -> Bool {
  @execution.producer_read_available(left.read) &&
  (match (left.source, left.composed) {
    (Some(_), None) => true
    (None, Some(original)) => client_composed_keyed_original_current(original)
    _ => false
  })
}

///|
/// Assemble the SAME completed composed prefix on its retained Model Scope.
/// The original left already owns this private tuple. No caller Ledger,
/// copied Scope, reconstructed binding or new admission can replace it.
pub fn start_client_original_composed_keyed_lookup_input(
  left : ClientKeyedLeftRead,
  max_bytes : Int,
  max_work : Int,
) -> Result[ClientKeyedLookupInput, ClientKeyedRequestIssue] {
  guard left.source is None &&
    left.composed is Some(original) &&
    physical_equal(left.acquisition, original.keyed) &&
    client_composed_keyed_original_current(original) else {
    return Err(ForeignLeft)
  }
  // The legacy optional entrance authenticates exactly ONE captured child.
  // This composed left already authenticates its ordered MULTIPLE Sources,
  // completed producers and same recorded prefix above. Reusing the single-
  // child shape would refuse this genuine two-Source inventory. Keep that
  // other entrance unchanged; the existing allocator still debits this exact
  // retained Scope Ledger and preserves every consumed attempt on failure.
  start_client_keyed_lookup_input_owned(
    left,
    original.scope.ledger,
    max_bytes,
    max_work,
    None,
  )
}

///|
pub fn client_composed_keyed_lookup_matches_model_parent(
  lookup : ClientKeyedLookupInput,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  ledger : @resources.Ledger,
) -> Bool {
  lookup.left.source is None &&
  lookup.left.composed is Some(original) &&
  physical_equal(original.compiled, compiled) &&
  physical_equal(original.definition, definition) &&
  physical_equal(original.plan, plan) &&
  physical_equal(lookup.ledger, ledger) &&
  physical_equal(original.scope.ledger, ledger) &&
  physical_equal(original.keyed, lookup.left.acquisition) &&
  !lookup.closed &&
  client_composed_keyed_original_current(original)
}

///|
pub fn client_composed_keyed_request_matches_model_parent(
  request : ClientKeyedRequest,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  ledger : @resources.Ledger,
) -> Bool {
  client_keyed_request_matches_acquisition(request, request.left.acquisition) &&
  request.assembly_accounting is Some(lookup) &&
  physical_equal(request.left, lookup.left) &&
  lookup.selected_request is Some(selected) &&
  physical_equal(selected, request) &&
  lookup.selected_index == Some(-1) &&
  request.row == keyed_lookup_next_original_row(lookup) &&
  request.attempts == 0L &&
  !request.io_complete &&
  lookup.completed is None &&
  lookup.copying is None &&
  lookup.preparation is None &&
  client_composed_keyed_lookup_matches_model_parent(
    lookup, compiled, definition, plan, ledger,
  ) &&
  lookup.left.composed is Some(original) &&
  @row_host.row_captured_inputs_borrowed_available(original.captures, ledger) &&
  client_composed_keyed_original_prefix_available(original) &&
  @resources.original_borrowed_reservation_available(
    original.scope.identity,
    ledger,
    lookup.reservation,
  )
}

///|
// An already-entered child retains this SAME assembly/left/Scope identity
// after its selected slot advances or its IO attempt is observed. This does
// not authorize another request or another physical attempt.
pub fn client_composed_keyed_request_retained_model_parent(
  request : ClientKeyedRequest,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  ledger : @resources.Ledger,
) -> Bool {
  client_keyed_request_matches_acquisition(request, request.left.acquisition) &&
  request.assembly_accounting is Some(lookup) &&
  physical_equal(request.left, lookup.left) &&
  client_composed_keyed_lookup_matches_model_parent(
    lookup, compiled, definition, plan, ledger,
  )
}

///|
// Actual completed-left length, not a checked estimate or the later Model
// output count. Repeated keys use existing rows without allocating a second
// physical child; one row can select at most its one original request slot.
pub fn client_composed_keyed_request_model_rows(
  request : ClientKeyedRequest,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  ledger : @resources.Ledger,
) -> Int? {
  guard client_composed_keyed_request_retained_model_parent(
    request, compiled, definition, plan, ledger,
  ) else {
    return None
  }
  let rows = @execution.producer_read_row_count(request.left.read)
  guard request.row >= 0 &&
    request.row < rows &&
    client_composed_keyed_request_retained_model_parent(
      request, compiled, definition, plan, ledger,
    ) else {
    return None
  }
  Some(rows)
}

///|
pub fn client_composed_keyed_lookup_sources_match(
  lookup : ClientKeyedLookupInput,
  occurrence : ClientInferOccurrence,
  sources : Array[@query.CapturedInputSource],
) -> Bool {
  guard lookup.left.source is None &&
    lookup.left.composed is Some(original) &&
    physical_equal(original.keyed, lookup.left.acquisition) &&
    physical_equal(lookup.ledger, original.scope.ledger) &&
    client_infer_occurrence_matches_plan(occurrence, original.plan) &&
    sources.length() == original.sources.length() &&
    client_composed_keyed_original_current(original) else {
    return false
  }
  for index, source in sources {
    if !physical_equal(source, original.sources[index]) {
      return false
    }
  }
  true
}

///|
// Same-package Source closure borrows a Root only through the lookup that
// consumed that exact provider result. A matching Source observation alone
// cannot discharge its pending enclosing Stage.
fn client_composed_keyed_lookup_has_source_producer(
  lookup : ClientKeyedLookupInput,
  occurrence : ClientInferOccurrence,
  sources : Array[@query.CapturedInputSource],
  slot : Int,
) -> Bool {
  // Immutable correspondence here; the admission's final keyed boundary below
  // the Source callbacks checks the whole live lookup once. Do not repeat that
  // callbackful whole-inventory check for every source in this same walk.
  guard lookup.left.composed is Some(original) &&
    client_infer_occurrence_matches_plan(occurrence, original.plan) &&
    sources.length() == original.sources.length() else {
    return false
  }
  if original.host is Some(host) {
    guard sources.get(slot) is Some(source) &&
      original.sources.get(slot) is Some(actual) &&
      physical_equal(source, actual) &&
      select_client_direct_acquisition_occurrences(original.plan.owner, 1000000)
      is Ok(direct) &&
      client_direct_acquisition_occurrence_at(direct, slot)
      is Some((_, _, task)) else {
      return false
    }
    // This is the already-committed original Source Unit in the same Host,
    // not a new completed producer manufactured from its earlier raw capture.
    return @strategy.captured_task_completed(
      @strategy.captured_effect_run_dag(host),
      task,
    )
  }
  // The enclosing admission checks the complete vector after all callbacks.
  // This iteration binds only its exact original slot, never another Source.
  guard sources.get(slot) is Some(source) &&
    original.sources.get(slot) is Some(actual) &&
    physical_equal(source, actual) &&
    client_composed_keyed_indexed_producer(original.producers, slot)
    is Some(producer) else {
    return false
  }
  client_composed_keyed_producer_output(
    producer,
    original.scope,
    original.compiled,
    original.definition,
    original.plan,
    original.keyed,
    sources,
  )
  is Some(_)
}

///|
pub fn client_composed_keyed_lookup_sources(
  lookup : ClientKeyedLookupInput,
  occurrence : ClientInferOccurrence,
) -> Array[@query.CapturedInputSource]? {
  guard lookup.left.composed is Some(original) &&
    client_composed_keyed_lookup_sources_match(
      lookup,
      occurrence,
      original.sources,
    ) &&
    client_keyed_lookup_input_identity(lookup) is Some(_) else {
    return None
  }
  Some(original.sources.copy())
}

///|
/// Match the actual producer retained by this keyed lookup, not the raw
/// acquisition before its checked filter/projection. Equal rows, target or
/// logical identity cannot replace the original completed occurrence.
pub fn client_composed_keyed_lookup_source_read_matches(
  lookup : ClientKeyedLookupInput,
  occurrence : ClientInferOccurrence,
  slot : Int,
  read : @execution.ProducerRead,
) -> Bool {
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.left.composed is Some(original) &&
    client_infer_occurrence_matches_plan(occurrence, original.plan) &&
    original.sources.get(slot) is Some(source) else {
    return false
  }
  let matched = match
    client_composed_keyed_indexed_producer(original.producers, slot) {
    None => @query.captured_source_matches_segment_input(source, read)
    Some(producer) =>
      client_composed_keyed_producer_output(
        producer,
        original.scope,
        original.compiled,
        original.definition,
        original.plan,
        original.keyed,
        original.sources,
      )
      .map(output => {
        @execution.producer_read_matches_completed_output(read, output)
      })
      .unwrap_or(false)
  }
  // The enclosing ordered-vector entry already checked the complete lookup;
  // its existing join receiver checks current again after these read callbacks.
  // Do not repeat the whole Source/producer inventory for every input port.
  matched
}

///|
/// Match a supplied Whole Source port to the SAME retained capture. A Source
/// that already executed a checked producer must still supply that producer's
/// Result through the existing RelationRead path, never its earlier raw input.
pub fn client_composed_keyed_lookup_source_supplied_read_matches(
  lookup : ClientKeyedLookupInput,
  occurrence : ClientInferOccurrence,
  slot : Int,
  read : @execution.SuppliedRelationRead,
) -> Bool {
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.left.composed is Some(original) &&
    client_infer_occurrence_matches_plan(occurrence, original.plan) &&
    original.sources.get(slot) is Some(source) &&
    client_composed_keyed_indexed_producer(original.producers, slot) is None &&
    @query.captured_source_original_input_read(source) is Some(expected) &&
    @execution.supplied_relation_read_same_binding(read, expected) &&
    @execution.supplied_relation_read_available(read) else {
    return false
  }
  // The original Source/read current callbacks can reenter cleanup. They
  // cannot leave this returned port usable after retiring the lookup owner.
  !lookup.closed && lookup.left.lookup_issue is None
}

///|
/// Borrow the SAME completed root proofs for the existing checked DAG. The
/// prefix remains their execution/reservation/cleanup owner; this does not
/// issue a completion, replay a Source or grant a consumer port.
pub fn client_composed_keyed_lookup_source_results(
  lookup : ClientKeyedLookupInput,
  occurrence : ClientInferOccurrence,
) -> Array[
  (
    Int,
    @execution.GeneratedSequence,
    Array[(Int, Int, @execution.ProducerRead)],
    @execution.CompletedSegmentInputs,
  ),
]? {
  guard !lookup.closed &&
    lookup.left.composed is Some(original) &&
    client_composed_keyed_lookup_sources_match(
      lookup,
      occurrence,
      original.sources,
    ) else {
    return None
  }
  let results : Array[
    (
      Int,
      @execution.GeneratedSequence,
      Array[(Int, Int, @execution.ProducerRead)],
      @execution.CompletedSegmentInputs,
    ),
  ] = []
  match original.producers {
    NoProducers => ()
    ProducerSlots(producers, _) =>
      for producer in producers {
        guard client_composed_keyed_producer_output(
            producer,
            original.scope,
            original.compiled,
            original.definition,
            original.plan,
            original.keyed,
            original.sources,
          )
          is Some(_) else {
          return None
        }
        results.push(
          (
            producer.task,
            producer.sequence,
            producer.inputs.copy(),
            producer.completed,
          ),
        )
      }
  }
  if !client_composed_keyed_original_current(original) {
    return None
  }
  Some(results)
}

///|
pub fn client_composed_keyed_lookup_input_slot(
  lookup : ClientKeyedLookupInput,
  occurrence : ClientInferOccurrence,
) -> Int? {
  guard lookup.left.composed is Some(original) &&
    client_composed_keyed_lookup_sources_match(
      lookup,
      occurrence,
      original.sources,
    ) else {
    return None
  }
  let subject = @checked.source_execution_subject(original.keyed.check)
  let pipeline = @lower.pipeline(@lower.bound_preparation(original.keyed.owner))
  match
    @pipeline.lookup(
      pipeline,
      @acquisition.declaration(subject.source).input_name,
    ) {
    Some(@pipeline.Input(index)) => Some(index)
    _ => None
  }
}

///|
pub fn client_composed_keyed_lookup_prefix_work(
  lookup : ClientKeyedLookupInput,
  occurrence : ClientInferOccurrence,
) -> Int64? {
  guard lookup.left.composed is Some(original) &&
    client_composed_keyed_lookup_sources_match(
      lookup,
      occurrence,
      original.sources,
    ) else {
    return None
  }
  Some(original.prefix_work)
}

///|
// Bind the actual external prefix ports in operation order. The graph, not
// source names or caller coordinates, selects each original captured producer.
pub fn prepare_client_original_composed_keyed_inputs(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  keyed : ClientKeyedAcquisition,
  sources : Array[@query.CapturedInputSource],
  captures : @row_host.RowCapturedInputs,
  sequence : @execution.GeneratedSequence,
  max_entries : Int,
  max_name_bytes : Int,
  producers? : Array[ClientComposedKeyedProducer] = [],
) -> Result[Array[(Int, Int, @execution.ProducerRead)], ClientKeyedRequestIssue] {
  guard borrow_client_original_composed_keyed_ledger(
      scope, compiled, definition, plan, keyed, sources, captures,
    )
    is Ok(_) &&
    physical_equal(@execution.generated_sequence_owner(sequence), keyed.owner) else {
    return Err(ForeignLeft)
  }
  let graph = plan.owner.graph
  guard client_composed_keyed_index_producers(
      producers,
      sources.length(),
      @strategy.graph_task_count(graph),
    )
    is Some(producer_index) else {
    return Err(ForeignLeft)
  }
  let inputs : Array[(Int, Int, @execution.ProducerRead)] = []
  let used : Array[Int] = []
  for position in 0..<@execution.generated_sequence_step_count(sequence) {
    let step = @execution.generated_sequence_step_index_at(sequence, position).unwrap()
    let node = @lower.node_at(@lower.bound_preparation(keyed.owner), step).unwrap()
    for port in 0..<@lower.node_input_count(node) {
      let target = @lower.node_input_target(node, port).unwrap()
      if target is @pipeline.Step(previous) && previous < step {
        continue
      }
      let mut selected = None
      for index in 0..<@strategy.graph_data_count(graph) {
        let edge = @strategy.graph_data_at(graph, index).unwrap()
        if @strategy.data_edge_consumer(edge) != plan.task {
          continue
        }
        let source_input = @strategy.data_edge_input(edge)
        if target == @pipeline.Input(source_input) {
          if selected is Some(_) {
            return Err(ForeignLeft)
          }
          selected = Some(@strategy.data_edge_producer(edge))
        }
      }
      if target is @pipeline.Input(index) {
        for slot in 0..<sources.length() {
          if @row_host.row_captured_inputs_source_original_at(captures, slot)
            is Some(original) &&
            @acquisition.source_acquisition_input(original) ==
            @pipeline.Input(index) &&
            physical_equal(
              @acquisition.source_acquisition_pipeline(original),
              @lower.pipeline(@lower.bound_preparation(keyed.owner)),
            ) {
            if selected is Some(_) {
              return Err(ForeignLeft)
            }
            selected = Some(slot)
          }
        }
      }
      guard selected is Some(task) &&
        !used.contains(task) &&
        task < sources.length() else {
        return Err(ForeignLeft)
      }
      let whole = @row_host.row_captured_inputs_source_original_at(
          captures, task,
        )
        is Some(_)
      if !whole && task != inputs.length() {
        return Err(ForeignLeft)
      }
      let bound = match
        (if whole &&
          client_composed_keyed_indexed_producer(producer_index, task)
          is Some(selected) {
          guard client_composed_keyed_producer_output(
              selected, scope, compiled, definition, plan, keyed, sources,
            )
            is Some(output) else {
            return Err(ForeignLeft)
          }
          match target {
            @pipeline.Input(index) =>
              @execution.bind_completed_input(
                keyed.owner,
                index,
                @execution.generated_sequence_owner(selected.sequence),
                output,
              ).map_err(issue => @query.CapturedSourceIssue::Binding(issue))
            _ => return Err(ForeignLeft)
          }
        } else if whole {
          @query.bind_captured_source_operation(
            sources[task],
            keyed.owner,
            step,
            port,
          )
        } else {
          match target {
            @pipeline.Input(index) =>
              @query.bind_captured_source(sources[task], keyed.owner, index)
            _ =>
              @query.bind_captured_source_operation(
                sources[task],
                keyed.owner,
                step,
                port,
              )
          }
        }) {
        Ok(value) => value
        Err(issue) => return Err(Capture(issue))
      }
      let read = match
        @execution.prepare_producer_read(
          keyed.owner,
          bound,
          max_entries,
          max_name_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Read(issue))
      }
      inputs.push((step, port, read))
      used.push(task)
    }
  }
  guard inputs.length() == sources.length() &&
    borrow_client_original_composed_keyed_ledger(
      scope, compiled, definition, plan, keyed, sources, captures,
    )
    is Ok(_) else {
    return Err(ForeignLeft)
  }
  Ok(inputs)
}

///|
// Called only with the existing Local prefix's actual output and the exact
// reads retained by that execution. A copied row set or equal Program cannot
// substitute for its original completed segment receipt.
pub fn prepare_client_original_composed_keyed_left(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  keyed : ClientKeyedAcquisition,
  sources : Array[@query.CapturedInputSource],
  captures : @row_host.RowCapturedInputs,
  sequence : @execution.GeneratedSequence,
  inputs : Array[(Int, Int, @execution.ProducerRead)],
  output : @execution.CompletedOutput,
  prefix : @resources.Reservation,
  prefix_work : Int64,
  max_entries : Int,
  max_name_bytes : Int,
  producers? : Array[ClientComposedKeyedProducer] = [],
  host? : @strategy.CapturedEffectRunDAG? = None,
  host_sources? : Array[@acquisition.SourceAcquisition] = [],
) -> Result[ClientKeyedLeftRead, ClientKeyedRequestIssue] {
  let _ = match
    borrow_client_original_composed_keyed_ledger(
      scope,
      compiled,
      definition,
      plan,
      keyed,
      sources,
      captures,
      prefix=Some(prefix),
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignLeft)
  }
  guard prefix_work >= 0L &&
    (if host is Some(original) {
      client_composed_keyed_host_inputs_match(
        original,
        plan,
        scope.ledger,
        sources,
        host_sources,
        inputs,
      )
    } else {
      inputs.length() == sources.length()
    }) &&
    physical_equal(@execution.generated_sequence_owner(sequence), keyed.owner) &&
    @execution.retain_completed_segment_inputs(
      output, sequence, inputs, max_entries,
    )
    is Some(completed) else {
    return Err(ForeignLeft)
  }
  guard client_composed_keyed_index_producers(
      producers,
      sources.length(),
      @strategy.graph_task_count(plan.owner.graph),
    )
    is Some(producer_index) else {
    return Err(ForeignLeft)
  }
  for (_, _, read) in (if host is None { inputs } else { [] }) {
    let mut matches = 0
    for slot, source in sources {
      let selected = client_composed_keyed_indexed_producer(
        producer_index, slot,
      )
      let matched = match selected {
        None => @query.captured_source_matches_segment_input(source, read)
        Some(producer) =>
          client_composed_keyed_producer_output(
            producer, scope, compiled, definition, plan, keyed, sources,
          )
          is Some(output) &&
          @execution.producer_read_matches_completed_output(read, output)
      }
      if matched {
        matches += 1
      }
    }
    if matches != 1 {
      return Err(ForeignLeft)
    }
  }
  let bound = match
    @execution.bind_completed_operation_input(
      keyed.owner,
      @acquisition.keyed_join_step(keyed.binding.join),
      0,
      keyed.owner,
      output,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignLeft)
  }
  let read = match
    @execution.prepare_producer_read(
      keyed.owner,
      bound,
      max_entries,
      max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Read(issue))
  }
  let original = {
    scope,
    compiled,
    definition,
    plan,
    keyed,
    sources: sources.copy(),
    captures,
    sequence,
    inputs: inputs.copy(),
    completed: Some(completed),
    direct_output: None,
    prefix: Some(prefix),
    prefix_work,
    producers: producer_index,
    host,
    host_sources,
  }
  guard client_composed_keyed_original_current(original) &&
    borrow_client_original_composed_keyed_ledger(
      scope,
      compiled,
      definition,
      plan,
      keyed,
      sources,
      captures,
      prefix=Some(prefix),
    )
    is Ok(_) else {
    return Err(ForeignLeft)
  }
  Ok({
    acquisition: keyed,
    source: None,
    composed: Some(original),
    read,
    requests: 0L,
    attempts: 0L,
    request_bytes: 0L,
    response_bytes: 0L,
    decoded_bytes: 0L,
    started_ms: None,
    observed_ms: 0L,
    lookup_issue: None,
    assembly_started: false,
  })
}

///|
/// Match only the actual predecessor reads of this original Effect DAG. The
/// complete direct Source inventory remains independently retained; one joined
/// Result input is not recast as one of those raw Source observations.
pub fn client_composed_keyed_host_inputs_match(
  host : @strategy.CapturedEffectRunDAG,
  plan : ClientInferPlanGraph,
  ledger : @resources.Ledger,
  sources : Array[@query.CapturedInputSource],
  originals : Array[@acquisition.SourceAcquisition],
  inputs : Array[(Int, Int, @execution.ProducerRead)],
) -> Bool {
  let run = @strategy.captured_effect_run_dag(host)
  guard @strategy.captured_effect_run_matches_preparation(
      host,
      run,
      plan.owner.graph,
    ) &&
    physical_equal(@strategy.captured_dag_ledger(run), ledger) &&
    !inputs.is_empty() &&
    select_client_direct_acquisition_occurrences(plan.owner, 1000000)
    is Ok(direct) &&
    client_direct_acquisition_occurrence_count(direct) == sources.length() &&
    originals.length() == sources.length() else {
    return false
  }
  for slot, source in sources {
    guard client_direct_acquisition_occurrence_at(direct, slot)
      is Some((stage, input, task)) &&
      originals.get(slot) is Some(original) &&
      client_source_acquisition_matches_program(
        plan.owner,
        stage,
        input,
        original,
      ) &&
      @query.captured_source_matches_input_acquisition(source, original) &&
      @query.captured_source_original_input_read(source) is Some(read) &&
      @strategy.source_input_dag_retains_completed_read_at(run, read, task) else {
      return false
    }
  }
  inputs.all(input => {
    @strategy.captured_effect_keyed_prefix_input_matches(
      host,
      plan.task,
      input.0,
      input.1,
      input.2,
    )
  })
}

///|
/// Only the exact DAG that supplied the prefix's original completed reads can
/// consume this lookup. Equal compilation, rows or Source CIDs are insufficient.
pub fn client_composed_keyed_lookup_matches_host(
  lookup : ClientKeyedLookupInput,
  host : @strategy.CapturedEffectRunDAG,
) -> Bool {
  lookup.left.composed
  .map(original => {
    original.host.map(actual => physical_equal(actual, host)).unwrap_or(false) &&
    client_composed_keyed_original_current(original)
  })
  .unwrap_or(false)
}

///|
fn client_composed_keyed_original_prefix_available(
  original : ClientComposedKeyedOriginal,
) -> Bool {
  match original.prefix {
    Some(prefix) =>
      @resources.original_borrowed_reservation_available(
        original.scope.identity,
        original.scope.ledger,
        prefix,
      )
    None =>
      original.host is Some(_) &&
      original.direct_output is Some(_) &&
      original.completed is None &&
      @resources.original_ledger_inventory_available(original.scope.identity)
  }
}

///|
// A real completed prefix and a directly borrowed imported Result are distinct
// original proofs. The direct branch claims no sequence execution or work.
fn client_composed_keyed_original_output(
  original : ClientComposedKeyedOriginal,
) -> @execution.CompletedOutput? {
  match (original.completed, original.direct_output) {
    (Some(completed), None) =>
      @execution.completed_segment_inputs_output(
        completed,
        original.sequence,
        original.inputs,
      )
    (None, Some(output)) => {
      guard original.host is Some(host) &&
        original.inputs.length() == 1 &&
        client_composed_keyed_host_inputs_match(
          host,
          original.plan,
          original.scope.ledger,
          original.sources,
          original.host_sources,
          original.inputs,
        ) &&
        @execution.producer_read_matches_completed_output(
          original.inputs[0].2,
          output,
        ) else {
        return None
      }
      Some(output)
    }
    _ => None
  }
}

///|
/// A first keyed JOIN can consume the original imported Result directly. Its
/// input is already a completed producer; no empty prefix, synthetic Step,
/// provider execution, reservation or replacement output is constructed.
pub fn prepare_client_original_composed_keyed_host_input_left(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  keyed : ClientKeyedAcquisition,
  rows : Array[@row_host.RowCapturedInput],
  host : @strategy.CapturedEffectRunDAG,
  sequence : @execution.GeneratedSequence,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[ClientKeyedLeftRead?, ClientKeyedRequestIssue] {
  guard client_keyed_acquisition_coordinates(keyed) is Some((_, task, join)) &&
    task == plan.task &&
    physical_equal(@execution.generated_sequence_owner(sequence), keyed.owner) &&
    @lower.node_at(@lower.bound_preparation(keyed.owner), join) is Some(node) else {
    return Err(ForeignLeft)
  }
  let input = match @lower.node_input_target(node, 0) {
    Some(@pipeline.Step(_)) => return Ok(None)
    Some(@pipeline.Input(input)) => input
    _ => return Err(ForeignLeft)
  }
  let (ledger, captures, sources) = match
    borrow_client_original_composed_keyed_input_captures(
      scope,
      compiled,
      definition,
      plan,
      keyed,
      rows,
      installed=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignLeft)
  }
  let run = @strategy.captured_effect_run_dag(host)
  let read = match
    @strategy.captured_task_input(
      run,
      task,
      max_entries,
      max_name_bytes,
      input_index=input,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignLeft)
  }
  let originals = sources
    .mapi((slot, _) => {
      @row_host.row_captured_inputs_source_original_at(captures, slot)
    })
    .filter_map(value => value)
  let inputs = [(join, 0, read)]
  guard client_composed_keyed_host_inputs_match(
    host, plan, ledger, sources, originals, inputs,
  ) else {
    return Err(ForeignLeft)
  }
  let graph = @strategy.captured_dag_graph(run)
  let mut output = @strategy.captured_pending_task_input_output(
    run, task, input,
  )
  let mut matched = false
  for index in 0..<@strategy.graph_data_count(graph) {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    if @strategy.data_edge_consumer(edge) == task &&
      @strategy.data_edge_input(edge) == input {
      if matched {
        return Err(ForeignLeft)
      }
      matched = true
      if output is Some(_) {
        continue
      }
      output = @strategy.captured_task_output(
        run,
        @strategy.data_edge_producer(edge),
        @strategy.data_edge_target(edge),
      )
    }
  }
  guard output is Some(output) &&
    @execution.producer_read_matches_completed_output(read, output) else {
    return Err(ForeignLeft)
  }
  let original : ClientComposedKeyedOriginal = {
    scope,
    compiled,
    definition,
    plan,
    keyed,
    sources,
    captures,
    // Only contracts/physical owner are borrowed from this original sequence.
    // completed=None records that it did not execute to produce this input.
    sequence,
    inputs,
    completed: None,
    direct_output: Some(output),
    prefix: None,
    prefix_work: 0L,
    producers: NoProducers,
    host: Some(host),
    host_sources: originals,
  }
  guard client_composed_keyed_original_current(original) else {
    return Err(ForeignLeft)
  }
  Ok(
    Some({
      acquisition: keyed,
      source: None,
      composed: Some(original),
      read,
      requests: 0L,
      attempts: 0L,
      request_bytes: 0L,
      response_bytes: 0L,
      decoded_bytes: 0L,
      started_ms: None,
      observed_ms: 0L,
      lookup_issue: None,
      assembly_started: false,
    }),
  )
}
