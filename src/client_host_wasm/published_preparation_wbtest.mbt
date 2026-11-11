///|
// Same independent JSON/hash fixture as the portable Source bridge cases.
// Buffer stop callbacks are explicit ports; there is no physical Host/Run ACK.
let published_preparation_environment_wire : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:de7cfc6d9aa91109ea99c14a77c22fbe49c94e49d6ff0d2fefd49a9904831288","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:c99f6697a8b40c16a418a156177be2a6144be3ba5ebbc36020c819789d021cd4","mapping_ref":"mapping:crm.account.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]},{"effect_kind":"update","permissions":["scope:update"],"selector_class":"ids","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:1208f407bf69f466944f865797ce7407361d822605d1fbbb502177af4b63958f","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
fn published_preparation_fixture(
  nonce : Int64,
  text : String,
  read_only? : Bool = false,
) -> (
  Instance,
  StoredPreparation,
  @buffers.BufferPool,
  @resources.SharedCapacity,
  @buffers.BufferSlot,
  @buffers.BufferSlot,
) raise {
  let root = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 128,
    holdings: 128,
    transfer_bytes: 67108864L,
    retained_bytes: 67108864L,
    execution_bytes: 67108864L,
  }).unwrap()
  let capacity = @resources.reserve_shared_capacity(root, 33554432L).unwrap()
  let pool = @buffers.open_pool_on_ledger(root, 4194304L, 16, 1048576).unwrap()
  assert_eq(
    install_buffer_instance(
      nonce,
      root,
      capacity,
      None,
      pool,
      16,
      prepare_product_sequence_contracts().unwrap(),
    ),
    0,
  )
  let value = selected(nonce).unwrap()
  let environment = @host.admit_client_check_environment(
    published_preparation_environment_wire,
    "sha256:de7cfc6d9aa91109ea99c14a77c22fbe49c94e49d6ff0d2fefd49a9904831288",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[],\"updateTargets\":[{\"name\":\"salesforce.Account\",\"targetRef\":\"connector://crm/account\",\"installationBindingCid\":\"sha256:" +
    "d".repeat(64) +
    "\",\"installationOwnerCid\":\"sha256:" +
    "e".repeat(64) +
    "\"}]}"
  let environment_bytes = @utf8.encode(published_preparation_environment_wire)
  let environment_slot = @buffers.reserve_output_buffer(
    pool,
    environment_bytes.length(),
    0L,
    () => true,
  ).unwrap()
  @buffers.supply_buffer_output(pool, environment_slot, environment_bytes).unwrap()
  let environment_borrow = @buffers.borrow_buffer(pool, environment_slot, () => {
    true
  }).unwrap()
  value.environments[1] = {
    borrow: environment_borrow,
    environment,
    wire: published_preparation_environment_wire,
    context: @preparation.bind_local_published_input_context(
      environment,
      publication,
      None,
    ).unwrap(),
    publication: Some(publication),
  }
  let bytes = @utf8.encode(
    "{\"input\":{\"format\":\"aql\",\"text\":\"" +
    text +
    "\"},\"kind\":\"aql\",\"parameters\":null" +
    (if read_only { ",\"readOnly\":true}" } else { "}" }),
  )
  let slot = @buffers.reserve_buffer(pool, bytes.length(), 0L, () => true).unwrap()
  @buffers.fill_buffer(pool, slot, 0, bytes.length(), index => {
    Some(bytes[index])
  }).unwrap()
  @buffers.seal_buffer(pool, slot, 16384, 64).unwrap()
  let borrow = @buffers.borrow_buffer(pool, slot, () => true).unwrap()
  let record : StoredPreparation = {
    borrow,
    slot,
    environment: 1,
    kind: 3,
    restoration: None,
    submitted: None,
    started: false,
    outcome: None,
    source: None,
    source_issue: None,
  }
  value.preparations[2] = record
  (value, record, pool, capacity, slot, environment_slot)
}

