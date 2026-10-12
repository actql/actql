///|
test "original storage binding independent exact preimage" {
  let body =
    #|{"key_generation_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","private_namespace":"local-continuation-private","store_authority_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","store_contract_cid":"sha256:247d00ffcfddef53c9631b096e4ee3dfd37e2f83a035e0bcf6f7559b852476df","store_contract_wire":"{\"version\":\"actql-local-publication-store/0.1\",\"isolation\":\"execution-namespace\",\"store_authority_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"}","version":"actql-model-original-storage-binding/0.1"}
  let value = seal_run_evidence_value(
    "model_original_storage_binding", body, 2048, 32, 2,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:78c803436a1ff3cb68ebd954f539a2353049544615e942931d7aa0ab6839e2a3",
  )
  let wire = run_evidence_value_json(value)
  assert_eq(
    run_evidence_value_json(
      admit_run_evidence_value(
        "model_original_storage_binding", wire, 2048, 32, 2,
      ).unwrap(),
    ),
    wire,
  )
  assert_true(
    admit_run_evidence_value(
      "model_original_storage_binding",
      " " + wire,
      2048,
      32,
      2,
    )
    is Err(RunEvidenceInvalidWire),
  )
  // These independent substitutions are not produced from product output.
  for
    invalid in [
      body.replace(old="247d00", new="347d00"),
      body.replace(old="local-continuation-private", new="publication-private"),
      body.replace(old="execution-namespace", new="shared"),
      body.replace(old="key_generation_cid", new="key"),
      body.replace(
        old="actql-model-original-storage-binding/0.1",
        new="actql-model-original-storage-binding/" + "9.9",
      ),
      body.replace(
        old="{\"key_generation_cid\"",
        new="{\"holding_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"key_generation_cid\"",
      ),
    ] {
    assert_true(
      seal_run_evidence_value(
        "model_original_storage_binding", invalid, 2048, 32, 2,
      )
      is Err(_),
    )
  }
  assert_true(
    seal_run_evidence_value("model_original_storage_binding", body, 32, 32, 2)
    is Err(_),
  )
}
