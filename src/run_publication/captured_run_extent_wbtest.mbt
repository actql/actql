///|
// Private constructor-level fixture only, not an admitted public Run chain.
fn extent_metadata_fixture() -> PublicationContract {
  let wire = "{\"n\":1}"
  {
    name: "fixture",
    identity_field: "cid",
    identity: "fixture",
    wire,
    value: parse_contract_wire(wire, 100, 10, 4).unwrap(),
    wire_usage: Some((7, 2, 1)),
  }
}

///|
test "captured context extent counts repeated snapshot occurrences and row-shaped work" {
  let metadata = extent_metadata_fixture()
  let authoring : RunEvidenceValue = {
    name: "authoring_context",
    identity: "fixture",
    wire: metadata.wire,
    value: metadata.value,
  }
  for count in [0, 10001, 100000] {
    let wire = "[" + Array::make(count, "{\"n\":1}").join(",") + "]"
    let value = parse_contract_wire(wire, 2000000, 300001, 4).unwrap()
    let snapshot : CapturedResultSnapshot = {
      name: "answer",
      definition: metadata,
      artifact: metadata,
      rows: value,
      fields: ["n"],
      row_wire_bytes: wire.length(),
      row_nodes: 1 + 2 * count,
      row_depth: if count == 0 {
        1
      } else {
        2
      },
    }
    assert_true(
      captured_plain_run_extent(
        metadata,
        [{ ..snapshot, row_nodes: 0, }],
        authoring,
        [],
      )
      is None,
    )
    assert_true(
      captured_plain_run_extent(
        metadata,
        [{ ..snapshot, row_wire_bytes: 2147483647, }],
        authoring,
        [],
      )
      is None,
    )
    let one = captured_plain_run_extent(metadata, [snapshot], authoring, []).unwrap()
    let repeated = { ..snapshot, name: "other", }
    let twice = captured_plain_run_extent(
      metadata,
      [snapshot, repeated],
      authoring,
      [],
    ).unwrap()
    assert_true(twice.0 >= one.0 + wire.length())
    assert_true(twice.1 >= one.1 + snapshot.row_nodes)
    let context = start_effect_context_preparation(
      [snapshot],
      [],
      [],
      { bodies: [], wire: "[]", },
      [],
      authoring,
      [],
      None,
      [],
      one.0,
      one.1,
      one.2,
      publication_evidence_workspace(one.1),
    ).unwrap()
    let mut done = false
    for _ in 0..<100000 {
      if context.advance(256).unwrap().0 {
        done = true
        break
      }
    }
    assert_true(done)
    let body = context.finish().unwrap()
    let writer = @encode.measuring_writer(one.0, one.1, one.2) catch {
      _ => abort("invalid extent")
    }
    @json.emit_value(body, writer) catch {
      _ => abort("context exceeded extent")
    }
    let (bytes, nodes, depth) = @encode.finish_measurement_usage(writer) catch {
      _ => abort("measurement failed")
    }
    assert_true(bytes <= one.0 && nodes <= one.1 && depth <= one.2)
    if count == 100000 {
      assert_true(nodes > 100000)
      let old = start_effect_context_preparation(
        [snapshot],
        [],
        [],
        { bodies: [], wire: "[]", },
        [],
        authoring,
        [],
        None,
        [],
        1000000,
        100000,
        64,
        publication_evidence_workspace(100000),
      ).unwrap()
      let mut refused = false
      for _ in 0..<100000 {
        match old.advance(256) {
          Err(CaptureIssuanceEncoding) => {
            refused = true
            break
          }
          Ok((false, _)) => ()
          _ => break
        }
      }
      assert_true(refused)
    }
  }
}
