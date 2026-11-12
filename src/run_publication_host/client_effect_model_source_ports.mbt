///|
// Match an already admitted original to the checked Source occurrence. This
// reads original metadata only: no parse, Source current callback or admission.
fn model_effect_source_original_matches_check(
  original : ClientInferSourceOriginal,
  check : @checked.SourceExecution,
) -> Bool {
  let subject = @checked.source_execution_subject(check)
  guard @checked.source_execution_kind(check) is @checked.CarrierResponse &&
    subject.request is @acquisition.Direct(mode, _) else {
    return false
  }
  match original {
    Whole(acquisition) =>
      physical_equal(@acquisition.source_acquisition_mode(acquisition), mode) &&
      @context.program_identity_stage_requests(subject.owner, subject.stage).map(requests => {
          physical_equal(
            requests,
            @acquisition.source_acquisition_owner(acquisition),
          )
        },
      ) ==
      Some(true) &&
      @acquisition.source_acquisition_source_index(acquisition) == subject.input
    Query(requirement) => {
      let (stage, input) = @planning.query_requirement_site(requirement)
      physical_equal(
        @planning.query_requirement_program(requirement),
        subject.owner,
      ) &&
      @context.program_identity_stage_at(subject.owner, subject.stage).map(value => {
        @program_refs.stage_definition_id(
          @context.stage_identity_definition(value),
        )
      }) ==
      Some(stage) &&
      @acquisition.declaration(subject.source).input_name == input
    }
  }
}

///|
// A Result's existing policy retains its full original Source ancestry,
// including multiple Sources in one producer. Never equate Source count with
// Result-port count or reconstruct a dependency graph from serialized DATA.
fn model_effect_result_port_policy(
  program : @checked.CheckedProgram,
  interface : @checked.BuiltResultInterface,
) -> @checked.PublicationSourcePolicy? {
  let site = @context.result_import_type_site(interface.row)
  guard site.requirement is @context.Result(_, predecessor, _) else {
    return None
  }
  let identity = @checked.source_identity(program)
  for stage in 0..<@checked.unit_count(program) {
    if @context.program_identity_stage_at(identity, stage).map(value => {
        physical_equal(value, predecessor)
      }) !=
      Some(true) {
      continue
    }
    for
      index in 0..<@checked.unit_publication_count(program, stage).unwrap_or(0) {
      let result = @checked.unit_publication_at(program, stage, index).unwrap()
      if @checked.publication_result_name(result) == interface.result_name {
        return @checked.publication_source_policy(result)
      }
    }
  }
  None
}

///|
fn model_effect_result_port_source(
  program : @checked.CheckedProgram,
  interface : @checked.BuiltResultInterface,
  original : ClientInferSourceOriginal,
) -> @checked.SourceExecution? {
  guard model_effect_result_port_policy(program, interface) is Some(policy) else {
    return None
  }
  for source in 0..<@checked.publication_policy_source_count(policy) {
    let check = @checked.publication_policy_source_at(policy, source).unwrap()
    if model_effect_source_original_matches_check(original, check) {
      return Some(check)
    }
  }
  None
}

///|
fn model_effect_checked_source_port_name(
  program : @checked.CheckedProgram,
  unit : Int,
  check : @checked.SourceExecution,
) -> String? {
  let subject = @checked.source_execution_subject(check)
  if subject.stage == unit {
    return Some(@acquisition.declaration(subject.source).input_name)
  }
  let mut name = None
  for index in 0..<@checked.unit_result_import_count(program, unit).unwrap_or(0) {
    let interface = @checked.unit_result_import_at(program, unit, index).unwrap()
    guard model_effect_result_port_policy(program, interface) is Some(policy) else {
      continue
    }
    for source in 0..<@checked.publication_policy_source_count(policy) {
      if @checked.publication_policy_source_at(policy, source).map(value => {
          physical_equal(value, check)
        }) ==
        Some(true) {
        if name is Some(_) {
          return None
        }
        name = Some(interface.input_name)
        break
      }
    }
  }
  name
}

///|
fn model_effect_inline_source(
  program : @checked.CheckedProgram,
  unit : Int,
  original : ClientInferSourceOriginal,
) -> Bool {
  for index in 0..<@checked.source_execution_count(program) {
    let check = @checked.source_execution_at(program, index).unwrap()
    if @checked.source_execution_subject(check).stage == unit &&
      model_effect_source_original_matches_check(original, check) {
      return true
    }
  }
  false
}

///|
// Resolve a declared Source to the original consumer port. Imported Result
// identity and Source ancestry remain distinct; the physical input kernel
// separately requires the actual completed Result at that port.
fn model_effect_source_port_name(
  program : @checked.CheckedProgram,
  unit : Int,
  original : ClientInferSourceOriginal,
) -> String? {
  for index in 0..<@checked.source_execution_count(program) {
    let check = @checked.source_execution_at(program, index).unwrap()
    if model_effect_source_original_matches_check(original, check) {
      return model_effect_checked_source_port_name(program, unit, check)
    }
  }
  None
}

///|
fn model_effect_imported_source(
  imports : ClientEffectImportedEvidence,
  input : ClientInferSourceInput,
) -> Bool {
  let program = @checked.effect_program_static_checked_computation(
    imports.owner.candidate,
  )
  for observed in imports.observations {
    let interface = @strategy.captured_effect_result_import_interface(
      observed.captured,
    )
    if model_effect_result_port_source(program, interface, input.original)
      is Some(check) &&
      @strategy.captured_effect_inputs_acquired_source_matches(
        imports.inputs,
        @checked.source_execution_subject(check).stage,
        input.identity,
      ) {
      return true
    }
  }
  false
}

///|
// Only a checked Result port carrying this exact keyed Source can retain its
// earlier lookup transitively. The existing import issuer binds the actual
// captured producer/Artifact and Run; a Source label or equal CID cannot do so.
// This is immutable metadata and never calls Source-current or reopens a read.
fn model_effect_imported_keyed(
  imports : ClientEffectImportedEvidence,
  sources : ClientInferComposedSources,
) -> Bool {
  guard sources.keyed is Some((_, observed, _)) else { return false }
  let check = observed.lookup.left.acquisition.check
  let program = @checked.effect_program_static_checked_computation(
    imports.owner.candidate,
  )
  for imported in imports.observations {
    let interface = @strategy.captured_effect_result_import_interface(
      imported.captured,
    )
    guard model_effect_result_port_policy(program, interface) is Some(policy) else {
      continue
    }
    if model_effect_keyed_policy_matches(policy, check) {
      return true
    }
  }
  false
}

///|
fn model_effect_keyed_policy_matches(
  policy : @checked.PublicationSourcePolicy,
  check : @checked.SourceExecution,
) -> Bool {
  guard @checked.source_execution_kind(check) is @checked.KeyedRequest(request) else {
    return false
  }
  // Publication retains the response gate; acquisition selects its request
  // gate. Their shared original binding identifies the same keyed occurrence,
  // without interchanging the two phases or admitting another lookup.
  for index in 0..<@checked.publication_policy_source_count(policy) {
    if @checked.publication_policy_source_at(policy, index).map(original => {
        match @checked.source_execution_kind(original) {
          @checked.KeyedResponse(response) => physical_equal(response, request)
          _ => false
        }
      }) ==
      Some(true) {
      return true
    }
  }
  false
}
