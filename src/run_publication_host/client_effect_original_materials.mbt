///|
/// Project materials directly from the original checked preparation and Run.
/// No caller-supplied Program, parameters or check environment can replace
/// those Owners. This does not reconstruct a preparation, extend lifetime,
/// create authorization or establish cross-process normalization custody.
pub fn issue_prepared_client_effect_run_materials(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request? : ClientRequestIdentity? = None,
  normalization? : ClientEffectNormalization? = None,
) -> Result[String, ClientEffectRunMaterialsIssue] {
  let prepared = client_effect_compilation_owner(allowed.compilation)
  if prepared.source_intent is Some(_) && request is None {
    return Err(Request(IdentityMismatch))
  }
  match bind_client_effect_compiled_run(prepared, allowed, definition) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  if allowed.compilation.normalization_profile is Some(_) &&
    normalization is None {
    return Err(Normalization(MissingOriginalJournal))
  }
  let normalization_wire = match normalization {
    None => None
    Some(original) =>
      match prepared_client_effect_normalization_evidence(prepared, original) {
        Ok(value) => {
          if original.inventory is LocalUpdate(_) &&
            !same_client_effect_normalization_profile(
              Some(original.inventory),
              allowed.compilation.normalization_profile,
            ) {
            return Err(Normalization(ForeignCatalog))
          }
          Some(@publication.run_evidence_value_json(value))
        }
        Err(issue) => return Err(Normalization(issue))
      }
  }
  let request_wire = match request {
    None => None
    Some(value) => {
      match prepared_client_effect_request_scope(prepared, value) {
        Ok(_) => ()
        Err(issue) => return Err(Request(issue))
      }
      if client_request_input_cid(value) !=
        client_effect_original_input_intent_cid(prepared) {
        return Err(Request(IdentityMismatch))
      }
      match client_request_identity_record_wire(value) {
        Ok(wire) => Some(wire)
        Err(issue) => return Err(Request(issue))
      }
    }
  }
  encode_prepared_client_effect_materials(
    allowed, definition, request_wire, normalization_wire,
  )
}

///|
/// Only the source frontend's original preparation can retain this intent.
/// The legacy path keeps its exact source-free identity.
fn client_effect_original_input_intent_cid(
  prepared : PreparedClientEffectComputation,
) -> String {
  match prepared.source_intent {
    None => source_free_caller_input_intent_cid()
    Some(intent) => client_submitted_intent_cid(intent)
  }
}

///|
/// The shared bounded projection codec is also used to verify canonical
/// material bytes after original Run admission. It does not issue a journal,
/// authorization, invocation or Run and has no replacement authoring inputs.
fn encode_prepared_client_effect_materials(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request_wire : String?,
  normalization_wire : String?,
) -> Result[String, ClientEffectRunMaterialsIssue] {
  let prepared = client_effect_compilation_owner(allowed.compilation)
  let (program, parameters, environment) = match
    client_effect_original_input_wires(prepared) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let infer_input = match
    client_effect_original_infer_input(allowed.compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let infer_inputs_wire = match client_effect_original_infer_inputs(allowed.compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let source_free_policy_input = match
    client_effect_original_source_free_policy_input(allowed.compilation) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  encode_client_run_materials_body(
    allowed.admission,
    definition,
    prepared_client_effect_computation_environment_cid(prepared),
    environment,
    program,
    parameters,
    request_wire~,
    normalization_wire~,
    target_selections_wire=prepared_client_effect_target_selections(prepared),
    infer_input~,
    infer_inputs_wire~,
    source_free_policy_input~,
  ).map_err(fn(issue) { ClientEffectRunMaterialsIssue::Input(issue) })
}

///|
/// Both pre-Run checkpoint and admitted Run projection read the same retained
/// source, supplied values and checked environment. Neither accepts replacement
/// authoring inputs or reads a current alias publication.
fn client_effect_original_input_wires(
  prepared : PreparedClientEffectComputation,
) -> Result[(String, String?, String), ClientEffectRunMaterialsIssue] {
  try {
    let source_writer = @encode.writer(65536, 8192, 64)
    @syntax.emit_program_source(prepared.source, source_writer)
    let program = @encode.finish(source_writer)
    let parameters = match prepared.supplied {
      None => None
      Some(value) => {
        let writer = @encode.writer(65536, 8192, 64)
        @syntax.emit_admitted_source_value(value, writer)
        Some(@encode.finish(writer))
      }
    }
    let environment_writer = @encode.writer(65536, 4096, 64)
    @environment.emit(
      @checked.effect_program_static_environment(prepared.candidate),
      environment_writer,
    )
    Ok((program, parameters, @encode.finish(environment_writer)))
  } catch {
    _ => return Err(Input(MaterialsMalformed))
  }
}
