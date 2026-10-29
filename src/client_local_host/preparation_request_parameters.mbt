///|
// Input-sized declaration types/defaults and their synchronous workspace share
// the existing common value-node/text allowances. Original indexed input stays
// borrowed. Stages and the root-field Map coexist with that output. Fixed
// reader/Result/quotation controls stay in the existing Check Host baseline.
fn request_parameter_source_bytes(
  program : @syntax.Program,
  geometry : @decode.SubtreeConstructionGeometry?,
) -> Int64? {
  let mut bytes = 0L
  if geometry is Some(g) {
    guard @execution.execution_capacity_inventory_add(
        bytes,
        @execution.ValueNodeSlots,
        g.nodes.to_int64(),
        2,
      )
      is Some(next) &&
      @execution.execution_capacity_inventory_add(
        next,
        @execution.DecodedTextBytes,
        g.total_utf16,
        2,
      )
      is Some(next) else {
      return None
    }
    bytes = next
  }
  @execution.execution_capacity_inventory_add(
    bytes,
    @execution.CursorRootSlots,
    @syntax.stage_count(program).to_int64() +
    @decode.object_length(@syntax.program_body(program)).unwrap().to_int64(),
    1,
  )
}

///|
// One semantic phase, one original capacity grow. There is no external call
// between the admitted grow and the declaration/Source/Check constructors.
// The Request's Selecting fence covers synchronous current-callback reentry.
// This is logical accounting, not a physical allocator or a current cache.
fn[I] prepare_request_parameter_check_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  program : @syntax.Program,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : @checked.CheckLimits,
  source_catalog : @checked.PreparedSourceCatalog?,
  source_preparation : @stages.Source?,
  effect_limits : @publication_host.ClientEffectComputationLimits?,
) -> Result[
  ClientProgramCheckPreparation[I, Unit],
  ClientRequestPreparationIssue,
] {
  let checking = match effect_limits {
    None => limits
    Some(selected) => selected.program.checking
  }
  let source = match source_preparation {
    Some(original) => Some(original)
    None => owner.parameter_source
  }
  if source is Some(original) {
    return match effect_limits {
      None =>
        begin_program_check_preparation(
          owner.capacity,
          input,
          program,
          environment,
          supplied,
          evidence,
          checking,
          source_catalog~,
          source_preparation=Some(original),
        ).map_err(issue => ProgramCheck(issue))
      Some(selected) =>
        begin_effect_program_check_preparation(
          owner.capacity,
          input,
          program,
          environment,
          supplied,
          evidence,
          selected,
          source_catalog~,
          source_preparation=Some(original),
        ).map_err(issue => ProgramCheck(issue))
    }
  }
  let root = @syntax.program_body(program)
  // Root selection plus indexed geometry and original preflight visit at
  // most six times the admitted node count; Source adds its actual Stage copy.
  let maximum = 6L * @decode.admission_usage(root).nodes.to_int64() +
    @syntax.stage_count(program).to_int64() +
    1L
  let work = match
    @resources.begin_preparation_phase_work_continuation64(
      owner.capacity,
      input,
      @resources.ParameterSourceConstruction,
      maximum,
    ) {
    Err(issue) => return Err(Work(issue))
    Ok(value) => value
  }
  let spent = Ref(0L)
  let returned = Ref(false)
  let result = construct_request_parameter_check_owned(
    owner, input, program, environment, supplied, evidence, checking, source_catalog,
    effect_limits, work, spent, returned,
  )
  let charge = if returned.val {
    Ok(())
  } else {
    @resources.spend_preparation_phase_work_continuation64(work, spent.val)
  }
  let finished = @resources.finish_preparation_phase_work_continuation64(work)
  match charge {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  match finished {
    Err(issue) => Err(Work(issue))
    Ok(_) => result
  }
}

///|
fn[I] construct_request_parameter_check_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  program : @syntax.Program,
  environment : @checked.CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  checking : @checked.CheckLimits,
  source_catalog : @checked.PreparedSourceCatalog?,
  effect_limits : @publication_host.ClientEffectComputationLimits?,
  work : @resources.PreparationPhaseWorkContinuation64,
  spent : Ref[Int64],
  returned : Ref[Bool],
) -> Result[
  ClientProgramCheckPreparation[I, Unit],
  ClientRequestPreparationIssue,
] {
  let root = @syntax.program_body(program)
  let mut parameters = None
  for index in 0..<@decode.object_length(root).unwrap() {
    spent.val += 1L
    let (name, original) = @decode.field_at(root, index).unwrap()
    if name == "params" {
      parameters = Some(original)
      break
    }
  }
  let geometry = parameters.map(original => {
    let g = @decode.observe_subtree_construction_geometry(original)
    spent.val += g.work
    g
  })
  match
    @resources.spend_preparation_phase_work_continuation64(work, spent.val) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => spent.val = 0L
  }
  match @resources.return_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => returned.val = true
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard request_parameter_source_bytes(program, geometry) is Some(bytes) &&
    @execution.checked_preparation_add_product(r, bytes, 1L)
    is Some(base_retained) &&
    @execution.checked_preparation_add_product(e, bytes, 1L)
    is Some(base_execution) &&
    @execution.checked_preparation_add_product(
      base_retained, program_check_initial_control_bytes, 1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      base_execution, program_check_initial_control_bytes, 1L,
    )
    is Some(execution) else {
    return Err(ProgramCheck(Overflow))
  }
  match
    @resources.reserve_working_preparation_phase(
      owner.capacity,
      input,
      retained,
      execution,
    ) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  match @resources.resume_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => returned.val = false
  }
  let (prepared, nodes, _) = @parameters.prepare_declaration_read(parameters, {
    max_parameters: checking.compilation.structure.parameters,
    max_nodes: checking.compilation.traversal.nodes,
    max_depth: checking.compilation.traversal.depth,
    max_text_bytes: checking.compilation.traversal.text_bytes,
  })
  spent.val += nodes.to_int64()
  let reader = match prepared {
    Err(issue) => return Err(ParameterDeclarations(issue))
    Ok(original) => original
  }
  match @parameters.finish_declaration_read(reader) {
    Err(issue) => return Err(ParameterDeclarations(issue))
    Ok(_) => ()
  }
  let (prepared, source_work) = @stages.prepare_from_declaration_read(
    program, reader,
  )
  spent.val += source_work
  let source = match prepared {
    Err(issue) => return Err(ParameterSource(issue))
    Ok(original) => original
  }
  owner.parameter_source = Some(source)
  let child = new_program_check_preparation(
    owner.capacity,
    input,
    program,
    environment,
    supplied,
    evidence,
    checking,
    source_catalog,
    Some(source),
    base_retained,
    base_execution,
  )
  child.effect_limits = effect_limits
  Ok(child)
}

///|
// Drop only aliases to the completed original immutable reader and Source.
// Same parent/successor retains backing and consumed work until real retirement.
fn[I] clear_request_parameter_source(
  owner : ClientRequestPreparation[I],
) -> Unit {
  owner.parameter_source = None
}
