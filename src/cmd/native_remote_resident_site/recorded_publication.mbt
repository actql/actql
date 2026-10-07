///|
/// Read only original Owner-issued publication evidence. This directory is a
/// local custody input, not a compiler, issuer, executor or replacement Run.
/// The resident caller must match its authority to the saved dispatch and
/// independently restore completed custody before any report is delivered.
fn load_recorded_publication(
  root : String,
) -> @publication.RecordedRunPublication raise CommandStop {
  // Same evidence limits used by the ordinary resident materials admission.
  let bytes = 100000
  let nodes = 10000
  let depth = 100
  let read = name => load_text(root, name, bytes.to_int64())
  let template = match
    @publication.admit_run_evidence_value(
      "bound_invocation_template",
      read("bound-template.json"),
      bytes,
      nodes,
      depth,
    ) {
    Ok(value) => value
    Err(_) => stop("recorded-template-invalid")
  }
  let plan = match
    @publication.admit_publication_contract(
      "compiled_plan",
      read("compiled-plan.json"),
      bytes,
      nodes,
      depth,
    ) {
    Ok(value) => value
    Err(_) => stop("recorded-plan-invalid")
  }
  let prepared = match
    @publication.admit_run_evidence_value(
      "prepared_invocation",
      read("prepared-invocation.json"),
      bytes,
      nodes,
      depth,
    ) {
    Ok(value) => value
    Err(_) => stop("recorded-prepared-invalid")
  }
  let authorization = match
    @publication.admit_run_evidence_value(
      "run_authorization",
      read("run-authorization.json"),
      bytes,
      nodes,
      depth,
    ) {
    Ok(value) => value
    Err(_) => stop("recorded-authorization-invalid")
  }
  let admission = match
    @publication.admit_run_publication(template, prepared, authorization, plan) {
    Ok(value) => value
    Err(_) => stop("recorded-admission-invalid")
  }
  let definition = match
    @publication.admit_publication_contract(
      "run_definition",
      read("run-definition.json"),
      bytes,
      nodes,
      depth,
    ) {
    Ok(value) => value
    Err(_) => stop("recorded-run-invalid")
  }
  let result = match
    @publication.admit_result_definition(
      read("result-definition.json"),
      bytes,
      nodes,
      depth,
    ) {
    Ok(value) => value
    Err(_) => stop("recorded-result-invalid")
  }
  match
    @publication.prepare_recorded_run_publication(admission, definition, result) {
    Ok(value) => value
    Err(_) => stop("recorded-publication-binding-invalid")
  }
}
