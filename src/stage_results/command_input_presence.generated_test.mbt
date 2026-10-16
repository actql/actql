// Generated from independent fixed corpus by scripts/command-input-presence-vectors.mjs.

///|
test "Command presence fixed identity empty required subset" {
  let targets = presence_targets("{\"name\":{\"literal\":\"n\"},\"overwrite\":{\"literal\":false}}", required="[]")
  let target = effect_command_target_contract(effect_command_target_at(targets, 0).unwrap())
  assert_eq(@environment.command_target_cid(target), "sha256:c4835b8732c3a1a5ce0322a2a949bfa561b60952b0c393f4ea471d14f2039035")
  assert_eq(@environment.catalog_identity(@environment.command_target_catalog(target)).2, "sha256:7d8b9cd35c31ca8aa827e63f7814f814fc3fee5e90119ef1496b6cd334af39ff")
  let command = @decode.open_object(@environment.member_body(@environment.command_target_member(target))).unwrap()
  let reference = @environment.catalog_reference_for_cursor(effect_command_targets_references(targets), @decode.lookup(command, "input_schema").unwrap()).unwrap()
  assert_eq(@environment.contract_identity(@environment.reference_contract(reference)).2, "sha256:b60dac531f149b90a42b0a864d18bd053778e03813deccfd79ff20e5416c6339")
  let admitted = bind_effect_command_inputs(targets, presence_limits()).unwrap()
  assert_eq(effect_command_input_field_count(effect_command_input_at(admitted, 0).unwrap()), 2)
}

///|
test "Command presence fixed identity one required field" {
  let targets = presence_targets("{\"name\":{\"literal\":\"n\"},\"overwrite\":{\"literal\":false}}", required="[\"name\"]")
  let target = effect_command_target_contract(effect_command_target_at(targets, 0).unwrap())
  assert_eq(@environment.command_target_cid(target), "sha256:c9bfbc2c2805dcb14fe6ec6673aca07b4c8a3477ff14c7b1345f224534bbf646")
  assert_eq(@environment.catalog_identity(@environment.command_target_catalog(target)).2, "sha256:fd787d6ba69a77315e5b5522ac39b92a9fe18b2b0ccd762137141552d3484a1c")
  let command = @decode.open_object(@environment.member_body(@environment.command_target_member(target))).unwrap()
  let reference = @environment.catalog_reference_for_cursor(effect_command_targets_references(targets), @decode.lookup(command, "input_schema").unwrap()).unwrap()
  assert_eq(@environment.contract_identity(@environment.reference_contract(reference)).2, "sha256:7e88d735c0375a321f9fa796997ec7ea5f0c10ab14b4ee15d0b229b2751d1947")
  let admitted = bind_effect_command_inputs(targets, presence_limits()).unwrap()
  assert_eq(effect_command_input_field_count(effect_command_input_at(admitted, 0).unwrap()), 2)
}

///|
test "Command presence fixed identity all required forward" {
  let targets = presence_targets("{\"name\":{\"literal\":\"n\"},\"overwrite\":{\"literal\":false}}", required="[\"name\",\"overwrite\"]")
  let target = effect_command_target_contract(effect_command_target_at(targets, 0).unwrap())
  assert_eq(@environment.command_target_cid(target), "sha256:b1157b58fb492d577eb715033b3598674f5fc23bff5564e76cec94e4a64e70d0")
  assert_eq(@environment.catalog_identity(@environment.command_target_catalog(target)).2, "sha256:3826fdf61ae3c0910ebba8f555d0c676f01e72f514d4977d14cbe38ceee824bf")
  let command = @decode.open_object(@environment.member_body(@environment.command_target_member(target))).unwrap()
  let reference = @environment.catalog_reference_for_cursor(effect_command_targets_references(targets), @decode.lookup(command, "input_schema").unwrap()).unwrap()
  assert_eq(@environment.contract_identity(@environment.reference_contract(reference)).2, "sha256:7a7ed561422ec9a825475b462265e7cd6697dc884a4ca073245f2e16db84fabf")
  let admitted = bind_effect_command_inputs(targets, presence_limits()).unwrap()
  assert_eq(effect_command_input_field_count(effect_command_input_at(admitted, 0).unwrap()), 2)
}

///|
test "Command presence fixed identity all required reversed remains distinct" {
  let targets = presence_targets("{\"name\":{\"literal\":\"n\"},\"overwrite\":{\"literal\":false}}", required="[\"overwrite\",\"name\"]")
  let target = effect_command_target_contract(effect_command_target_at(targets, 0).unwrap())
  assert_eq(@environment.command_target_cid(target), "sha256:a9a62b27656489ffbcae4d9fc4b167e42dd2db32f30318d0261c0d148960233d")
  assert_eq(@environment.catalog_identity(@environment.command_target_catalog(target)).2, "sha256:8649a8dcebf0d0fd12ba79efb6e0f76ba4e4eddcf8f14565c65566f7ebf99187")
  let command = @decode.open_object(@environment.member_body(@environment.command_target_member(target))).unwrap()
  let reference = @environment.catalog_reference_for_cursor(effect_command_targets_references(targets), @decode.lookup(command, "input_schema").unwrap()).unwrap()
  assert_eq(@environment.contract_identity(@environment.reference_contract(reference)).2, "sha256:7df8ad229711bbd63ca94f58983cb28b589290cab4b871c5f19eca6603f4cd08")
  let admitted = bind_effect_command_inputs(targets, presence_limits()).unwrap()
  assert_eq(effect_command_input_field_count(effect_command_input_at(admitted, 0).unwrap()), 2)
}
