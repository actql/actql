///|
fn lookup_barrier_fixture(runtime : Bool) -> String {
  if runtime {
    (
      #|{"barrier_id":"lookup-0","capacity_guarantee":"complete","correlation":{"cardinality":"one","identity":["resource","version"],"null_request_policy":"fail","on":[{"request":"resource","response":"resource"},{"request":"version","response":"version"}],"on_duplicate_identity":"fail","on_excess_cardinality":"fail","on_missing":"fail","on_unrequested_key":"fail"},"correlation_fields":["resource","version"],"effective_output_classification":"internal","effective_output_data_policy_cid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","effective_request_classification":"internal","effective_request_data_policy_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","effective_response_classification":"internal","effective_response_data_policy_cid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","egress_requirements":{"kind":"not_required"},"input_artifact_fields":["resource","version"],"input_ref":"left.rows","lookup_execution_cid":"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","observed_response_fields":["resource","version","content"],"on_non_success":"fail","output_contract_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","output_ref":"acquired.rows","request_input_data_policy_cids":["sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"],"request_mapping":{"resource":{"field":"resource"},"version":{"field":"version"}},"request_schema_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","response_identity_fields":["resource","version"],"response_source_data_policy_cid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","source_input_ref":"drive.contents","source_view_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":"actql-lookup-barrier/0.1"}
    )
  } else {
    (
      #|{"barrier_id":"lookup-0","bounds":{"max_batches":2,"max_distinct_keys":2,"max_input_rows":2,"max_keys_per_batch":1,"max_network_attempts":2,"max_pages_per_batch":1,"max_request_bytes_per_attempt":128,"max_requests":2,"max_response_rows":2,"max_rows_per_key":1,"max_total_duration_ms":10000,"max_total_request_bytes":256,"max_total_response_bytes":4096},"capacity_guarantee":"complete","capacity_proof_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","correlation":{"cardinality":"one","identity":["resource","version"],"null_request_policy":"fail","on":[{"request":"resource","response":"resource"},{"request":"version","response":"version"}],"on_duplicate_identity":"fail","on_excess_cardinality":"fail","on_missing":"fail","on_unrequested_key":"fail"},"correlation_fields":["resource","version"],"effective_output_classification":"internal","effective_output_data_policy_cid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","effective_request_classification":"internal","effective_request_data_policy_cid":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","effective_response_classification":"internal","effective_response_data_policy_cid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","egress_requirements":{"kind":"not_required"},"input_artifact_fields":["resource","version"],"input_ref":"left.rows","observed_response_fields":["resource","version","content"],"on_non_success":"fail","output_contract_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","output_ref":"acquired.rows","request_input_data_policy_cids":["sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"],"request_mapping":{"resource":{"field":"resource"},"version":{"field":"version"}},"request_schema_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","response_identity_fields":["resource","version"],"response_source_data_policy_cid":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","source_input_ref":"drive.contents","source_view_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","version":"actql-lookup-barrier/0.1"}
    )
  }
}

///|
test "runtime lookup barrier retains original policy and static instance identity without a count proof" {
  for
    (runtime, expected) in [
      (
        false, "sha256:23db07593b5cce1a95b56be8345f78da6b1e7292104957bc04db91628c113b56",
      ),
      (
        true, "sha256:764aa786c4ab1fde7c9dd749754f1aecf44bf5edaf007ef440334bf1712951ca",
      ),
    ] {
    let barrier = seal_publication_contract(
      "lookup_barrier",
      lookup_barrier_fixture(runtime),
      16384,
      2048,
      32,
    ).unwrap()
    assert_eq(barrier.identity, expected)
    assert_eq(
      admit_publication_contract(
        "lookup_barrier",
        barrier.wire,
        16384,
        2048,
        32,
      ).unwrap().identity,
      expected,
    )
    assert_eq(barrier.wire.contains("lookup_execution_cid"), runtime)
    assert_eq(barrier.wire.contains("capacity_proof_cid"), !runtime)
    assert_eq(barrier.wire.contains("max_distinct_keys"), !runtime)
  }
}

///|
test "runtime lookup barrier refuses mixed proof maxima missing policy and incomplete semantics" {
  let runtime = lookup_barrier_fixture(true)
  for
    changed in [
      runtime.replace(
        old="\"lookup_execution_cid\"",
        new="\"capacity_proof_cid\"",
      ),
      runtime.replace(
        old="\"capacity_guarantee\":\"complete\"",
        new="\"capacity_guarantee\":\"hard_limit_only\"",
      ),
      runtime.replace(old="\"input_ref\":", new="\"bounds\":{},\"input_ref\":"),
      runtime.replace(
        old="\"input_ref\":",
        new="\"capacity_proof_cid\":\"sha256:" +
          "1".repeat(64) +
          "\",\"input_ref\":",
      ),
      runtime.replace(
        old="\"lookup_execution_cid\":\"sha256:",
        new="\"lookup_execution_cid\":\"not-a-cid:",
      ),
      runtime.replace(
        old="\"on_missing\":\"fail\"",
        new="\"on_missing\":\"guess\"",
      ),
    ] {
    assert_true(
      seal_publication_contract("lookup_barrier", changed, 16384, 2048, 32)
      is Err(_),
    )
  }
  assert_true(
    seal_publication_contract("lookup_barrier", runtime, 1, 2048, 32) is Err(_),
  )
}

///|
test "runtime lookup barrier preserves unknown policy DATA without changing static or Model admission" {
  let mut runtime = lookup_barrier_fixture(true)
  let mut original_static = lookup_barrier_fixture(false)
  for
    field in [
      "effective_request_classification", "effective_response_classification", "effective_output_classification",
    ] {
    let old = "\"" + field + "\":\"internal\""
    let replacement = "\"" + field + "\":\"unknown\""
    runtime = runtime.replace(old~, new=replacement)
    original_static = original_static.replace(old~, new=replacement)
  }
  let data = seal_publication_contract(
    "lookup_barrier", runtime, 16384, 2048, 32,
  ).unwrap()
  // Independent standard-library SHA256 of the authored whole preimage.
  assert_eq(
    data.identity,
    "sha256:69317ca2211933e0acd501d64039b7965feef2e18b63b70a8eaa625f0258f9fb",
  )
  assert_eq(
    admit_publication_contract("lookup_barrier", data.wire, 16384, 2048, 32).unwrap().identity,
    data.identity,
  )
  assert_true(
    data.wire.contains("\"effective_request_classification\":\"unknown\""),
  )
  // Unknown is preserved, not replaced by a default or a static count proof.
  assert_true(
    seal_publication_contract(
      "lookup_barrier", original_static, 16384, 2048, 32,
    )
    is Err(_),
  )
}
