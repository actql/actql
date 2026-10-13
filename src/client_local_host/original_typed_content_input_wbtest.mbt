///|
// Existing independently sealed Content ModelTask/execution vectors from the
// original serialization-input fixture. No CID or historical vector is repinned.
fn original_typed_content_task() -> String {
  (
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:836444f3888092768af981447509670f2efc05bc047bf2665a951603c93b160d","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"document":{"media_type":"application/x-ndjson","nullable":false,"type":"content_ref"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:60859537e680a59e68650f78be73ce2c818e3f3f2e37460568c8a54877c03d7a","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:d0ff84aab70965d97df8303954e5ab59e9b554de3251ca53f55da56577eedde2","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  )
}

///|
fn original_typed_content_execution() -> (String, String) {
  (
    (
      #|{"backoff_contract_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","default_publication":"outcomes","max_attempts_per_slot":1,"max_total_attempts":1,"max_total_cost_units":0,"max_total_duration_ms":500,"max_total_token_reservation":33,"max_total_wire_bytes":133072,"media_input_contracts":{"document":"sha256:03213e7e836021f73b99d57eb5ea5855cd8430cd85b4a4079a8d92eede531507"},"model_task_contract_cid":"sha256:836444f3888092768af981447509670f2efc05bc047bf2665a951603c93b160d","retry_classification_contract_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","self_cid":"sha256:4393328509ccd287c21d7cc029062dd0f5833907fcdd81d4adf33ef493950097","version":"actql-model-execution-contract/0.1"}
    ),
    "sha256:4393328509ccd287c21d7cc029062dd0f5833907fcdd81d4adf33ef493950097",
  )
}

///|
// Data-only consumer seam: the Model provider/startup is not invoked here.
// Physical allphase/normal funding remains the A/C original-startup handoff.
fn original_keyed_typed_content_input(
  compiled : @publication_host.ClientCompiledRun,
  plan : @publication_host.ClientInferPlanGraph,
  generation : @publication_host.ClientSerializationGeneration,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  original? : (
    @publication_host.ClientModelReadScope,
    @publication.PublicationContract,
    @resources.Ledger,
  )? = None,
) -> Unit raise {
  let occurrence = @publication_host.client_serialization_generation_infer_occurrence(
    generation, compiled, plan,
  ).unwrap()
  let output = @publication_host.client_serialization_generation_output_for(
    generation, compiled,
  ).unwrap()
  let segment = @execution.prepare_serialization_infer_input_segment(
    output,
    9,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
  ).unwrap()
  assert_eq(@execution.generated_sequence_step_count(segment), 1)
  assert_eq(@execution.generated_sequence_step_index_at(segment, 0), Some(8))
  let mapping : @execution.InferPreparationLimits = {
    max_items: 2,
    max_work: 100000,
    max_frames: 100,
    max_workspace_slots: 10000,
    values: { max_nodes: 1000, max_depth: 64, max_text_bytes: 10000, },
    logical: {
      max_input_rows: 2L,
      max_value_bytes: 10000L,
      max_live_value_bytes: 100000L,
      max_work: 100000L,
    },
  }
  // Synthetic 7/5 and 10/5 values test nominal same-Ledger admission only.
  // They are not a simultaneous physical bound or a production supplier.
  // Claim/enter precedes the input constructor; no Model execution is started.
  let consumer = match original {
    None => None
    Some((scope, definition, ledger)) => {
      let read = match
        @publication_host.prepare_client_model_read(scope, 7L, 5L) {
        Ok(value) => value
        Err(
          @publication_host.Resource(
            @resources.Resource(@resources.RetentionLimit)
          )
        ) => fail("the original census has no reservation slot for the read")
        Err(_) => fail("unexpected original read preparation failure")
      }
      let consumer = @publication_host.claim_client_model_read_preparation(
        read, compiled, definition, plan, 7L, 5L,
      ).unwrap()
      @publication_host.enter_client_model_read_consumer(
        consumer, compiled, definition, plan, 7L, 5L,
      ).unwrap()
      let before = @resources.ledger_usage(ledger)
      assert_true(
        @publication_host.enter_client_model_read_consumer(
          consumer, compiled, definition, plan, 7L, 5L,
        )
        is Err(@publication_host.Resource(@resources.SpentClaim)),
      )
      assert_eq(@resources.ledger_usage(ledger), before)
      Some(consumer)
    }
  }
  let active = start_client_serialized_infer_input(
    occurrence, segment, 7, output, execution, measurement, mapping,
  ).unwrap()
  let mut rows = None
  for _ in 0..<100000 {
    match advance_client_infer_input(active, 7).unwrap() {
      Complete(value, ..) => {
        rows = Some(value)
        break
      }
      Continue(..) => ()
      _ => fail("actual serialized ContentRef did not reach typed input")
    }
  }
  let rows = rows.unwrap()
  assert_eq(@execution.prepared_infer_rows_count(rows), 1)
  let key = @execution.prepared_infer_rows_key(rows, 0, 0).unwrap()
  assert_true(key.value is @admitted.Text("captured.jsonl"))
  let document = @execution.prepared_infer_rows_value(rows, 0, 0).unwrap()
  guard document.value is @admitted.Reference(reference) else {
    fail("document role must retain ContentRef, not name/text/envelope JSON")
  }
  assert_true(@admitted.reference_available(reference))
  assert_true(
    @admitted.reference_wire(reference).contains(
      "sha256:825b743cf65a3b85fd1220c1bfd6ec9b5c07389479d26df31b32ab31ecb354cd",
    ),
  )
  assert_true(client_infer_completed_input(active) is Some(_))
  let handed = match (original, consumer) {
    (Some((_, definition, ledger)), Some(consumer)) => {
      let input = client_infer_completed_input(active).unwrap()
      let workspace = original_keyed_content_workspace().export_limits
      let scan = @execution.start_completed_relation_identity_scan(
        input,
        20,
        workspace.values,
        workspace.payload_wire,
        workspace.logical_wire,
        workspace.schema,
        10000,
        10000,
      ).unwrap()
      while !@execution.advance_completed_relation_identity_scan(scan, 7).unwrap().0 {
        ()
      }
      let receipt = @execution.finish_completed_relation_identity_scan(scan).unwrap()
      assert_true(
        @publication_host.issue_client_infer_occurrence_call_scope(
          occurrence, plan, input, receipt, 100000, 10000, 100,
        )
        is Err(@publication_host.ClientInferCallScopeIssue::ForeignInput),
      )
      let call_scope = @publication_host.issue_client_infer_occurrence_call_scope(
        occurrence,
        plan,
        input,
        receipt,
        100000,
        10000,
        100,
        generation=Some(generation),
      ).unwrap()
      let quantities = @resources.quantity_usage(ledger)
      let (same, token) = @publication_host.handoff_client_model_read_consumer_input_capacity(
        consumer, compiled, definition, plan, call_scope, rows, 10L, 5L,
      ).unwrap()
      assert_true(physical_equal(same, ledger))
      assert_true(@resources.capacity_reservation_matches(same, token, 10L, 5L))
      assert_eq(@resources.quantity_usage(same), quantities)
      let before = @resources.ledger_usage(same)
      assert_true(
        @publication_host.handoff_client_model_read_consumer_input_capacity(
          consumer, compiled, definition, plan, call_scope, rows, 10L, 5L,
        )
        is Err(@publication_host.Read(Resource(@resources.SpentClaim))),
      )
      assert_true(
        @publication_host.settle_client_model_read_consumer(consumer, false)
        is Err(@publication_host.Resource(@resources.CleanupPending)),
      )
      assert_eq(@resources.ledger_usage(same), before)
      Some((same, token))
    }
    _ => None
  }
  let rows_use = @execution.acquire_prepared_infer_rows(rows).unwrap()
  assert_false(cleanup_client_infer_input(active).unwrap())
  assert_true(active.mapping is Some(_))
  assert_true(active.prefix is Some(_))
  assert_true(active.sequence is Some(_))
  assert_true(@execution.prepared_infer_rows_value(rows, 0, 0) is Some(_))
  assert_true(@execution.release_prepared_infer_rows_use(rows_use))
  assert_true(cleanup_client_infer_input(active).unwrap())
  assert_true(client_infer_completed_input(active) is None)
  assert_true(@execution.prepared_infer_rows_value(rows, 0, 0) is None)
  assert_true(@execution.prepared_infer_rows_key(rows, 0, 0) is None)
  assert_true(@execution.completed_output_available(output))
  // This detects retained mapper/prefix roots on the reusable wrapper after
  // confirmed cleanup; it must not revoke the independently owned byte Ref.
  assert_true(active.mapping is None)
  assert_true(active.prefix is None)
  assert_true(active.retained_input is None)
  assert_true(active.sequence is None)
  assert_true(cleanup_client_infer_input(active).unwrap())
  assert_true(@admitted.reference_available(reference))
  match (consumer, handed) {
    (Some(consumer), Some((same, token))) => {
      // Only this API fixture's input has existed: its confirmed cleanup does
      // not stand in for a Model, SDK, Store, Provider or durable ACK cleanup.
      @publication_host.settle_client_model_read_consumer(consumer, true).unwrap()
      @resources.settle_capacity(same, token).unwrap()
    }
    _ => ()
  }
}
