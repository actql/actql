///|
/// Source and shape construction use the existing parser/decoder. This driver
/// changes custody/admission only; it is not another language implementation.
pub fn[I] parse_closed_values_document(
  owner : ClientClosedValuesPreparation[I],
) -> Result[Unit,ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) && physical_equal(original,owner) && owner.input is Some(input) else {return Err(ForeignOriginal)}
  if owner.retiring || owner.parsed is Some(_) || owner.work is Some(_) {return Err(WrongPhase)}
  guard owner.document is Some(document) && owner.lexical is Some(facts) && owner.envelope is Some(bounds) else {return Err(WrongPhase)}
  guard closed_values_source_phase_layout(facts) is Some(source) &&
    preparation_representation_cost(source.retained) is Some(retained_add) &&
    closed_values_walk_storage_layout(facts.node_upper,Int::max(bounds.fields,9)) is Some(walk) &&
    closed_values_map_constructor_layout(Int::max(bounds.fields,9)) is Some(map) &&
    closed_values_compiler_failure_layout(facts.depth_upper) is Some(failure) &&
    preparation_representation_cost(source.parser_temporary) is Some(parser_peak) &&
    preparation_representation_cost(source.decoder_temporary) is Some(decoder_peak) &&
    closed_values_sum_layouts([walk,map,failure]) is Some(shape_temporary) &&
    preparation_representation_cost(shape_temporary) is Some(shape_peak) &&
    client_closed_values_initial_control_capacity(owner.policy) is Some((_,controls)) else {return Err(Policy)}
  // SDK snapshot and submitted-intent callbacks have returned. Their surviving
  // wire/snapshot/intent dependencies remain in R; their private frames/arrays
  // are not returned. The parser AST overlaps decoding inside its own peak,
  // but parse_program_input returns only Cursor+usage before shape inspection.
  let source_peak=Int64::max(parser_peak,Int64::max(decoder_peak,shape_peak))
  guard closed_values_execution_peak(owner.execution_quote,source_peak,controls) is Some(execution) else {return Err(Policy)}
  if retained_add>9223372036854775807L-owner.retained_quote {return Err(Policy)}
  let retained=owner.retained_quote+retained_add
  match reserve_closed_values_phase(owner.capacity,input,SourceParsing,retained,execution) {
    Err(issue)=>return Err(issue)
    Ok(_)=>{owner.retained_quote=retained;owner.execution_quote=execution}
  }
  // Existing source/tree budgets govern these actual constructors separately;
  // no claim that their counters are a shared aggregate CPU budget is made.
  let parsed=match @syntax.parse_program_input(document,{
    source:{max_input_bytes:facts.input_bytes,max_nodes:facts.node_upper,max_depth:facts.depth_upper},
    tree:{max_nodes:facts.node_upper,max_depth:facts.depth_upper,max_string_bytes:facts.longest_quoted_utf16,max_total_string_bytes:facts.quoted_utf16_units},
    max_stages:1,
  },format=@syntax.Json) {
    Err(issue)=>return Err(Syntax(issue))
    Ok(value)=>value
  }
  owner.parsed=Some(parsed)
  guard closed_values_shape_work(bounds.fields,bounds.rows) is Some(work_limit) else {return Err(Policy)}
  let work=match @resources.begin_preparation_phase_work(owner.capacity,input,@resources.ShapeInspection,work_limit) {
    Err(issue)=>return Err(Work(issue))
    Ok(value)=>value
  }
  owner.work=Some(work)
  match @resources.spend_preparation_phase_work(work,work_limit) {
    Err(issue)=>return Err(Work(issue))
    Ok(_)=>()
  }
  guard closed_values_shape(parsed,work_limit) is Some(shape) && shape.fields==bounds.fields && shape.rows==bounds.rows else {return Err(Policy)}
  owner.shape=Some(shape)
  match @resources.finish_preparation_phase_work(work) {
    Err(issue)=>return Err(Work(issue))
    Ok(_)=>owner.work=None
  }
  let program=closed_values_program_inventories(shape)
  guard preparation_representation_cost(program.retained) is Some(program_retained) &&
    closed_values_sum_layouts([program.containers_peak,program.carriers_peak,program.failure_peak]) is Some(program_temporary) &&
    preparation_representation_cost(program_temporary) is Some(program_execution) else {return Err(Policy)}
  // parse_program_input and the shape proof have returned. ParsedProgramInput
  // holds no parser AST; its indexed tree and shared Strings/Spans are in R.
  guard closed_values_execution_peak(execution,program_execution,controls) is Some(program_peak) else {return Err(Policy)}
  if program_retained>9223372036854775807L-retained {return Err(Policy)}
  match reserve_closed_values_phase(owner.capacity,input,ProgramConstruction,retained+program_retained,program_peak) {
    Err(issue)=>return Err(issue)
    Ok(_)=>{owner.retained_quote=retained+program_retained;owner.execution_quote=program_peak}
  }
  match @syntax.finish_program_input(parsed) {
    Err(issue)=>Err(Syntax(issue))
    Ok(program)=>{owner.program=Some(program);Ok(())}
  }
}
