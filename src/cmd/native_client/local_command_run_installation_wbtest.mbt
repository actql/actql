///|
let command_run_installation_fixture : String =
  #|{
  #|  "version": "actql-config/0.1",
  #|  "native": {
  #|    "run": {
  #|      "namespace_id": "local-example",
  #|      "store_name": "results",
  #|      "store_authority_cid": "sha256:8888888888888888888888888888888888888888888888888888888888888888",
  #|      "store_capacity_bytes": 1048576,
  #|      "store_objects": 8,
  #|      "store_record_bytes": 1048576,
  #|      "result_payload_bytes": 65536,
  #|      "retention_policy_wire": "{\"available_until\":\"2099-01-01T00:00:00.000Z\",\"clock_contract_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"effective_data_policy_cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"effective_retention_policy_cid\":\"sha256:eaa2bdcfc3048331c4cf99cce2f6a4fcd5d8baa7c56693df7940995abbc89027\",\"extension_ceiling_at\":\"2099-01-02T00:00:00.000Z\",\"metadata_delete_by\":\"2099-01-03T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"retention_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"version\":\"actql-result-retention-policy/0.1\"}"
  #|    }
  #|  }
  #|}

///|
test "command Run installation reuses only the exact selected DATA" {
  let original = local_command_run_installation_original(
    "run.json", command_run_installation_fixture,
  )
  let first = original.select("run.json", original.body).unwrap()
  let copied_body = @utf8.encode(command_run_installation_fixture)
  let second = original.select("run.json", copied_body).unwrap()
  assert_true(physical_equal(first, original.installation))
  assert_true(physical_equal(second, first))
  assert_true(physical_equal(second.retention, first.retention))
  assert_eq(first.namespace_id, "local-example")
  assert_eq(first.store_name, "results")
  assert_eq(first.result_payload_bytes, 65536L)
  assert_eq(
    @publication.publication_contract_identity(first.retention),
    "sha256:eaa2bdcfc3048331c4cf99cce2f6a4fcd5d8baa7c56693df7940995abbc89027",
  )
}

///|
test "command Run installation refuses changed bytes and foreign selection" {
  let original = local_command_run_installation_original(
    "run.json", command_run_installation_fixture,
  )
  assert_true(original.select("other.json", original.body) is None)
  assert_true(original.select("run.json", @utf8.encode("{}")) is None)
  assert_true(
    original.select(
      "run.json",
      @utf8.encode(command_run_installation_fixture + " "),
    )
    is None,
  )
}

///|
test "command Run installation refuses an invalid initial policy original" {
  let invalid = command_run_installation_fixture.replace(
    old="eaa2bdcfc3048331c4cf99cce2f6a4fcd5d8baa7c56693df7940995abbc89027",
    new="faa2bdcfc3048331c4cf99cce2f6a4fcd5d8baa7c56693df7940995abbc89027",
  )
  let issue = try {
    ignore(local_command_run_installation_original("run.json", invalid))
    "unexpected success"
  } catch {
    ClientStop(issue) => issue
  }
  assert_eq(issue, "InvalidLocalResultRetentionPolicy")
}

///|
test "Values publication keeps the empty payload refusal before opening work" {
  let original = local_command_run_installation_original(
    "run.json", command_run_installation_fixture,
  )
  let selected = original.select("run.json", original.body).unwrap()
  assert_eq(local_values_publication_payload_limit(selected), 65536)
  // A zero Store allocation is legal configuration DATA, but it cannot
  // publish a Values Result. Preserve the previous pre-Start refusal.
  let empty = { ..selected, result_payload_bytes: 0L, }
  let issue = try {
    ignore(local_values_publication_payload_limit(empty))
    "unexpected success"
  } catch {
    ClientStop(issue) => issue
  }
  assert_eq(issue, "LocalValuesPublicationLimit")
}
