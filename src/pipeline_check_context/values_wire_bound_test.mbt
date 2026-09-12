///|
fn values_wire_claim(
  count : Int,
  law? : String = "actql.bound.values-wire",
  unit? : String = "bytes",
  step? : Int = 0,
  input? : String? = None,
) -> @wire.ProgramProofClaim {
  let subject = "checked-step:" + step.to_string()
  let inputs = match input {
    None => "[]"
    Some(cid) => "[\"" + cid + "\"]"
  }
  let proof = "{\"inputs\":" +
    inputs +
    ",\"law_id\":\"" +
    law +
    "\",\"semantic_ref\":\"" +
    subject +
    "\",\"unit\":\"" +
    unit +
    "\",\"value\":" +
    count.to_string() +
    ",\"version\":\"actql-bound-proof/0.1\"}"
  let proof_cid = "sha256:" + @sha.hex(@utf8.encode(proof))
  let dependencies = match input {
    None => "[\"" + proof_cid + "\"]"
    Some(cid) =>
      if cid < proof_cid {
        "[\"" + cid + "\",\"" + proof_cid + "\"]"
      } else {
        "[\"" + proof_cid + "\",\"" + cid + "\"]"
      }
  }
  let body = "{\"dependencies\":" +
    dependencies +
    ",\"derivation\":{\"op\":\"source\"},\"law_id\":\"" +
    law +
    "\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
    proof_cid +
    "\",\"semantic_ref\":\"" +
    subject +
    "\"},\"unit\":\"" +
    unit +
    "\",\"value\":" +
    count.to_string() +
    ",\"version\":\"actql-bound-witness/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let limits : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }
  @wire.bind_program_proof(
    @utf8.encode(proof),
    @wire.admit(
      @utf8.encode(
        body[:body.length() - 1].to_owned() +
        ",\"witness_cid\":\"" +
        cid +
        "\"}",
      ),
      cid,
      limits,
    ).unwrap(),
    limits,
  ).unwrap()
}

///|
fn wire_bound_cells(
  supplied? : @decode.Cursor? = None,
) -> ProgramOperationCells {
  check_program_operation_cells(
    cells_fixture(
      "{\"type\":\"number\",\"nullable\":false}",
      "{\"type\":\"number\",\"default\":7}",
      "[{\"x\":{\"$param\":\"n\"}},{\"x\":1},{\"x\":{\"$param\":\"n\"}}]",
      supplied~,
    ),
    10000000,
    100,
  ).unwrap()
}

///|
test "values wire application recomputes the fixed proof under its exact owner" {
  let cells = wire_bound_cells()
  let proof = values_wire_claim(25)
  assert_eq(
    @wire.cid(@wire.program_proof_witness(proof)),
    "sha256:15622500b68d7891fc269aca0d7cb37561307a912578cd88f3d2dadcc54fb56e",
  )
  let applied = check_values_wire_bound(cells, 0, proof, 25, 7, 2).unwrap()
  assert_true(physical_equal(applied.cells, cells))
  assert_true(physical_equal(applied.proof, proof))
  assert_eq((applied.bytes, applied.nodes, applied.depth), (25, 7, 2))
  assert_eq(
    values_wire_bound_contract(applied),
    "sha256:aa0833e19bbf9be3ccfc445e9bebc55c57ce8b8151bc143d1220da4d17a61168",
  )
  let changed = wire_bound_cells(supplied=Some(cursor("{\"n\":100}")))
  assert_true(
    check_values_wire_bound(changed, 0, proof, 100, 100, 10)
    is Err(ValueMismatch),
  )
  let other = wire_bound_cells(supplied=Some(cursor("{\"n\":9}")))
  let other_bound = check_values_wire_bound(other, 0, proof, 25, 7, 2).unwrap()
  // Equal measurements may both validate a claim; their applied owners remain
  // distinct and cannot be substituted by comparing the proof CID alone.
  assert_false(physical_equal(other_bound.cells, applied.cells))
  assert_false(physical_equal(other_bound.site, applied.site))
}

///|
test "values wire application rejects wrong law unit subject value and budget" {
  let cells = wire_bound_cells()
  assert_true(
    check_values_wire_bound(
      cells,
      0,
      values_wire_claim(25, law="actql.bound.values"),
      100,
      100,
      10,
    )
    is Err(LawMismatch),
  )
  assert_true(
    check_values_wire_bound(
      cells,
      0,
      values_wire_claim(25, unit="rows"),
      100,
      100,
      10,
    )
    is Err(LawMismatch),
  )
  assert_true(
    check_values_wire_bound(
      cells,
      0,
      values_wire_claim(25, step=1),
      100,
      100,
      10,
    )
    is Err(SubjectMismatch),
  )
  assert_true(
    check_values_wire_bound(cells, 0, values_wire_claim(24), 100, 100, 10)
    is Err(ValueMismatch),
  )
  assert_true(
    check_values_wire_bound(
      cells,
      0,
      values_wire_claim(25, input=Some("sha256:" + "0".repeat(64))),
      100,
      100,
      10,
    )
    is Err(InvalidProof),
  )
  let proof = values_wire_claim(25)
  for (bytes, nodes, depth) in [(24, 7, 2), (25, 6, 2), (25, 7, 1)] {
    assert_true(
      check_values_wire_bound(cells, 0, proof, bytes, nodes, depth)
      is Err(Measurement(Encoding(@encode.OutputLimit))),
    )
  }
  for index in [-1, 1, 10000] {
    assert_true(
      check_values_wire_bound(cells, index, proof, 25, 7, 2)
      is Err(Measurement(InvalidRequirement)),
    )
  }
}

///|
test "empty values have a two-byte wire proof rather than the zero-row proof" {
  let cells = check_program_operation_cells(
    cells_fixture(
      "{\"type\":\"number\",\"nullable\":false}", "{\"type\":\"number\",\"default\":7}",
      "[]",
    ),
    10000000,
    0,
  ).unwrap()
  let bound = check_values_wire_bound(cells, 0, values_wire_claim(2), 2, 1, 1).unwrap()
  assert_eq((bound.bytes, bound.nodes, bound.depth), (2, 1, 1))
  assert_true(
    check_values_wire_bound(cells, 0, values_wire_claim(0), 2, 1, 1)
    is Err(ValueMismatch),
  )
}
