///|
// Only the same failed syntax/lowering result may supply this observation.
// Its existing output slot retains that original through report publication.
fn[I] project_request_query_check_outcome(
  owner : ClientRequestPreparation[I],
  input : I,
  terminal : ClientRequestTerminalIssue,
  visible_publication : String,
  context_ref : String,
  input_kind : String,
  input_revision : String,
  input_bytes : Int,
  declarations_revision : String?,
  declarations_bytes : Int,
  parameters_revision : String?,
  parameters_bytes : Int,
  correlation_ref : String,
  source_namespace : @local_preparation.ClientCheckSourceNamespace?,
) -> Result[String?, ClientRequestPreparationIssue] {
  let phase = owner.phase
  if phase != QuerySyntaxFailed && phase != QueryLoweringFailed {
    return if phase == Selecting { Err(WrongPhase) } else { Ok(None) }
  }
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.query_syntax is Some(query) else {
    return Err(ForeignOriginal)
  }
  let parsed_original = match query.query {
    Some(Ok(original)) => Some(original)
    _ => None
  }
  let (issue, environment, publication) = match terminal {
    QuerySyntax(original) => {
      guard phase == QuerySyntaxFailed &&
        query.query is Some(Err(retained)) &&
        physical_equal(retained, original) else {
        return Err(ForeignOriginal)
      }
      let issue = match original {
        Frontend(value) => value
        Request(SourceInput(Source(Frontend(value)))) => value
        _ => return Ok(None)
      }
      (issue, None, None)
    }
    QueryLowering(original) => {
      guard phase == QueryLoweringFailed &&
        query.lowering is Some(lowering) &&
        lowering.output is Some(Err(retained)) &&
        physical_equal(retained, original) else {
        return Err(ForeignOriginal)
      }
      let issue = match original {
        Publication(Frontend(value)) => value
        Request(SourceInput(Source(Frontend(value)))) => value
        _ => return Ok(None)
      }
      (issue, Some(lowering.environment), Some(lowering.publication))
    }
    _ => return Ok(None)
  }
  if input_kind != "text" ||
    !request_check_observation_reference(context_ref, "ctx:") ||
    !request_check_observation_reference(input_revision, "rev:") ||
    !request_check_observation_reference(correlation_ref, "corr:", digits=32) ||
    input_bytes < 0 ||
    declarations_bytes < 0 ||
    parameters_bytes < 0 ||
    declarations_revision
    .map(value => !request_check_observation_reference(value, "rev:"))
    .unwrap_or(false) ||
    parameters_revision
    .map(value => !request_check_observation_reference(value, "rev:"))
    .unwrap_or(false) {
    return Err(Policy)
  }
  if (owner.native_query_declarations is Some(_)) !=
    (declarations_revision is Some(_)) ||
    (declarations_revision is None && declarations_bytes != 0) ||
    (owner.native_parameters is Some(_)) != (parameters_revision is Some(_)) ||
    (parameters_revision is None && parameters_bytes != 0) {
    return Err(ForeignOriginal)
  }
  // Original declaration geometry bounds the diagnostic vectors without
  // parsing or binding it again. The document bounds retained name labels.
  let units = query.document.length().to_int64() +
    owner.native_query_declarations
    .map(pair => @decode.admission_usage(pair.0).nodes.to_int64())
    .unwrap_or(0L) +
    1L
  let findings = 2L *
    owner.native_query_declarations
    .map(pair => @parameters.declaration_count(pair.1).to_int64())
    .unwrap_or(0L) +
    4L
  guard request_check_observation_inventory_bytes(
      visible_publication, findings, units,
    )
    is Some(bytes) else {
    return Err(Policy)
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      let (r, e) = match
        @resources.preparation_capacity_working_extents(owner.capacity, input) {
        Err(issue) => return Err(Capacity(issue))
        Ok(value) => value
      }
      guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
        @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
        return Err(Policy)
      }
      match
        @resources.reserve_working_preparation_phase(
          owner.capacity,
          input,
          r,
          e,
        ) {
        Err(issue) => return Err(Capacity(issue))
        Ok(_) => ()
      }
      guard owner.phase == Selecting &&
        owner.input is Some(current) &&
        physical_equal(current, input) &&
        owner.query_syntax is Some(current_query) &&
        physical_equal(current_query, query) else {
        return Err(ForeignOriginal)
      }
      let same_terminal = match terminal {
        QuerySyntax(original) =>
          match query.query {
            Some(Err(current)) => physical_equal(current, original)
            _ => false
          }
        QueryLowering(original) =>
          match query.lowering {
            Some(lowering) =>
              match lowering.output {
                Some(Err(current)) =>
                  physical_equal(current, original) &&
                  environment
                  .map(value => physical_equal(value, lowering.environment))
                  .unwrap_or(false) &&
                  publication
                  .map(value => physical_equal(value, lowering.publication))
                  .unwrap_or(false)
                _ => false
              }
            None => false
          }
        _ => false
      }
      let current_parsed = match query.query {
        Some(Ok(original)) => Some(original)
        _ => None
      }
      guard same_terminal &&
        (match (parsed_original, current_parsed) {
          (None, None) => true
          (Some(original), Some(current)) => physical_equal(original, current)
          _ => false
        }) else {
        return Err(ForeignOriginal)
      }
      Ok(
        Some(
          @local_preparation.client_program_project_original_query_issue(
            issue,
            environment,
            publication,
            visible_publication,
            context_ref,
            input_revision,
            input_bytes,
            declarations_revision,
            declarations_bytes,
            parameters_revision,
            parameters_bytes,
            correlation_ref,
            source_namespace,
            query_original=parsed_original,
          ),
        ),
      )
    },
    () => if owner.phase == Selecting { owner.phase = phase },
  )
}
