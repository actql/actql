///|
test "SourceView top k policy retains selection counts and partition occurrences" {
  for partition in [None, Some("[]"), Some("[\"id\",\"id\"]")] {
    for parameter in [false, true] {
      let name = if partition is Some(_) { "top_k_by" } else { "top_k" }
      let program = checked_direct_program_fixture(
        top_k_step="{\"" +
          name +
          "\":{\"k\":" +
          (if parameter { "{\"$param\":\"count\"}" } else { "2" }) +
          ",\"by\":[{\"id\":\"desc\"}]" +
          partition.map(p => ",\"partition_by\":" + p).unwrap_or("") +
          "}}",
      )
      let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
      assert_eq(publication_policy_source_count(policy), 1)
      assert_eq(publication_policy_top_k_count(policy), 1)
      assert_true(policy.unknown_provenance)
      let retained = publication_policy_top_k_at(policy, 0).unwrap()
      assert_eq(retained.step, 1)
      assert_eq(
        retained.count,
        if parameter {
          @relation.Parameter("count")
        } else {
          @relation.Literal(2L)
        },
      )
      assert_eq(
        @relation.operation(retained.operation),
        if partition is Some(_) {
          @relation.TopKBy
        } else {
          @relation.TopK
        },
      )
      assert_eq(
        @relation.top_k_partition_count(retained.operation),
        if partition == Some("[\"id\",\"id\"]") {
          2
        } else {
          0
        },
      )
      assert_true(publication_policy_top_k_at(policy, -1) is None)
      assert_true(publication_policy_top_k_at(policy, 1) is None)
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut selections = 0
      let mut partitions = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(TopKExecution(check))) {
          assert_true(physical_equal(check.operation, retained.operation))
          assert_eq(check.count, retained.count)
          assert_eq(check.site.step, retained.step)
          match check.rule {
            SelectOrderedPrefix => selections += 1
            PartitionByCanonicalKeys => partitions += 1
          }
        }
      }
      assert_eq(selections, 1)
      assert_eq(partitions, if partition is Some(_) { 1 } else { 0 })
    }
  }
}
