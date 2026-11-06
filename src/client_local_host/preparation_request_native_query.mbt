///|
fn[I, T] prepare_request_native_query_input(
  owner : ClientRequestPreparation[I],
  input : I,
  reader : @source.JsonDataReader[T],
  supplied : T?,
  declarations : T?,
) -> Result[Unit, ClientRequestTerminalIssue] {
  guard owner.phase == Open &&
    !owner.native_parameters_ready &&
    request_intent_input_ready(owner) &&
    owner.program_json is None else {
    return Err(Preparation(WrongPhase))
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  let mut bytes = 0L
  if supplied is Some(_) {
    let (source, tree) = @local_preparation.local_parameter_input_limits()
    guard request_native_tree_units(
        owner.snapshot_units,
        owner.snapshot_values,
        { source, tree, max_stages: 0, },
      )
      is Some(units) &&
      @execution.preparation_representation_cost(units) is Some(cost) else {
      return Err(Preparation(Policy))
    }
    bytes = cost
  }
  if declarations is Some(_) {
    let (source, tree) = @source_publication.source_publication_input_limits()
    guard request_native_tree_units(
        owner.snapshot_units,
        owner.snapshot_values,
        { source, tree, max_stages: 0, },
      )
      is Some(units) &&
      @execution.preparation_representation_cost(units) is Some(cost) &&
      @execution.checked_preparation_add_product(bytes, cost, 1L) is Some(total) else {
      return Err(Preparation(Policy))
    }
    // Typed declaration entries/types/defaults coexist with the retained
    // Source/index. Reuse the shared observed-data envelope once for that
    // actual variable expansion, not a policy-sized or per-wrapper census.
    guard request_snapshot_data_bytes(
        owner.snapshot_units,
        owner.snapshot_values,
      )
      is Some(typed) &&
      @execution.checked_preparation_add_product(total, typed, 1L)
      is Some(combined) else {
      return Err(Preparation(Policy))
    }
    bytes = combined
  }
  let (r0, e0) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r0, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e0, bytes, 1L) is Some(e) else {
    return Err(Preparation(Policy))
  }
  owner.phase = Selecting
  if bytes != 0L {
    match
      @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
      Err(issue) => {
        owner.phase = ProgramJsonFailed
        return Err(Preparation(Capacity(issue)))
      }
      Ok(_) => ()
    }
  }
  // Preserve ordinary Local's supplied-values-first failure order.
  owner.native_parameters = match supplied {
    None => None
    Some(value) =>
      match @local_preparation.admit_captured_local_parameters(value, reader) {
        Err(issue) => {
          owner.phase = ProgramJsonFailed
          return Err(Preparation(Parameters(issue)))
        }
        Ok(value) => Some(value)
      }
  }
  owner.native_query_declarations = match declarations {
    None => None
    Some(value) =>
      match
        @source_publication.admit_captured_query_declarations(value, reader) {
        Err(issue) => {
          owner.phase = ProgramJsonFailed
          return Err(Publication(Publication(issue)))
        }
        Ok(value) => Some(value)
      }
  }
  owner.native_parameters_ready = true
  owner.phase = Open
  Ok(())
}

