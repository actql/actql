///|
/// Exact completed input custody, not a caller-provided dependency identity.
/// The graph's commit path has checked actual inputs against these ports.
struct CapturedEffectResultImport {
  inputs : CapturedEffectInputs
  consumer : Int
  interface : @checked.BuiltResultInterface
  producer : CapturedEffectLocalResult
}

///|
pub fn capture_effect_result_import(
  inputs : CapturedEffectInputs,
  consumer : Int,
  index : Int,
  max_work : Int,
) -> Result[CapturedEffectResultImport, RunIssue] {
  if !inputs.live || inputs.run.captured.stopped {
    return Err(Stopped)
  }
  let run = inputs.run.captured
  let graph = run.graph
  guard graph.stage_tasks.get(consumer) is Some(tasks) &&
    @checked.unit_result_import_at(graph.program, consumer, index)
    is Some(interface) else {
    return Err(ForeignCandidate)
  }
  if max_work < tasks.length() + inputs.local_results.length() {
    return Err(PreviewWorkLimit)
  }
  // Completion is recorded only after the actual request/output input checks.
  // Inspecting the static graph alone is insufficient evidence of a read.
  for task in tasks {
    if !task_done(run, task) {
      return Err(NotReady)
    }
  }
  let site = @context.result_import_type_site(interface.row)
  guard site.stage == consumer &&
    site.requirement is @context.Result(name, predecessor, _) &&
    name == interface.input_name else {
    return Err(ForeignCandidate)
  }
  let identity = @checked.source_identity(graph.program)
  for producer in inputs.local_results {
    if producer.stage >= consumer {
      continue
    }
    guard @context.program_identity_stage_at(identity, producer.stage)
      is Some(owner) else {
      return Err(ForeignCandidate)
    }
    if physical_equal(owner, predecessor) &&
      @execution.managed_result_occurrence_name(
        captured_any_result_borrow_occurrence(producer.borrow),
      ) ==
      interface.result_name {
      if !captured_any_result_borrow_available(producer.borrow) {
        return Err(NotReady)
      }
      return Ok({ inputs, consumer, interface, producer, })
    }
  }
  Err(MissingOutput)
}

///|
pub fn captured_effect_result_import_interface(
  value : CapturedEffectResultImport,
) -> @checked.BuiltResultInterface {
  value.interface
}

///|
pub fn captured_effect_result_import_consumer(
  value : CapturedEffectResultImport,
) -> Int {
  value.consumer
}

///|
pub fn captured_effect_result_import_producer(
  value : CapturedEffectResultImport,
) -> CapturedEffectLocalResult {
  value.producer
}

///|
pub fn captured_effect_result_import_matches(
  value : CapturedEffectResultImport,
  inputs : CapturedEffectInputs,
  consumer : Int,
  producer : CapturedEffectLocalResult,
) -> Bool {
  physical_equal(value.inputs, inputs) &&
  inputs.live &&
  !inputs.run.captured.stopped &&
  value.consumer == consumer &&
  physical_equal(value.producer, producer) &&
  captured_any_result_borrow_available(value.producer.borrow)
}
