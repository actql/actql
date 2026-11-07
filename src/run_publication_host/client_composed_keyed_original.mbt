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
  completed : @execution.CompletedSegmentInputs
  prefix : @resources.Reservation
  prefix_work : Int64
}

///|
pub fn select_client_effect_composed_model_keyed_acquisition(
  prepared : PreparedClientEffectComputation,
  plan : ClientInferPlanGraph,
) -> Result[ClientKeyedAcquisition?, ClientKeyedAcquisitionIssue] {
  guard client_infer_occurrence_matches_effect(plan.occurrence, prepared) else {
    return Err(ForeignPipeline)
  }
  match client_composed_keyed_source_coordinates(plan.owner) {
    Err(issue) => Err(issue)
    Ok(None) => Ok(None)
    Ok(Some((stage, input, join))) => {
      if stage != plan.stage {
        return Ok(None)
      }
      if join >= plan.source_ordinal {
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
    sources.length() == client_direct_acquisition_occurrence_count(direct) &&
    sources.length() == 2 else {
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
    rows.length() == 2 &&
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
    rows.length() == 2 &&
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
  guard client_model_origin_matches(scope.origin, compiled, definition, plan) &&
    rows.length() == 2 else {
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
  @resources.original_borrowed_reservation_available(
    value.scope.identity,
    value.scope.ledger,
    value.prefix,
  ) &&
  @execution.completed_segment_inputs_output(
    value.completed,
    value.sequence,
    value.inputs,
  )
  is Some(_) &&
  value.sources.all(@query.captured_source_available) &&
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
  request.row == lookup.accepted &&
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
  @resources.original_borrowed_reservation_available(
    original.scope.identity,
    ledger,
    original.prefix,
  ) &&
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
) -> Result[Array[(Int, Int, @execution.ProducerRead)], ClientKeyedRequestIssue] {
  guard borrow_client_original_composed_keyed_ledger(
      scope, compiled, definition, plan, keyed, sources, captures,
    )
    is Ok(_) &&
    physical_equal(@execution.generated_sequence_owner(sequence), keyed.owner) else {
    return Err(ForeignLeft)
  }
  let graph = plan.owner.graph
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
        (if whole {
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
    inputs.length() == sources.length() &&
    physical_equal(@execution.generated_sequence_owner(sequence), keyed.owner) &&
    @execution.retain_completed_segment_inputs(
      output, sequence, inputs, max_entries,
    )
    is Some(completed) else {
    return Err(ForeignLeft)
  }
  for (_, _, read) in inputs {
    if sources
      .filter(source => {
        @query.captured_source_matches_segment_input(source, read)
      })
      .length() !=
      1 {
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
    completed,
    prefix,
    prefix_work,
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
