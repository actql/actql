///|
// Checked shape DATA, not a pin, execution capability or new physical owner.
// The caller funds the actual Unit depth vector before census, then funds the
// returned counts/names before materializing requests or acquiring any pins.
struct CapturedEffectDependencyPortCensus {
  run : CapturedEffectRunDAG
  depths : Array[Int]
  remaining : Int
  results : Int
  members : Int
  tables : Int
  name_units : Int64
}

///|
pub fn captured_effect_dependency_unit_count(run : CapturedEffectRunDAG) -> Int {
  @checked.unit_count(run.checked.computation.graph_value().program_value())
}

///|
pub fn census_captured_effect_dependency_ports(
  run : CapturedEffectRunDAG,
  max_work : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> Result[CapturedEffectDependencyPortCensus, RunIssue] {
  if run.captured.stopped {
    return Err(ForeignCandidate)
  }
  let value = run.checked.computation
  let (depths, remaining) = match
    effect_dependency_depth_inventory(value, max_work, max_depth, Some(work)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let graph = value.graph_value()
  let program = graph.program_value()
  let incoming = @context.incoming_links_requirements(
    @context.program_incoming_gates_owner(@checked.incoming_gates(program)),
  )
  let wiring = @context.program_incoming_wiring(incoming)
  let mut results = 0
  let mut names = 0L
  for stage in 0..<depths.length() {
    if !work(1) {
      return Err(PreviewWorkLimit)
    }
    if depths[stage] < 0 {
      continue
    }
    guard @results.wiring_stage_at(wiring, stage) is Some(ports) else {
      return Err(ForeignCandidate)
    }
    let publications = @results.stage_port_publications(ports)
    let count = @ports.port_count(publications)
    if count > remaining - results {
      return Err(PreviewWorkLimit)
    }
    for index in 0..<count {
      if !work(1) {
        return Err(PreviewWorkLimit)
      }
      let port = @ports.port_at(publications, index).unwrap()
      names += @ports.name(@ports.port_result(port)).length().to_int64()
    }
    results += count
  }
  let members = captured_effect_run_source_count(run)
  let mut tables = 0
  for index in 0..<members {
    if !work(1) {
      return Err(PreviewWorkLimit)
    }
    if captured_effect_run_source_at(run, index) is Some(source) {
      names += @execution.managed_result_occurrence_name(source.occurrence)
        .length()
        .to_int64()
    }
  }
  for source in value.table_sources_iter() {
    if !work(1) {
      return Err(PreviewWorkLimit)
    }
    if source is Some(_) {
      tables += 1
    }
  }
  if results > 2147483647 - members || tables > 2147483647 - results - members {
    return Err(PreviewWorkLimit)
  }
  Ok({ run, depths, remaining, results, members, tables, name_units: names, })
}

///|
pub fn captured_effect_dependency_port_census_geometry(
  value : CapturedEffectDependencyPortCensus,
) -> (Int, Int, Int, Int, Int64) {
  (
    value.depths.length(),
    value.results,
    value.members,
    value.tables,
    value.name_units,
  )
}

///|
// All array/map/key and borrow/control construction has already been funded
// on the SAME original Run. Each original Result/Source/Table occurrence and
// pin is still acquired independently by the unchanged atomic pin helper.
// No physical owner is deduplicated by DATA identity.
pub fn pin_censused_captured_effect_sources(
  value : CapturedEffectDependencyPortCensus,
  configured_max_pins : Int?,
) -> Result[CapturedEffectInputs, RunIssue] {
  if value.run.captured.stopped {
    return Err(ForeignCandidate)
  }
  let actual = value.results + value.members + value.tables
  let selected = match configured_max_pins {
    Some(limit) if limit >= 0 => Int::min(limit, actual)
    Some(_) => return Err(PreviewWorkLimit)
    None => actual
  }
  let ports = match
    materialize_effect_dependency_ports(
      value.run.checked.computation,
      value.depths,
      selected,
      value.remaining,
    ) {
    Ok(ports) => ports
    Err(issue) => return Err(issue)
  }
  if ports.length() != value.results {
    return Err(ForeignCandidate)
  }
  pin_captured_effect_sources_with_ports(value.run, selected, ports)
}
