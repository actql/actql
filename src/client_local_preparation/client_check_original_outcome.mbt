///|
/// Project an already-retained original semantic outcome. The Request
/// facade supplies these typed originals while its parent remains live and
/// backs this output/working frame before entry. This function has no checker,
/// binder, Source collector/resolver, compiler or ownership transfer.
///
/// The trusted Host supplies fresh audience metadata AFTER its actual Source
/// and Account decisions. The visible publication is a disclosure filter, not
/// a new Source grant. Native originals have no authored text coordinates.
/// A matching retained Parameters representation may explain its existing
/// scalar key spans; no Program or Parameters document is parsed again.
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
  original_parameters? : String? = None,
  original_document? : String? = None,
  document_format? : @syntax.Format = Json,
) -> String {
  if !["program", "text"].contains(input_kind) {
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
  let mut original_pointer = None
  // An authored raw document uses the SAME retained Program cursor/spans.
  // Captured native values without text keep their existing no-location view.
  let diagnostic_document = original_document.unwrap_or("")
  let diagnostic_body = original_document.map(_ => @syntax.program_body(program))
  let diagnostic_program = if original_document is Some(_) {
    None
  } else {
    Some(program)
  }
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
  // A completed input read before Source resolution is independent of every
  // private Source's availability. The old later binder keeps its original
  // disclosure filter; absence of this original never starts another read.
  let independent = @checked.independent_supplied_binding_issue(
    outcome, program, supplied,
  )
  let supplied_issue = match independent {
    Some(issue) => Some(issue)
    None =>
      if !hidden &&
        outcome is @checked.Rejected(diagnostic) &&
        @checked.diagnostic_cause(diagnostic)
        is Source(SourceView(Binding(Binding(issue)))) {
        Some(issue)
      } else {
        None
      }
  }
  let supplied_refusal = if supplied_issue is Some(issue) &&
    issue is BindingInput(Supplied, _) &&
    check_binding_fault(issue) is Invalid {
    findings.push(
      check_supplied_type_finding(
        issue,
        @stage_parameters.declarations(source),
        supplied,
        original_parameters,
      ),
    )
    true
  } else {
    false
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
        diagnostic_document,
        supplied,
        original_parameters,
        value => original_pointer = value,
        format=document_format,
        original_body=diagnostic_body,
        retained_program=diagnostic_program,
      )
    }
    findings.push(Unresolved("source_resolution"))
    Report
  } else if unregistered is Some(_) || supplied_refusal {
    Report
  } else {
    match outcome {
      @checked.Checked(_) => Report
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
          diagnostic_document,
          supplied,
          original_parameters,
          value => original_pointer = value,
          format=document_format,
          original_body=diagnostic_body,
          retained_program=diagnostic_program,
        )
    }
  }
  check_outcome_json(findings, stop, context_ref, correlation_ref, {
    scope: BoundInput,
    structured_program: input_kind == "program",
    program_pointer: original_pointer,
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
