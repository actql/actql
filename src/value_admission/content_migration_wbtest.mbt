///|
test "ContentRef migration refuses the actual former envelope before issuer access" {
  // Preserved from 80ca8ab23202cde18123e9a1a790bb7c5f308aa8. This is
  // a prior shape fixture, not signed authority or a regenerated new Ref.
  let old = "{\"$actql_ref\":\"artifact\",\"artifact_ref_cid\":\"sha256:15e902418023a2de574d29d716f3b643825e19afa1fa3a5a46e049ffb1606eff\",\"media_type\":\"application/json\",\"metadata\":{\"artifact_store_id\":\"fixture\",\"availability_evidence_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"capture_authority\":\"read_content\",\"content_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"issuer_evidence\":{},\"media_type\":\"application/json\",\"retention_class\":\"fixture\",\"size_bytes\":3,\"storage_scope\":\"workspace\",\"truncated\":false},\"version\":\"actql-artifact-ref/0.1\"}"
  let validations = Ref(0)
  let authorizations = Ref(0)
  let issuer = bind_reference_issuer(
    (_, _) => {
      validations.val += 1
      true
    },
    _ => {
      authorizations.val += 1
      true
    },
  )
  let contract = reference_contract(
    "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
  )
  assert_true(
    issue_reference(issuer, contract, old, reference_limits())
    is Err(ContractMismatch),
  )
  assert_eq(validations.val, 0)
  assert_eq(authorizations.val, 0)
}

///|
test "ContentRef shape is not issuance and reread checks current authority" {
  let wire = content_reference_wire()
  let contract = reference_contract(
    "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
  )
  assert_true(
    issue_reference(
      bind_reference_issuer((_, _) => false, _ => true),
      contract,
      wire,
      reference_limits(),
    )
    is Err(IssuerRejected),
  )
  let live = Ref(true)
  let issued = issue_reference(
    bind_reference_issuer((_, candidate) => candidate == wire, _ => live.val),
    contract,
    wire,
    reference_limits(),
  ).unwrap()
  guard issued.value is Reference(original) else { abort("ContentRef") }
  let reissuer = bind_reference_reissuer((required, candidate) => {
    if candidate == wire && reference_compatible(original, required) {
      Some(original)
    } else {
      None
    }
  })
  assert_true(
    issue_reference(reissuer, contract, wire, reference_limits()) is Ok(_),
  )
  live.val = false
  assert_true(
    issue_reference(reissuer, contract, wire, reference_limits())
    is Err(Unauthorized),
  )
  assert_true(!reference_available(original))
}
