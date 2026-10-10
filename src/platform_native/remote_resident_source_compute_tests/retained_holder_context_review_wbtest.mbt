///|
/// The actual original holders use the production checked-edge join. No test
/// joins their imported input evidence or supplies a replacement observation.
fn retained_holder_context_review(
  holder : @resident.ResidentRetainedConsumer,
  journal : @dispatch_journal.Journal,
  producer : @resident.ResidentEffectProducerExecuted,
  producer_journal : @dispatch_journal.Journal,
  root_path : String,
  name : String,
) -> Unit raise {
  let consumer = holder.effect_computation(journal).unwrap()
  let source = producer.source_for_capture(producer_journal).unwrap()
  let source_usage = source.usage()
  let consumer_usage = consumer.usage()
  let prepare = (stage, index, pins, work) => {
    holder.prepare_effect_review_inputs(
      journal,
      producer,
      producer_journal,
      stage,
      index,
      retained_compute_effect_retention(),
      resident_compute_limits(),
      pins,
      work,
      65536,
      4096,
      64,
    )
  }
  assert_true(
    prepare(1, 0, 0, 10000) is Err({ issue: InvalidLimits, pending: None, }),
  )
  assert_true(
    prepare(1, 0, 4, 1) is Err({ issue: Producer(WorkLimit), pending: None, }),
  )
  assert_true(
    prepare(0, 0, 4, 10000) is Err({ issue: Import(_), pending: None, }),
  )
  assert_true(
    prepare(1, 1, 4, 10000) is Err({ issue: Import(_), pending: None, }),
  )
  assert_eq(source.usage().held_bytes, source_usage.held_bytes)
  assert_eq(consumer.usage().held_bytes, consumer_usage.held_bytes)
  let invocation = producer
    .invocation_for_capture(producer_journal, 65536, 4096, 64)
    .unwrap()
  // A failed Result capture owns only this connection's private pins/export.
  // Prepare it before the independent successful context to respect the
  // existing Named Result export pin ceiling; no limit is raised here.
  let rejected_context = prepare(1, 0, 4, 10000).unwrap()
  assert_true(
    @effect_provider.prepare_native_resident_effect_review_from_context(
      holder,
      journal,
      rejected_context,
      invocation.0,
      [],
      [],
      retained_holder_review_policy(
        holder,
        rejected_context.facts(journal).unwrap().inputs,
        invocation.1,
      ),
    )
    is Err(
      {
        issue: Result(
          Receipt(ReceiptIssuanceWrongContract("normalization_journal"))
        ),
        pending: None,
      }
    ),
  )
  assert_true(rejected_context.facts(journal) is None)
  assert_true(rejected_context.close())
  assert_eq(source.usage().held_bytes, source_usage.held_bytes)
  assert_eq(consumer.usage().held_bytes, consumer_usage.held_bytes)
  assert_eq(
    consumer.usage().reserved_retention_bytes,
    consumer_usage.reserved_retention_bytes,
  )
  let context = prepare(1, 0, 4, 10000).unwrap()
  let facts = context.facts(journal).unwrap()
  let materials = consumer.effect_materials_for_capture().unwrap()
  assert_eq(facts.materials.request, materials.request)
  assert_eq(
    @host.client_effect_local_result_artifact_json(facts.receiver),
    @host.client_effect_local_result_artifact_json(facts.producer.artifact),
  )
  assert_eq(
    @host.client_effect_imported_relation_bodies(facts.imported).length(),
    1,
  )
  assert_eq(
    @publication.publication_contract_identity(facts.producer.invocation),
    @publication.publication_contract_identity(invocation.1),
  )
  assert_eq(
    @publication.run_evidence_value_json(facts.producer.observation),
    @publication.run_evidence_value_json(invocation.0),
  )
  // Normalization policy is still a fixture, not a production normalization
  // journal issued by this connection. Original acquisition and input custody
  // above are actual Native Owner outputs.
  let normalization = @publication.seal_run_evidence_value(
    "normalization_journal",
    "{\"version\":\"actql-normalization-journal/0.1\",\"rule_catalog_cid\":\"" +
    retained_compute_cid("d") +
    "\",\"entries\":[]}",
    65536,
    4096,
    64,
  ).unwrap()
  retained_holder_provider_review(
    holder,
    journal,
    consumer,
    source,
    facts.materials,
    facts.inputs,
    @resident.resident_retained_consumer_request(holder),
    facts.producer.invocation,
    facts.producer.observation,
    facts.producer,
    facts.receiver,
    facts.imported,
    facts.root_index,
    root_path,
    name,
    context,
    normalization,
    () => prepare(1, 0, 4, 10000),
  )
  assert_true(context.close())
  assert_true(context.close())
  assert_true(context.facts(journal) is None)
  assert_true(
    context.capture_result(journal, normalization, [], [], 65536, 4096, 64)
    is Err(Unavailable),
  )
  assert_true(consumer.request_for_effect_review(facts.inputs) is None)
  assert_eq(source.usage().held_bytes, source_usage.held_bytes)
  assert_eq(
    source.usage().reserved_execution_bytes,
    source_usage.reserved_execution_bytes,
  )
  assert_eq(consumer.usage().held_bytes, consumer_usage.held_bytes)
  assert_eq(
    consumer.usage().reserved_execution_bytes,
    consumer_usage.reserved_execution_bytes,
  )
}
