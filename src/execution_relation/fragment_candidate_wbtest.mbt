///|
// Test-only complete-envelope emission; production uses admitted material.
fn emit_fragment_candidate(
  candidate : FragmentCandidate,
  limits : RegistryLimits,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_fragment_candidate_body(
    candidate.material,
    limits,
    Some(candidate.artifact.cid),
    out,
  )
}

///|
fn test_fragment_contract() -> FragmentContract raise {
  admit_fragment_contract(
    registered_relation_contracts(),
    registered_fragment(),
    registry_limits(),
  ).unwrap()
}

///|
test "fragment registration hashes the exact body rather than accepting a CID claim" {
  let relations = registered_relation_contracts()
  let limits = registry_limits()
  let accepted = admit_fragment_contract(
    relations,
    registered_fragment(),
    limits,
  ).unwrap()
  assert_true(physical_equal(accepted.relations, relations))
  assert_eq(accepted.cid, selected_fragment_contract_cid)
  assert_true(
    admit_fragment_contract(relations, registered_values(), limits)
    is Err(ContractMismatch),
  )
  assert_true(
    admit_fragment_contract(relations, registered_fragment(), {
      ..limits,
      max_body_bytes: 1,
    })
    is Err(BodyLimit),
  )
}

///|
test "complete fragment candidate matches independently constructed contract vector" {
  let material = prepare_fragment_material(
    artifact_request("{\"literal\":7}", 10L),
    material_demands(),
    registry_limits(),
  ).unwrap()
  let contract = test_fragment_contract()
  let candidate = prepare_fragment_candidate(
    contract,
    material,
    registry_limits(),
  ).unwrap()
  assert_true(physical_equal(candidate.material, material))
  assert_true(physical_equal(candidate.contract, contract))
  // Independently built from the specified request/graph/root/limit forms and
  // hashed with Python hashlib, not obtained from product output. The complete
  // fixed body is in portability/corpus/expression-fragment-identities.json.
  assert_eq(
    candidate.artifact.cid,
    "sha256:cb951447c0b929beed22554835c2e3817aeb8b943d181e01b0c0e8a4a630ae7e",
  )
  assert_eq(candidate.artifact.bytes, 2774)
  assert_true(
    prepare_fragment_candidate(contract, material, {
      ..registry_limits(),
      max_body_bytes: 2774,
    })
    is Ok(_),
  )
  assert_true(
    prepare_fragment_candidate(contract, material, {
      ..registry_limits(),
      max_body_bytes: 2773,
    })
    is Err(OutputLimit),
  )
  let out = @encode.writer(10000, 10000, 100)
  emit_fragment_candidate(candidate, registry_limits(), out)
  let text = @encode.finish(out)
  let body = @json.parse(text)
  match body {
    Object(fields) => {
      match fields.get("fragment_cid") {
        Some(String(cid)) => assert_eq(cid, candidate.artifact.cid)
        _ => fail("missing fragment identity")
      }
      let _ = fields.remove("fragment_cid")
      let preimage = @identity.from_json(body, 10000, 100, 10000)
      assert_eq(
        @identity.cid_value(preimage, 10000, 10000, 100),
        candidate.artifact.cid,
      )
      assert_eq(
        @identity.stringify_value(preimage, 10000, 10000, 100),
        @identity.stringify_value(candidate.artifact.value, 10000, 10000, 100),
      )
    }
    _ => fail("expected complete fragment")
  }
  let short = @encode.writer(text.length() - 1, 10000, 100)
  let rejected = try {
    emit_fragment_candidate(candidate, registry_limits(), short)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
