///|
test "Local normalization retains original admission compilation and material owner" {
  let input = prepared(@input.Program(program))
  let original = plan(input, "normalization-run")
  let issued = issue_local_run_normalization(original).unwrap()
  let evidence = local_run_normalization_evidence(original, issued).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(evidence),
    "sha256:e245b445e5014e5764dab4bf1b9ddc3b3abdf821ddf75950f9bee9df29007164",
  )
  let other = plan(prepared(@input.Program(program)), "normalization-run")
  assert_eq(local_run_definition_cid(other), local_run_definition_cid(original))
  assert_true(
    local_run_normalization_evidence(other, issued) is Err(ForeignPlan),
  )
  let wire = @publication.run_evidence_value_json(evidence)
  assert_eq(
    @publication.run_evidence_value_json(
      restore_local_run_normalization_evidence(
        original, issued, wire, "sha256:f93d91b468d850cbc63a8c8350578af8431a2256eb2b1ef3f60586fdc640561d",
      ).unwrap(),
    ),
    wire,
  )
  assert_true(
    restore_local_run_normalization_evidence(
      other, issued, wire, "sha256:f93d91b468d850cbc63a8c8350578af8431a2256eb2b1ef3f60586fdc640561d",
    )
    is Err(ForeignPlan),
  )
  assert_true(
    restore_local_run_normalization_evidence(
      original,
      issued,
      wire,
      @host.client_local_completion_free_catalog_cid(),
    )
    is Err(Normalization(ForeignCatalog)),
  )
  // Equal identity does not substitute another original compilation owner.
  let mismatched : LocalRunPlan = {
    ..original,
    compilation: other.compilation,
  }
  assert_true(
    issue_local_run_normalization(mismatched) is Err(Binding(ForeignRun)),
  )
}
