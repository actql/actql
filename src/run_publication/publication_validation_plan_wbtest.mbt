///|
test "owned validation refuses missing invalid and overflowing original measurements" {
  let absent=snapshot_contract("run_definition","fixture","{}")
  let absent_usage : PublicationValidationUsage={bytes:0,nodes:0,depth:0,occurrence_nodes:0L,metadata_bytes:0,metadata_nodes:0,metadata_depth:0}
  assert_false(absent_usage.add_contract(absent))
  assert_true(prepare_original_effect_free_chain_validation(absent,absent,[],[],absent,absent,absent) is None)
  let zero={..absent,wire_usage:Some((2,0,1))}
  let usage : PublicationValidationUsage={bytes:0,nodes:0,depth:0,occurrence_nodes:0L,metadata_bytes:0,metadata_nodes:0,metadata_depth:0}
  assert_false(usage.add_contract(zero))
  let huge={..absent,wire_usage:Some((2,2147483647,1))}
  let usage : PublicationValidationUsage={bytes:0,nodes:0,depth:0,occurrence_nodes:0L,metadata_bytes:0,metadata_nodes:0,metadata_depth:0}
  assert_true(usage.add_contract(huge))
  assert_false(usage.add_contract(huge))
}
