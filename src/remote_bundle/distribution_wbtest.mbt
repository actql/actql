///|
fn hold_fixture_cid_a() -> String {
  "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

///|
fn hold_fixture_cid_b() -> String {
  "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}

///|
fn hold_fixture_distribution() -> RemoteBundleDistribution {
  prepare_bundle_distribution([hold_fixture_cid_a(), hold_fixture_cid_b()]).unwrap()
}

///|
test "bundle distribution matches independent canonical body and CID vectors" {
  let distribution = hold_fixture_distribution()
  assert_eq(
    bundle_distribution_json(distribution).unwrap(),
    hold_vector_distribution_body(),
  )
  assert_eq(
    bundle_distribution_identity(distribution),
    hold_vector_distribution_cid(),
  )
  let admitted = admit_bundle_distribution_json(
    hold_vector_distribution_body(),
    hold_vector_distribution_cid(),
  ).unwrap()
  assert_eq(bundle_distribution_projection(admitted), [
    hold_vector_distribution_cid(),
    hold_fixture_cid_a(),
    hold_fixture_cid_b(),
  ])
  assert_true(bundle_distribution_contains(admitted, hold_fixture_cid_a()))
  assert_false(bundle_distribution_contains(admitted, "not-a-cid"))
}

///|
test "bundle distribution sorts owned copies without exposing caller arrays" {
  let input = [hold_fixture_cid_b(), hold_fixture_cid_a()]
  let distribution = prepare_bundle_distribution(input).unwrap()
  assert_eq(input[0], hold_fixture_cid_b())
  input.clear()
  let projected = bundle_distribution_projection(distribution)
  projected[1] = hold_fixture_cid_b()
  projected.clear()
  assert_eq(
    bundle_distribution_json(distribution).unwrap(),
    hold_vector_distribution_body(),
  )
  assert_eq(
    bundle_distribution_identity(distribution),
    hold_vector_distribution_cid(),
  )
}

///|
test "bundle distribution rejects malformed duplicate unknown and noncanonical values" {
  for
    members in [
      [],
      [hold_fixture_cid_a(), hold_fixture_cid_a()],
      ["sha256:abc"],
      [hold_fixture_cid_a().replace(old="a", new="A")],
    ] {
    assert_true(prepare_bundle_distribution(members) is Err(InvalidBundle))
  }
  let body = hold_vector_distribution_body()
  for
    invalid in [
      " " + body,
      body.replace(old="{", new="{\"unknown\":true,"),
      body.replace(old="{", new="{\"runtime_bundle_cids\":[],"),
      body.replace(old="/0.1", new="/0.2"),
      body.replace(old=hold_fixture_cid_b(), new=hold_fixture_cid_a()),
      body.replace(
        old="[\"" +
          hold_fixture_cid_a() +
          "\",\"" +
          hold_fixture_cid_b() +
          "\"]",
        new="[\"" +
          hold_fixture_cid_b() +
          "\",\"" +
          hold_fixture_cid_a() +
          "\"]",
      ),
    ] {
    assert_true(
      admit_bundle_distribution_json(invalid, hold_vector_distribution_cid())
      is Err(InvalidBundle),
    )
  }
  assert_true(
    admit_bundle_distribution_json(body, hold_fixture_cid_a())
    is Err(BundleIdentityMismatch),
  )
}

///|
test "bundle distribution uses the control wire budget independently of physical components" {
  let members : Array[String] = []
  for index in 1000..<1884 {
    members.push(
      "sha256:000000000000000000000000000000000000000000000000000000000000" +
      index.to_string(),
    )
  }
  let distribution = prepare_bundle_distribution(members).unwrap()
  let body = bundle_distribution_json(distribution).unwrap()
  assert_eq(@utf8.encode(body).length(), 65498)
  assert_true(
    admit_bundle_distribution_json(
      body,
      bundle_distribution_identity(distribution),
    )
    is Ok(_),
  )
  members.push(
    "sha256:0000000000000000000000000000000000000000000000000000000000001884",
  )
  assert_true(prepare_bundle_distribution(members) is Err(InvalidBundle))
  assert_true(
    admit_bundle_distribution_json(
      body + body,
      bundle_distribution_identity(distribution),
    )
    is Err(InvalidBundle),
  )
}

///|
test "bundle distribution JSON detects internal identity and member tampering" {
  let distribution = hold_fixture_distribution()
  assert_true(
    bundle_distribution_json({
      ..distribution,
      distribution_cid: hold_fixture_cid_a(),
    })
    is Err(BundleIdentityMismatch),
  )
  distribution.runtime_bundle_cids[1] = hold_fixture_cid_a()
  assert_true(bundle_distribution_json(distribution) is Err(InvalidBundle))
}
