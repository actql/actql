///|
fn fragment_output_contract_fixture() -> @contract.Contract {
  let prepared = values_compilation_parts_prepared()
  let owner = @strategy.graph_task_owner(prepared_client_graph(prepared), 0).unwrap()
  @schema.as_object(
    @lower.node_output_schema(
      @lower.node_at(@lower.bound_preparation(owner), 0).unwrap(),
    ),
  ).unwrap()
}

///|
test "fragment output contract emits checked fields once for text and hash" {
  let row = fragment_output_contract_fixture()
  let calls = Ref(0)
  let emit = (row, writer) => {
    calls.val += 1
    @contract.emit_checked(row, writer)
  }
  let (wire, cid) = client_values_fragment_output_contract(
    row,
    10000,
    1000,
    20,
    emit~,
  )
  assert_eq(
    wire, "{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}",
  )
  assert_eq(
    cid, "sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c",
  )
  assert_eq(calls.val, 1)
}

///|
fn fragment_output_previous_emission(
  row : @contract.Contract,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> (String, String) raise @encode.EncodeFailure {
  let hash = @encode.hashing_writer(bytes, nodes, depth)
  let text = @encode.writer(bytes, nodes, depth)
  @contract.emit_checked(row, hash)
  @contract.emit_checked(row, text)
  let cid = "sha256:" + @encode.finish_hash(hash)
  (@encode.finish(text), cid)
}

///|
fn fragment_output_nested_contract() -> @contract.Contract {
  let source = @source.parse_json(
    (
      #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"é😀":{"type":"array","nullable":true,"items":{"type":"string","nullable":false,"enum":["é","😀"]},"max_items":3}}}
    ),
    { max_input_bytes: 10000, max_nodes: 1000, max_depth: 20, },
  ).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 1000,
    max_depth: 20,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  @contract.read_checked(cursor, {
    max_nodes: 1000,
    max_depth: 20,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
test "single fragment output emission keeps exact prior bytes digest and all boundary failures" {
  for
    row in [
      fragment_output_contract_fixture(),
      fragment_output_nested_contract(),
    ] {
    let prior = fragment_output_previous_emission(row, 10000, 1000, 20)
    assert_eq(
      client_values_fragment_output_contract(row, 10000, 1000, 20),
      prior,
    )
    let measure = @encode.hashing_writer(10000, 1000, 20)
    @contract.emit_checked(row, measure)
    let (_, bytes, nodes, depth) = @encode.finish_hash_metrics(measure)
    assert_eq(
      client_values_fragment_output_contract(row, bytes, nodes, depth),
      prior,
    )
    assert_eq(prior.1, "sha256:" + @sha.text_hex(prior.0).unwrap())
    for
      (b, n, d) in [
        (bytes - 1, nodes, depth),
        (bytes, nodes - 1, depth),
        (bytes, nodes, depth - 1),
        (-1, nodes, depth),
        (bytes, 0, depth),
      ] {
      assert_true(
        try {
          ignore(client_values_fragment_output_contract(row, b, n, d))
          false
        } catch {
          @encode.OutputLimit => true
          _ => false
        },
      )
      assert_true(
        try {
          ignore(fragment_output_previous_emission(row, b, n, d))
          false
        } catch {
          @encode.OutputLimit => true
          _ => false
        },
      )
    }
  }
}

///|
test "interrupted fragment output emission exposes no completed text or hash" {
  let row = fragment_output_contract_fixture()
  assert_true(
    try {
      ignore(
        client_values_fragment_output_contract(row, 10000, 1000, 20, emit=(
          _,
          writer,
        ) => {
          @encode.begin_object(writer)
          @encode.key(writer, "partial")
          raise @encode.InvalidStructure
        }),
      )
      false
    } catch {
      @encode.InvalidStructure => true
      _ => false
    },
  )
  // A partial but non-raising emitter still cannot publish its provisional text.
  assert_true(
    try {
      ignore(
        client_values_fragment_output_contract(row, 10000, 1000, 20, emit=(
          _,
          writer,
        ) => @encode.begin_object(writer)),
      )
      false
    } catch {
      @encode.InvalidStructure => true
      _ => false
    },
  )
  assert_eq(
    client_values_fragment_output_contract(row, 10000, 1000, 20),
    fragment_output_previous_emission(row, 10000, 1000, 20),
  )
}

///|
test "actual Values compiler retains independent complete output contract identity" {
  let prepared = values_compilation_parts_prepared()
  let limits = prepared_client_values_sequence_limits(prepared)
  let compiled = issue_prepared_client_values_compilation(
    prepared,
    run_materials_manifests(),
    limits,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(
    compiled.fragment.output_contract_wire,
    "{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}",
  )
  assert_eq(
    compiled.fragment.output_contract_cid,
    "sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c",
  )
}
