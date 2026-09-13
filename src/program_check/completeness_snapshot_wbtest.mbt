///|
test "Local completeness claims retain snapshot ownership without changing Unit semantics" {
  let definitions : Array[String] = []
  for claim in ["absent", "schema", "complete", "partial"] {
    let snapshots = if claim == "absent" {
      "[]"
    } else {
      "[{" +
      (if claim == "schema" {
        ""
      } else {
        "\"completeness\":\"" +
        claim +
        "\",\"input_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\","
      }) +
      "\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"source_ref\":\"source:local/first/rows\",\"version\":\"actql-local-input-schema/0.1\"}]"
    }
    let checked : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      second_stage=true,
      checked_results=checked,
      snapshot_entries=snapshots,
      second_steps="[{\"take\":1,\"as\":\"chosen\"}]",
      second_result_from="chosen",
    )
    let p = checked[0]
    definitions.push(unit_definition_cid(p, 0).unwrap())
    guard unit_input_completeness(p, 0, 0).unwrap().binding is Local(subject) else {
      fail("Local source requirement")
    }
    assert_eq(subject.snapshot is Some(_), claim != "absent")
    if subject.snapshot is Some(entry) {
      let snapshot = @snapshot.environment_snapshot(entry)
      let materialization = @snapshot.materialization(snapshot)
      assert_eq(
        materialization is Some(_),
        claim == "complete" || claim == "partial",
      )
      if materialization is Some(materialization) {
        assert_eq(
          materialization.completeness,
          if claim == "complete" {
            @snapshot.Complete
          } else {
            @snapshot.Partial
          },
        )
      }
      // Integrity and environment membership are retained, not interpreted as
      // successful raw input admission or observed whole-source coverage.
      assert_true(
        @context.local_input_execution_at(subject, 0).unwrap().kind ==
        RawBinding,
      )
    }
    let consumer = unit_pipeline(p, 1).unwrap()
    let output = @pipeline.completeness_requirement(consumer, Step(0)).unwrap()
    assert_eq(@pipeline.completeness_scope(output), BoundedQuery)
    let imported = @pipeline.completeness_dependency_at(output, 0).unwrap().requirement
    let producer = @pipeline.completeness_dependency_at(imported, 0).unwrap().requirement
    let source = @pipeline.completeness_dependency_at(producer, 0).unwrap().requirement
    assert_true(
      @pipeline.completeness_belongs_to(
        source,
        subject.pipeline,
        subject.target,
      ),
    )
  }
  for cid in definitions {
    assert_eq(cid, definitions[0])
  }
}
