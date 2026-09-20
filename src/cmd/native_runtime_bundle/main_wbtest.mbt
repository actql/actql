///|
fn snapshot_fixture(index : Int) -> @runtime_bundle.NativeRuntimeBundleSnapshot {
  {
    runtime_bundle_cid: "sha256:" + index.to_string(),
    manifest_json: "{}",
    artifact_name: "bundle-" + index.to_string(),
    generation: { device: 1UL, inode: index.to_uint64(), size: 1L, },
    state: ["0", "0", "0"],
    reclaim_pending: false,
  }
}

///|
test "bundle snapshot list budgets its complete JSON shape" {
  for count in [0, 1, 12, 13, 128] {
    let values = Array::makei(count, snapshot_fixture)
    let expected_nodes = 1 + 13 * count
    assert_eq(snapshots_node_limit(values), Ok(expected_nodes))
    guard snapshots_output_limit(count) is Ok(bytes) else {
      fail("valid output size was rejected")
    }
    guard write_snapshots_with_limits(values, bytes, expected_nodes) is Ok(body) else {
      fail("exact node budget was rejected")
    }
    if count == 0 {
      assert_eq(body, "[]")
    } else {
      assert_true(body.has_prefix("["))
      assert_true(body.has_suffix("]"))
      for index in 0..<count {
        assert_true(
          body.contains(
            "\"artifact_name\":\"bundle-" + index.to_string() + "\"",
          ),
        )
      }
    }
    if expected_nodes > 0 {
      assert_eq(
        write_snapshots_with_limits(values, bytes, expected_nodes - 1),
        Err("result encoding failed"),
      )
    }
  }
}
