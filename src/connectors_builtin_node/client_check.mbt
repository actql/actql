///|
/// Public check of authored source against the Host's audience-visible alias
/// publication. Absent and inaccessible aliases are both left out of that
/// publication by the Host, so checking never sees the difference. This is the
/// one projection that builds `actql-check-outcome/0.1`; private causes,
/// supplied values and Host metadata never reach it.
priv enum CheckFinding {
  // A disclosable proven violation of the caller's own input.
  Violation(String)
  // An obligation that cannot be discharged from disclosable evidence.
  Unresolved(String)
  // An allowed construct or budget the checker could not close.
  Limit(String)
}

///|
priv enum CheckStop {
  Report
  Failed(String)
}

///|
let check_outcome_version = "actql-check-outcome/0.1"

///|
/// Check one source document for the public `check` operation. `context_ref`
/// is the Host-issued opaque reference to the audience-bound scope and
/// context; the verdict is never serialized without it.
#export_name("clientProgramCheckSource")
pub fn client_program_check_source(
  document : String,
  format : String,
  environment : @program_check.CheckEnvironment,
  visible_publication : String,
  declarations : String?,
  parameters : String?,
  context_ref : String,
) -> String {
  let findings : Array[CheckFinding] = []
  let stop = check_source_findings(
    findings, document, format, environment, visible_publication, declarations, parameters,
  )
  check_outcome_json(findings, stop, context_ref)
}

///|
/// The checking context itself is not disclosable to this audience. No
/// verdict, report, scope or context field is serialized.
#export_name("clientProgramCheckUnavailable")
pub fn client_program_check_unavailable(correlation_ref : String) -> String {
  try {
    let writer = @encode.writer(1024, 16, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "correlation_ref")
    @encode.string_value(writer, correlation_ref)
    @encode.key(writer, "outcome")
    @encode.string_value(writer, "unavailable")
    @encode.key(writer, "problem")
    @encode.begin_object(writer)
    @encode.key(writer, "code")
    @encode.string_value(writer, "check_unavailable")
    @encode.end_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, check_outcome_version)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => abort("CheckUnavailableEncoding")
  }
}

///|
fn check_source_findings(
  findings : Array[CheckFinding],
  document : String,
  format : String,
  environment : @program_check.CheckEnvironment,
  visible_publication : String,
  declarations : String?,
  parameters : String?,
) -> CheckStop {
  let selected = match @source_frontend.select_format(format) {
    Ok(Text) => @source_frontend.Text
    Ok(Sql) => @source_frontend.Sql
    _ => return Failed("check_format_unsupported")
  }
  let context = client_source_context(
    environment, visible_publication, declarations,
  ) catch {
    // The caller's own declaration document is a disclosable input fact.
    ClientSourceStop(Declarations) => {
      findings.push(Violation("parameter_declarations_invalid"))
      return Report
    }
    // Host installation metadata: not the caller's input.
    ClientSourceStop(_) => return Failed("check_context_invalid")
  }
  // Supplied values are bound against the caller's declarations before and
  // independently of relation resolution: an inaccessible source must not
  // hide a definite supplied-value violation.
  match context.parameter_declarations {
    Some(declared) =>
      match client_program_input("json", parameters) {
        Err(_) => findings.push(Violation("supplied_parameters_invalid"))
        Ok((_, supplied)) =>
          match
            @parameter_binding.bind(declared, supplied, {
              max_nodes: 8192,
              max_depth: 64,
              max_text_bytes: 65536,
            }) {
            Ok(NeedsBindings(_)) => findings.push(Limit("bound_values_missing"))
            Ok(Ready(_)) => ()
            Err(_) => findings.push(Violation("supplied_value_invalid"))
          }
      }
    None => ()
  }
  let lowered = match
    @source_frontend.lower(document, selected, Some(context)) {
    Ok(value) => value
    Err(issue) => {
      match issue {
        QuerySyntax({ issue: Limit(_), .. }) =>
          findings.push(Limit("analysis_budget_exhausted"))
        QuerySyntax(_) | WrongQueryForm =>
          findings.push(Violation("query_syntax_invalid"))
        // Absent and inaccessible relations are both missing from the
        // audience-visible publication; neither is a proven violation.
        QueryLowering(UnknownRelation) =>
          findings.push(Unresolved("source_resolution"))
        QueryLowering(
          UnsupportedProjection
          | UnsupportedGrouping
          | UnsupportedAggregate
          | UnsupportedHaving
          | UnsupportedOrdering
          | UnsupportedAnalytic
          | UnsupportedSet
          | UnsupportedJoin
          | UnsupportedCte
          | UnsupportedGraph
          | UnsupportedInfer
          | UnsupportedNearest
        ) => findings.push(Limit("implementation_limit"))
        // Resolved against visible relations only: a disclosable fact.
        QueryLowering(_) => findings.push(Violation("query_invalid"))
        InvalidFormat | MissingQueryContext | Encoding =>
          return Failed("check_internal")
      }
      return Report
    }
  }
  if findings.iter().any(finding => finding is Violation(_)) {
    return Report
  }
  let outcome = client_program_prepare_effect_free_with_parameters(
    lowered.document,
    "json",
    environment,
    parameters,
  )
  match outcome {
    Prepared(_) => ()
    Rejected(issue) =>
      match client_program_preparation_issue_code(outcome) {
        Some("check_invalid_input") =>
          findings.push(Violation("program_invalid"))
        Some("supplied_syntax") | Some("supplied_admission") =>
          findings.push(Violation("supplied_parameters_invalid"))
        Some("needs_inputs") | Some("check_missing_input") =>
          findings.push(Limit("bound_values_missing"))
        Some("check_unsupported") | Some("effect_not_supported") =>
          findings.push(Limit("implementation_limit"))
        Some("check_compile_limit") =>
          findings.push(Limit("analysis_budget_exhausted"))
        _ => {
          ignore(issue)
          return Failed("check_internal")
        }
      }
  }
  Report
}

