///|
test "original local effect selection requires both explicit scoped and disjoint key roles" {
  let reviewer = "{\"version\":\"actql-config/0.1\",\"native\":{\"effect_reviewer\":{\"enabled\":true,\"principal\":\"original-local\",\"connection\":\"local\",\"key_id\":\"reviewer-key\",\"reviewer_id\":\"named-reviewer\",\"public_key_pem\":\"reviewer-pem\"}}}"
  let host = "{\"version\":\"actql-config/0.1\",\"native\":{\"signing_key\":{\"enabled\":true,\"purpose\":\"host_attestation\",\"principal\":\"original-local\",\"connection\":\"local\",\"resource\":\"key/initial-host-attestation\",\"key_id\":\"host-key\",\"private_key_file\":\"key.pem\",\"public_key_pem\":\"host-pem\",\"checkpoint_kinds\":[\"effect_set\"]}}}"
  let select = (reviewer, host) => {
    admit_client_local_effect_approval_selection(
      reviewer, host, "original-local", "local",
    )
  }
  let subject = admit_client_local_effect_attestation_selection(
    host, "original-local", "local",
  ).unwrap()
  assert_eq(subject.resource, "key/initial-host-attestation")
  assert_eq(subject.key_id, "host-key")
  assert_true(
    admit_client_local_effect_attestation_selection(host, "other", "local")
    is None,
  )
  assert_true(
    admit_client_local_effect_attestation_selection(
      reviewer, "original-local", "local",
    )
    is None,
  )
  let selected = select(reviewer, host).unwrap()
  assert_eq(selected.registration.key_id, "reviewer-key")
  assert_eq(selected.host_key_id, "host-key")
  assert_eq(selected.private_key_file, "key.pem")
  assert_true(
    select(reviewer, host.replace_all(old="original-local", new="foreign"))
    is None,
  )
  assert_true(
    select(reviewer, host.replace_all(old="host-key", new="reviewer-key"))
    is None,
  )
  assert_true(
    select(reviewer, host.replace_all(old="host-pem", new="reviewer-pem"))
    is None,
  )
  assert_true(
    select(reviewer, host.replace_all(old="key.pem", new="../key.pem")) is None,
  )
  assert_true(
    select(
      reviewer,
      host.replace_all(old="host_attestation", new="reviewer_proof"),
    )
    is None,
  )
  assert_true(
    select(reviewer, host.replace_all(old="effect_set", new="run_scope"))
    is None,
  )
}
