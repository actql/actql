///|
/// Project only an already-retained original semantic refusal. The Request
/// facade supplies these typed originals while its parent remains live and
/// backs this output/working frame before entry. This function has no checker,
/// binder, Source collector/resolver, compiler or ownership transfer.
///
/// The trusted Host supplies fresh audience metadata AFTER its actual Source
/// and Account decisions. The visible publication is a disclosure filter, not
/// a new Source grant. Native originals have no authored text coordinates;
/// this projection never manufactures a location from another parse.
pub fn client_program_project_original_check_outcome(
  program : @syntax.Program,
  source : @stage_parameters.Source,
  supplied : @decode.Cursor?,
  inputs : @sourceview_input.Inputs?,
  outcome : @checked.CheckOutcome,
  environment : @checked.CheckEnvironment,
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
  selector_namespace : ClientCheckSourceSelectorNamespace?,
) -> String {
  if outcome is @checked.Checked(_) || !["program", "text"].contains(input_kind) {
    return check_failed_json("check_request_invalid", correlation_ref)
  }
  if selector_namespace is Some(proof) &&
    (
      !physical_equal(
        @checked.checking_environment_wire(proof.range.environment),
        @checked.checking_environment_wire(environment),
      ) ||
      proof.context_ref != context_ref ||
      proof.program_revision != input_revision ||
      input_kind != "program"
    ) {
    return check_failed_json("check_context_invalid", correlation_ref)
  }
  let publication = source_publication_cursor(visible_publication) catch {
    _ => return check_failed_json("check_context_invalid", correlation_ref)
  }
  guard @decode.open_object(publication) is Ok(object) &&
    @decode.lookup(object, "environmentCid") is Some(cid) &&
    @decode.text(cid) is Ok(cid) &&
    cid == @checked.checking_environment_cid(environment) &&
    @decode.lookup(object, "aliases") is Some(aliases) &&
    @decode.elements(aliases) is Ok(aliases) &&
    aliases.length() <= 1024 else {
    return check_failed_json("check_context_invalid", correlation_ref)
  }
  let findings : Array[CheckFinding] = []
  check_missing_value_findings(
    findings,
    @stage_parameters.declarations(source),
    supplied,
    BoundInput,
  )
  let mut hidden = false
  let mut unregistered : @sourceview_input.Declaration? = None
  if inputs is Some(inputs) {
    if outcome is @checked.Rejected(diagnostic) &&
      @checked.diagnostic_cause(diagnostic)
      is Source(Registration(Selection(issue))) &&
      selector_namespace is Some(proof) &&
      @acquisition.unresolved_selector_declaration(
        issue,
        inputs,
        proof.range.catalog,
      )
      is Some(declaration) {
      unregistered = Some(declaration)
      findings.push(SourceSelectorUnregistered(proof.name, declaration, None))
    }
    for index in 0..<@sourceview_input.count(inputs) {
      let input = @sourceview_input.at(inputs, index).unwrap()
      let visible = match input.view {
        Some(view) => {
          let expected = "connector://" +
            input.connector +
            "/" +
            input.resource +
            "#" +
            view
          aliases.any(entry => {
            check_program_public_text(entry, "sourceRef") == Some(expected)
          })
        }
        None => false
      }
      if !(unregistered is Some(original) && physical_equal(original, input)) &&
        !visible {
        hidden = true
      }
    }
  } else if @syntax.program_preparation_data(program).external_inputs > 0 {
    // A completed checker may retain its diagnostic without a separately
    // borrowed collection. Do not recollect or resolve merely for disclosure.
    hidden = true
  }
  for stage in @syntax.stages(program) {
    if @syntax.stage_table_input_count(stage) > 0 {
      hidden = true
    }
  }
  let stop = if hidden {
    // Preserve the existing independent unsupported-declaration limitation,
    // while every unresolved private dependency stays protected.
    if outcome is @checked.Rejected(diagnostic) &&
      @checked.diagnostic_cause(diagnostic)
      is Source(UnsupportedBindings(_) | UnsupportedEffects(_)) {
      let _ = check_program_diagnostic(
        findings,
        diagnostic,
        "",
        supplied,
        None,
        _ => (),
        retained_program=Some(program),
      )
    }
    findings.push(Unresolved("source_resolution"))
    Report
  } else if unregistered is Some(_) {
    Report
  } else {
    match outcome {
      @checked.Checked(_) => Failed("check_internal")
      @checked.NeedsInputs(requests) => {
        for index in 0..<@checked.input_request_count(requests) {
          match @checked.input_request_at(requests, index).unwrap().kind {
            ParameterValue(_) => () // Original declaration absences above.
            HostCapacityPolicy => {
              findings.push(CapacityPolicyRequired)
              findings.push(Limit("checking_context_missing"))
            }
            NumericReductionProfile(_) => {
              findings.push(NumericProfileRequired)
              findings.push(Limit("checking_context_missing"))
            }
            _ => findings.push(Limit("bound_values_missing"))
          }
        }
        // The original partial frontier cannot become verified when an
        // oversized/undisclosable requirement could not be enumerated.
        if findings.is_empty() {
          findings.push(Limit("bound_values_missing"))
        }
        Report
      }
      @checked.Rejected(diagnostic) =>
        check_program_diagnostic(
          findings,
          diagnostic,
          "",
          supplied,
          None,
          _ => (),
          retained_program=Some(program),
        )
    }
  }
  check_outcome_json(findings, stop, context_ref, correlation_ref, {
    scope: BoundInput,
    structured_program: input_kind == "program",
    program_pointer: None,
    source_revision: input_revision,
    source_bytes: input_bytes,
    declarations_revision: if input_kind == "program" {
      Some(input_revision)
    } else {
      declarations_revision
    },
    declarations_bytes,
    parameters_revision,
    parameters_bytes,
  })
}