///|
/// Public verdict from disclosable evidence only.
fn check_verdict(findings : Array[CheckFinding]) -> String {
  if findings.iter().any(finding => finding is Violation(_)) {
    "invalid"
  } else if findings.is_empty() {
    "verified"
  } else {
    "undetermined"
  }
}

///|
fn check_codes(
  findings : Array[CheckFinding],
  select : (CheckFinding) -> String?,
) -> Array[String] {
  let codes : Array[String] = []
  for finding in findings {
    match select(finding) {
      Some(code) => if !codes.contains(code) { codes.push(code) }
      None => ()
    }
  }
  codes.sort()
  codes
}

///|
fn write_check_report(
  writer : @encode.Writer,
  findings : Array[CheckFinding],
  context_ref : String,
  verdict : String,
) -> Unit raise @encode.EncodeFailure {
  let violations = check_codes(findings, finding => {
    match finding {
      Violation(code) => Some(code)
      _ => None
    }
  })
  let unresolved = check_codes(findings, finding => {
    match finding {
      Unresolved(boundary) => Some(boundary)
      _ => None
    }
  })
  let limits = check_codes(findings, finding => {
    match finding {
      Limit(code) => Some(code)
      _ => None
    }
  })
  @encode.begin_object(writer)
  @encode.key(writer, "context_ref")
  @encode.string_value(writer, context_ref)
  @encode.key(writer, "coverage")
  @encode.begin_object(writer)
  @encode.key(writer, "limits")
  @encode.begin_array(writer)
  for code in limits {
    @encode.begin_object(writer)
    @encode.key(writer, "code")
    @encode.string_value(writer, code)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "unresolved")
  @encode.begin_array(writer)
  for boundary in unresolved {
    @encode.begin_object(writer)
    @encode.key(writer, "boundary")
    @encode.string_value(writer, boundary)
    @encode.key(writer, "reason")
    @encode.string_value(writer, "unresolved_protected")
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
  @encode.key(writer, "reasons")
  @encode.begin_array(writer)
  for code in violations {
    @encode.begin_object(writer)
    @encode.key(writer, "code")
    @encode.string_value(writer, code)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "scope")
  @encode.begin_object(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "bound_input")
  @encode.end_object(writer)
  @encode.key(writer, "verdict")
  @encode.string_value(writer, verdict)
  @encode.end_object(writer)
}

///|
/// The reporting budget is separate from the analysis budget: a report that
/// cannot be bounded becomes Failed without a partial report.
fn check_outcome_json(
  findings : Array[CheckFinding],
  stop : CheckStop,
  context_ref : String,
) -> String {
  try {
    let writer = @encode.writer(65536, 4096, 16)
    @encode.begin_object(writer)
    match stop {
      Report => {
        @encode.key(writer, "outcome")
        @encode.string_value(writer, "completed")
        @encode.key(writer, "report")
        write_check_report(
          writer,
          findings,
          context_ref,
          check_verdict(findings),
        )
      }
      Failed(problem) => {
        @encode.key(writer, "outcome")
        @encode.string_value(writer, "failed")
        // A partial report is only ever invalid, never verified or a guess.
        if check_verdict(findings) == "invalid" {
          @encode.key(writer, "partial_report")
          write_check_report(writer, findings, context_ref, "invalid")
        }
        @encode.key(writer, "problem")
        @encode.begin_object(writer)
        @encode.key(writer, "code")
        @encode.string_value(writer, problem)
        @encode.end_object(writer)
      }
    }
    @encode.key(writer, "version")
    @encode.string_value(writer, check_outcome_version)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ =>
      "{\"outcome\":\"failed\",\"problem\":{\"code\":\"check_report_unbounded\"},\"version\":\"" +
      check_outcome_version +
      "\"}"
  }
}
