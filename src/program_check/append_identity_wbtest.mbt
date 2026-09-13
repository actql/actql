///|
test "formal append closes disjoint literal identity through Result imports" {
  let checked : Array[CheckedProgram] = []
  let _ = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    through_check=true,
    second_stage=true,
    checked_results=checked,
    producer_expression="'crm'",
    producer_suffix=",{\"from\":\"rows\",\"derive\":{\"value\":\"'support'\"},\"as\":\"other\"},{\"from\":\"derived\",\"append\":{\"with\":\"other\"},\"as\":\"combined\"}",
    producer_result_from="combined",
    extra_step_budget=2,
    string_limit=Some(32),
    second_steps="[{\"take\":1,\"as\":\"chosen\"}]",
    second_result_from="chosen",
  )
  let p = checked[0]
  let first = unit_pipeline(p, 0).unwrap()
  let keys = @pipeline.candidate_keys(first, Step(2)).unwrap()
  assert_eq(@evidence.key_witness_count(keys), 1)
  let key = @evidence.key_witness_at(keys, 0).unwrap()
  assert_eq(@evidence.key_origin(key), AppendResult)
  let second = unit_pipeline(p, 1).unwrap()
  let imported = @evidence.key_witness_at(
    @pipeline.candidate_keys(second, Input(0)).unwrap(),
    0,
  ).unwrap()
  assert_eq(@evidence.key_origin(imported), AppendResult)
  assert_true(
    physical_equal(
      @evidence.key_append_producer(key).unwrap(),
      @evidence.key_append_producer(imported).unwrap(),
    ),
  )
  assert_true(@pipeline.take_order(second, 0) is Some(_))
  let domain = @evidence.literal_domain(
    @pipeline.literal_domains(second, Input(0)).unwrap(),
    Unqualified("value"),
  ).unwrap()
  assert_eq(@evidence.literal_value_count(domain), 2)
  assert_true(@evidence.literal_origin(domain) is Union(_, _, _))
  assert_true(@evidence.key_pending(imported).contains(ValidateKeyProducer))
}
