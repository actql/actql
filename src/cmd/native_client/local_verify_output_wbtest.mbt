///|
fn output_verification_fixture(name : String) -> String raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_OUTPUT_VERIFY_ROOT") is Some(root) else {
    fail(
      "selected output verification requires its own canonical fixture directory",
    )
  }
  root + "/" + name
}

///|
fn output_verification_child(
  receipt : String,
  output : String,
) -> @argparse.Matches raise {
  guard command().parse(argv=[
      "verify",
      "output",
      output_verification_fixture(receipt),
      output_verification_fixture(output),
      "--json",
    ]).subcommand
    is Some(("verify", child)) else {
    fail("verify output parse")
  }
  child
}

///|
test "public output verification reads an actual singleton file and closes its original Readers" {
  let wire = local_verify_output_command(
    output_verification_child("single.json", "data.bin"),
  )
  let report = @decode.open_object(local_input_cursor(wire)).unwrap()
  assert_eq(
    @decode.boolean(@decode.required(report, "verified").unwrap()).unwrap(),
    true,
  )
  assert_eq(
    @decode.safe_integer(
      @decode.required(report, "matching_receipt_count").unwrap(),
    ).unwrap(),
    1L,
  )
  assert_eq(output_verification_files.val.length(), 2)
  local_finish_output_verification().unwrap()
  assert_true(output_verification_files.val.is_empty())
}

///|
test "public output verification reports all equal-byte receipt identities" {
  let wire = local_verify_output_command(
    output_verification_child("multiple.json", "data.bin"),
  )
  let report = @decode.open_object(local_input_cursor(wire)).unwrap()
  let ids = @decode.elements(@decode.required(report, "receipt_cids").unwrap())
    .unwrap()
    .map(value => @decode.text(value).unwrap())
  assert_eq(ids, [
    "sha256:653b739f7a85f39a048ed77fe1d38f8fc5e1edcf1ab50a867a83216e76a1d146", "sha256:18ac1e0d8d953ef2f6de009ebab351f57701ce6bf8396f277b8f8d8443df0403",
  ])
  assert_eq(
    @decode.safe_integer(
      @decode.required(report, "matching_receipt_count").unwrap(),
    ).unwrap(),
    2L,
  )
  assert_eq(
    @decode.safe_integer(
      @decode.required(report, "supplied_receipt_count").unwrap(),
    ).unwrap(),
    4L,
  )
  local_finish_output_verification().unwrap()
}

///|
test "public output verification rejects an invalid unrelated receipt before output acquisition" {
  let issue = try {
    ignore(
      local_verify_output_command(
        output_verification_child("invalid.json", "data.bin"),
      ),
    )
    "unexpected acceptance"
  } catch {
    ClientStop(issue) => issue
  }
  assert_eq(issue, "InvalidResultDeliveryReceiptContainer")
  assert_eq(output_verification_files.val.length(), 1)
  local_finish_output_verification().unwrap()
}

///|
test "public output verification rejects tampered output and empty collection with original cleanup" {
  for
    (receipt, output, opened) in [
      ("single.json", "changed.bin", 2),
      ("empty.json", "data.bin", 1),
    ] {
    let issue = try {
      ignore(
        local_verify_output_command(output_verification_child(receipt, output)),
      )
      "unexpected acceptance"
    } catch {
      ClientStop(issue) => issue
    }
    assert_eq(issue, "ResultDeliveryReceiptOutputMismatch")
    assert_eq(output_verification_files.val.length(), opened)
    local_finish_output_verification().unwrap()
  }
}
