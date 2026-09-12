///|
fn recursive_values_rows(
  field : String,
  declaration : String,
  data : String,
  bytes : Int,
  depth : Int,
  schema? : String? = None,
) -> ValuesRowLimit {
  let profile_body = capacity_profile(false)
    .replace(
      old="\"max_nested_value_bytes\":1",
      new="\"max_nested_value_bytes\":" + bytes.to_string(),
    )
    .replace(
      old="\"max_nested_value_depth\":1",
      new="\"max_nested_value_depth\":" + depth.to_string(),
    )
  let policy_body = profile_body[12:profile_body.length() - 1].to_owned()
  let capacity_policy = @policy.admit(
    @utf8.encode(policy_body),
    "sha256:" + @sha.hex(@utf8.encode(policy_body)),
    { max_bytes: 4000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let host_profile = bound_profile()
    .replace(
      old="\"max_nested_value_bytes\":1",
      new="\"max_nested_value_bytes\":" + bytes.to_string(),
    )
    .replace(
      old="\"max_nested_value_depth\":1",
      new="\"max_nested_value_depth\":" + depth.to_string(),
    )
  let cells = check_program_operation_cells(
    cells_fixture(
      field,
      declaration,
      data,
      host_profile~,
      capacity_policy~,
      schema~,
    ),
    10000000,
    100,
  ).unwrap()
  let limits : @wire.LimitLimits = {
    max_bytes: 4000,
    max_nodes: 1000,
    max_depth: 20,
    max_candidates: 2,
  }
  resolve_values_row_limit(
    resolve_values_wire_limit(
      cells,
      0,
      { max_bytes: 4000, max_nodes: 1000, max_depth: 20, },
      limits,
    ).unwrap(),
    limits,
  ).unwrap()
}

///|
test "recursive values check repeated nullable and vector cells under exact policy" {
  for
    (field, declaration, data, bytes, depth) in [
      (
        "{\"type\":\"string\",\"nullable\":false}", "{\"type\":\"string\",\"default\":\"large scalar\"}",
        "[{\"x\":{\"$param\":\"n\"}}]", 0, 0,
      ),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"default\":[1,2]}",
        "[{\"x\":{\"$param\":\"n\"}},{\"x\":{\"$param\":\"n\"}}]", 10, 1,
      ),
      (
        "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\"},\"default\":null}",
        "[{\"x\":{\"$param\":\"n\"}}]", 4, 1,
      ),
      (
        "{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}", "{\"type\":\"number\",\"default\":7}",
        "[{\"x\":[1,2]}]", 5, 1,
      ),
    ] {
    let rows = recursive_values_rows(
      field,
      declaration,
      data,
      bytes.max(1),
      depth.max(1),
    )
    let result = check_values_recursive_resources(rows, 1000, bytes, depth).unwrap()
    assert_eq((result.bytes, result.type_depth), (bytes, depth))
    assert_true(physical_equal(result.rows, rows))
    assert_true(
      physical_equal(
        @policy.ceiling_policy(result.byte_ceiling),
        rows.wire.policy,
      ),
    )
    assert_true(
      physical_equal(
        @policy.ceiling_policy(result.depth_ceiling),
        rows.wire.policy,
      ),
    )
    assert_true(
      check_values_recursive_resources(rows, result.work, bytes, depth) is Ok(_),
    )
    assert_true(
      check_values_recursive_resources(rows, result.work - 1, bytes, depth)
      is Err(_),
    )
    if bytes > 0 {
      assert_true(
        check_values_recursive_resources(rows, 1000, bytes - 1, depth) is Err(_),
      )
      let short = recursive_values_rows(
        field,
        declaration,
        data,
        bytes - 1,
        depth,
      )
      assert_true(
        check_values_recursive_resources(short, 1000, bytes, depth)
        is Err(BytesExceeded),
      )
    }
    for
      (work, bytes, depth) in [(-1, 1000, 20), (1000, -1, 20), (1000, 1000, -1)] {
      assert_true(
        check_values_recursive_resources(rows, work, bytes, depth)
        is Err(InvalidLimits),
      )
    }
  }
}

///|
test "declared recursive depth survives empty rows and containers without double byte counting" {
  let field = "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"a\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}}"
  let declaration = "{\"type\":\"object\",\"fields\":{\"a\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}},\"default\":{\"a\":[1]}}"
  for (data, bytes) in [("[]", 0), ("[{\"x\":{\"$param\":\"n\"}}]", 9)] {
    let rows = recursive_values_rows(field, declaration, data, bytes.max(1), 2)
    let result = check_values_recursive_resources(rows, 1000, bytes, 2).unwrap()
    assert_eq(
      (result.bytes, result.type_depth, result.selected_fields),
      (bytes, 2, 1),
    )
    let short = recursive_values_rows(field, declaration, data, bytes.max(1), 1)
    assert_true(
      check_values_recursive_resources(short, 1000, bytes, 2)
      is Err(DepthExceeded),
    )
    assert_true(
      check_values_recursive_resources(rows, 1000, bytes, 1)
      is Err(BudgetExceeded),
    )
  }
}

///|
test "sibling structured cells share the recursive ceiling without row keys" {
  let schema = "{\"a\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}},\"b\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"string\",\"nullable\":false}}}}"
  for ceiling in [11, 12] {
    let rows = recursive_values_rows(
      "{\"type\":\"number\",\"nullable\":false}",
      "{\"type\":\"number\",\"default\":7}",
      "[{\"a\":[],\"b\":{\"x\":\"é\"}}]",
      ceiling,
      1,
      schema=Some(schema),
    )
    let result = check_values_recursive_resources(rows, 1000, 12, 1)
    if ceiling == 12 {
      let admitted = result.unwrap()
      assert_eq(
        (admitted.bytes, admitted.type_depth, admitted.selected_fields),
        (12, 1, 2),
      )
    } else {
      assert_true(result is Err(BytesExceeded))
    }
  }
}