///|
/// Actual SQL/Pipe terminal on the SAME original Request and SDK capture.
/// Retain native Parameters/declarations, parsed Query and lowered Program;
/// the existing checker/compiler tail consumes these exact originals once.
pub fn[I, T] prepare_request_native_query_computation(
  owner : ClientRequestPreparation[I],
  input : I,
  document : String,
  format : @frontend.Format,
  reader : @source.JsonDataReader[T],
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  evidence : Array[@context.StageCapacityInput],
  program_limits : @publication_host.ClientProgramPreparationLimits,
  effect_limits : @publication_host.ClientEffectComputationLimits,
  supplied? : T? = None,
  declarations? : T? = None,
  public_primary? : Bool = true,
) -> Result[ClientRequestComputationKind, ClientRequestTerminalIssue] {
  match
    prepare_request_native_query_computation_input(
      owner,
      input,
      document,
      format,
      reader,
      environment,
      publication,
      binding_limits=Some(request_query_binding_limits(program_limits.checking)),
      public_primary~,
      supplied~,
      declarations~,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  finish_request_original_computation(
    owner, input, environment, publication, evidence, program_limits, effect_limits,
  )
}

///|
fn[I, T] prepare_request_native_query_computation_input(
  owner : ClientRequestPreparation[I],
  input : I,
  document : String,
  format : @frontend.Format,
  reader : @source.JsonDataReader[T],
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  binding_limits? : @admitted.Limits? = None,
  supplied? : T? = None,
  declarations? : T? = None,
  public_primary? : Bool = true,
) -> Result[Unit, ClientRequestTerminalIssue] {
  match
    prepare_request_native_query_input(
      owner, input, reader, supplied, declarations,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match parse_request_query_syntax(owner, input, document, format) {
    Err(issue) => return Err(QuerySyntax(issue))
    Ok(_) => ()
  }
  match
    lower_request_published_query(
      owner,
      input,
      publication,
      environment,
      None,
      public_primary~,
      binding_limits~,
    ) {
    Err(issue) => return Err(QueryLowering(issue))
    Ok(_) => ()
  }
  Ok(())
}

///|
/// Ordinary detached native Source envelope. Fixed header reads enter no
/// variable copy; the same Request owns native values and its document/Query.
/// Typed input failures are issued here, not forged by a Host error wrapper.
pub fn[I, T] prepare_request_native_source_computation(
  owner : ClientRequestPreparation[I],
  input : I,
  captured : T,
  reader : @source.JsonDataReader[T],
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  evidence : Array[@context.StageCapacityInput],
  program_limits : @publication_host.ClientProgramPreparationLimits,
  effect_limits : @publication_host.ClientEffectComputationLimits,
  supplied? : T? = None,
  public_primary? : Bool = true,
) -> Result[ClientRequestComputationKind, ClientRequestTerminalIssue] {
  match
    prepare_request_native_source_computation_input(
      owner,
      input,
      captured,
      reader,
      environment,
      publication,
      program_limits.checking,
      public_primary~,
      supplied~,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  finish_request_original_computation(
    owner, input, environment, publication, evidence, program_limits, effect_limits,
  )
}

///|
/// Keep the same JSON/YAML/SQL/Pipe input semantics and original Catalog;
/// leave compiler/Plan selection to the later same-Request completion.
pub fn[I, T] prepare_request_native_source_computation_check(
  owner : ClientRequestPreparation[I],
  input : I,
  captured : T,
  reader : @source.JsonDataReader[T],
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  evidence : Array[@context.StageCapacityInput],
  program_limits : @publication_host.ClientProgramPreparationLimits,
  effect_limits : @publication_host.ClientEffectComputationLimits,
  supplied? : T? = None,
  public_primary? : Bool = true,
) -> Result[Unit, ClientRequestTerminalIssue] {
  match
    prepare_request_native_source_computation_input(
      owner,
      input,
      captured,
      reader,
      environment,
      publication,
      program_limits.checking,
      public_primary~,
      supplied~,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  prepare_request_original_computation_check(
    owner, input, environment, publication, evidence, program_limits, effect_limits,
  )
}

///|
fn[I, T] prepare_request_native_source_computation_input(
  owner : ClientRequestPreparation[I],
  input : I,
  captured : T,
  reader : @source.JsonDataReader[T],
  environment : @checked.CheckEnvironment,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  limits : @checked.CheckLimits,
  supplied? : T? = None,
  public_primary? : Bool = true,
) -> Result[Unit, ClientRequestTerminalIssue] {
  guard owner.phase == Open &&
    !owner.native_parameters_ready &&
    request_intent_input_ready(owner) else {
    return Err(Preparation(WrongPhase))
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(Preparation(ForeignOriginal))
  }
  owner.phase = Selecting
  if (reader.kind)(captured) != 5 {
    owner.phase = ProgramJsonFailed
    return Err(QuerySyntax(Frontend(@frontend.InvalidFormat)))
  }
  let document = (reader.field)(captured, "text")
  let format = (reader.field)(captured, "format")
  if (reader.kind)(document) != 3 || (reader.kind)(format) != 3 {
    owner.phase = ProgramJsonFailed
    return Err(QuerySyntax(Frontend(@frontend.InvalidFormat)))
  }
  let selected = match @frontend.select_format((reader.text)(format)) {
    Err(issue) => {
      owner.phase = ProgramJsonFailed
      return Err(QuerySyntax(Frontend(issue)))
    }
    Ok(value) => value
  }
  let declarations = (reader.field)(captured, "parameterDeclarations")
  let declarations = if (reader.kind)(declarations) == 6 {
    None
  } else {
    Some(declarations)
  }
  let document = (reader.text)(document)
  if selected == @frontend.Json || selected == @frontend.Yaml {
    // Declaration overrides belong only to textual Query input. JSON/YAML
    // carry their original declarations inside the authored Program itself.
    if declarations is Some(_) {
      owner.phase = ProgramJsonFailed
      return Err(QuerySyntax(Frontend(@frontend.InvalidFormat)))
    }
    owner.phase = Open
    match
      prepare_request_native_query_input(owner, input, reader, supplied, None) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    return prepare_request_document_computation_input(
      owner,
      input,
      document,
      if selected == @frontend.Json {
        @syntax.Json
      } else {
        @syntax.Yaml
      },
      limits.input,
    )
  }
  owner.phase = Open
  prepare_request_native_query_computation_input(
    owner,
    input,
    document,
    selected,
    reader,
    environment,
    publication,
    binding_limits=Some(request_query_binding_limits(limits)),
    public_primary~,
    supplied~,
    declarations~,
  )
}

///|
// Match the existing original binder's initial topology controls. No Catalog
// admission has happened on the refused lowering path, so none is repeated.
fn request_query_binding_limits(
  limits : @checked.CheckLimits,
) -> @admitted.Limits {
  let selected = limits.compilation.traversal
  {
    max_nodes: selected.nodes,
    max_depth: selected.depth,
    max_text_bytes: selected.text_bytes,
  }
}