///|
fn published_preparation_close(
  nonce : Int64,
  pool : @buffers.BufferPool,
  capacity : @resources.SharedCapacity,
  slot : @buffers.BufferSlot,
  environment_slot : @buffers.BufferSlot,
) -> Unit raise {
  assert_eq(close_preparation(nonce, 2), 0)
  assert_eq(close_environment(nonce, 1), 0)
  @buffers.close_buffer(pool, slot).unwrap()
  @buffers.close_buffer(pool, environment_slot).unwrap()
  @buffers.close_pool(pool).unwrap()
  @resources.close_shared_capacity(capacity).unwrap()
  instance.val = None
}

///|
let published_preparation_effect_text = "SELECT 'original-id' AS id, 1 AS value |> RESULT out |> EFFECT UPDATE salesforce.Account ID id SET (Name = value)"

///|
test "published submitted preparation retains SAME Effect Source without Pure upgrade or repeat" {
  let nonce = 6181L
  let (value, record, pool, capacity, slot, environment_slot) = published_preparation_fixture(
    nonce, published_preparation_effect_text,
  )
  assert_eq(prepare_program(nonce, 2), 0)
  let source = stored_preparation_source(value, 2).unwrap()
  let effect = stored_preparation_effect(value, 2).unwrap()
  assert_eq(prepared_outcome(nonce, 2), 1)
  assert_eq(prepared_results(nonce, 2), 1)
  assert_true(prepared_tasks(nonce, 2) > 0)
  assert_true(stored_preparation_input(record) is None)
  assert_true(record.submitted is None)
  assert_true(
    @preparation.local_source_computation_preparation(source) is Effect(actual) &&
    physical_equal(actual, effect),
  )
  assert_eq(
    @preparation.local_source_computation_source(source).0,
    published_preparation_effect_text,
  )
  assert_eq(prepare_program(nonce, 2), 0)
  assert_true(
    physical_equal(source, stored_preparation_source(value, 2).unwrap()),
  )
  assert_true(
    physical_equal(effect, stored_preparation_effect(value, 2).unwrap()),
  )
  published_preparation_close(nonce, pool, capacity, slot, environment_slot)
  assert_true(stored_preparation_source(value, 2) is None)
}

///|
test "published submitted Pure handoff retains original intent and refuses equal foreign pair" {
  let nonce = 6182L
  let (value, record, pool, capacity, slot, environment_slot) = published_preparation_fixture(
    nonce, "SELECT 1 AS n",
  )
  assert_eq(prepare_program(nonce, 2), 0)
  let source = stored_preparation_source(value, 2).unwrap()
  let input = stored_preparation_input(record).unwrap()
  assert_true(
    @preparation.local_source_computation_preparation(source) is Pure(actual) &&
    physical_equal(actual, @preparation.local_prepared_program(input)),
  )
  assert_eq(prepared_outcome(nonce, 2), 1)
  assert_eq(prepared_results(nonce, 2), 1)
  assert_true(stored_preparation_effect(value, 2) is None)
  let pair = record.source.unwrap()
  let foreign = @host.prepare_client_submitted_intent(
    @host.client_submitted_intent_wire(pair.0),
    65536,
    8192,
    64,
  ).unwrap()
  record.source = Some((foreign, pair.1))
  assert_true(stored_preparation_source(value, 2) is None)
  assert_eq(prepared_outcome(nonce, 2), -35)
  assert_eq(prepared_results(nonce, 2), -35)
  record.source = Some(pair)
  assert_eq(prepared_outcome(nonce + 1L, 2), -2)
  assert_eq(prepared_outcome(nonce, 3), -2)
  published_preparation_close(nonce, pool, capacity, slot, environment_slot)
}

///|
test "published submitted refusal retains same typed issue before any executable Effect" {
  let nonce = 6183L
  let (value, record, pool, capacity, slot, environment_slot) = published_preparation_fixture(
    nonce,
    published_preparation_effect_text,
    read_only=true,
  )
  assert_eq(prepare_program(nonce, 2), 0)
  assert_eq(prepared_outcome(nonce, 2), 2)
  assert_true(record.source_issue is Some(ReadOnly))
  assert_true(record.source is None)
  assert_true(stored_preparation_effect(value, 2) is None)
  assert_eq(prepared_tasks(nonce, 2), -22)
  assert_eq(prepare_program(nonce, 2), 0)
  assert_true(record.source_issue is Some(ReadOnly))
  assert_eq(value.runs.length(), 0)
  published_preparation_close(nonce, pool, capacity, slot, environment_slot)
}
