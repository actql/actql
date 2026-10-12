///|
test "direct acquisition Source facts retain the fixed Catalog identities" {
  let (query, _) = query_sequence_fixture()
  let facts = @planning.query_acquisition_source_evidence_facts(query).unwrap()
  // Independent identities from the fixed Catalog input, not current product
  // output. Sharing the selector with keyed reads must not reidentify Direct.
  assert_eq(facts.source_ref, "connector://crm/main/r#v")
  assert_eq(
    facts.source_contract_cid,
    "sha256:1f5ce9a50072a24f9cf0673d174f4f0639a216cc5537277e15299fef59db921f",
  )
  assert_eq(facts.source_view_contract_cid, facts.source_contract_cid)
  assert_eq(
    facts.carrier_schema_contract_cid,
    "sha256:19f617653f557bcc5e2d851a889101df45e60326a4192a6fe5b109ccef4d0a1e",
  )
  assert_eq(
    facts.source_data_policy_cid,
    "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf",
  )
  assert_eq(facts.data_classification, "unknown")
}
