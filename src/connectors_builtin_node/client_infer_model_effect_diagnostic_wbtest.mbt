///|
// Pure projection of the actual returned Core issue. No state, current port,
// body decoder, validator or Model/Source operation is entered here.
test "original Model acquired failure kind projects the actual typed returned result" {
  let cases : Array[
    (@publication_host.ClientEffectAcquiredEvidenceIssue, String),
  ] = [
    (Invocation(MissingUnit), "invocation.missing_unit"),
    (Invocation(NotSourceFree), "invocation.not_source_free"),
    (Invocation(ForeignCapturedInput), "invocation.foreign_captured_input"),
    (Invocation(MissingCapturedInput), "invocation.missing_captured_input"),
    (
      Invocation(ForeignSourceObservation),
      "invocation.foreign_source_observation",
    ),
    (
      Invocation(IncompleteResultImports),
      "invocation.incomplete_result_imports",
    ),
    (Invocation(ForeignResultImport), "invocation.foreign_result_import"),
    (Invocation(Encoding), "invocation.encoding"),
    (Relation(WrongEvidence), "relation.wrong_evidence"),
    (Relation(WrongScope), "relation.wrong_scope"),
    (Relation(WrongRetention), "relation.wrong_retention"),
    (Relation(KeySetRole(7, "private-role")), "relation.key_set_role"),
    (Relation(KeySetArity(7)), "relation.key_set_arity"),
    (Relation(KeySetContract(7, 9)), "relation.key_set_contract"),
    (Relation(KeySetOrder(7, 9, InvalidKey)), "relation.key_set_order"),
    (Relation(Encoding), "relation.encoding"),
    (Relation(Contract(UnknownContract)), "relation.contract.unknown_contract"),
    (Relation(Contract(InvalidLimits)), "relation.contract.invalid_limits"),
    (Relation(Contract(InvalidWire)), "relation.contract.invalid_wire"),
    (Relation(Contract(InvalidObject)), "relation.contract.invalid_object"),
    (
      Relation(Contract(MissingField("private-field"))),
      "relation.contract.missing_field",
    ),
    (
      Relation(Contract(UnknownField("private-field"))),
      "relation.contract.unknown_field",
    ),
    (
      Relation(Contract(InvalidField("private-field"))),
      "relation.contract.invalid_field",
    ),
    (
      Relation(Contract(IdentityAlreadyPresent)),
      "relation.contract.identity_already_present",
    ),
    (Relation(Contract(IdentityMissing)), "relation.contract.identity_missing"),
    (
      Relation(Contract(IdentityMismatch)),
      "relation.contract.identity_mismatch",
    ),
    (
      Relation(Contract(ConditionalField("private-field"))),
      "relation.contract.conditional_field",
    ),
    (Relation(Contract(Encoding)), "relation.contract.encoding"),
    (Dependency(ForeignBody), "dependency"),
  ]
  for (issue, expected) in cases {
    let result : Result[
      @publication_host.ClientEffectModelAcquiredEvidence,
      @publication_host.ClientEffectAcquiredEvidenceIssue,
    ] = Err(issue)
    assert_eq(
      client_program_original_model_acquired_effect_evidence_issue_kind(result),
      Some(expected),
    )
  }
}
