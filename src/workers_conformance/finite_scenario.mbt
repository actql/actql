// Test-only original request ownership and observations. The product finite
// Host accepts these original handles; it cannot issue its own admission.

///|
#export_name("workersFiniteFixtureContracts")
pub fn finite_fixture_contracts() -> Array[String] raise {
  [
    @identity.stringify_value(registered_body(), 100000, 10000, 100),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
  ]
}

///|
#export_name("workersFiniteFixtureExecution")
pub fn finite_fixture_execution() -> @execution.SequenceExecutionLimits {
  compute_test_limits()
}

///|
#export_name("workersFiniteFixtureOriginal")
pub fn finite_fixture_original(
  prepared : @publication_host.PreparedClientProgram,
  compilation : @publication_host.ClientValuesCompilation,
) -> @publication_host.ClientCompiledRun {
  @publication_host.issue_client_values_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
}

///|
#export_name("workersFiniteFixtureAdmission")
pub fn finite_fixture_admission(
  original : @publication_host.ClientCompiledRun,
) -> @publication.RunPublicationAdmission {
  @publication_host.client_compiled_run_admission(original)
}

///|
#export_name("workersFiniteFixtureDefinition")
pub fn finite_fixture_definition(
  original : @publication_host.ClientCompiledRun,
) -> @publication.PublicationContract {
  @publication_host.issue_client_compiled_run_definition(
    original, "workers-finite-fixture", "original-run", "2026-10-12T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
}

///|
#export_name("workersFiniteFixtureLedger")
pub fn finite_fixture_ledger() -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 10000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 300000L,
    retained_bytes: 32000000L,
    execution_bytes: 134217728L,
  }).unwrap()
}

///|
#export_name("workersFiniteFixtureUsage")
pub fn finite_fixture_usage(ledger : @resources.Ledger) -> Array[Int64] {
  let usage = @resources.ledger_usage(ledger)
  [
    usage.planning_work.to_int64(),
    usage.attempts.to_int64(),
    usage.holdings.to_int64(),
    usage.transferred_bytes,
    usage.reserved_transfer_bytes,
    usage.held_bytes,
    usage.reserved_retention_bytes,
    usage.reserved_execution_bytes,
  ]
}

///|
/// Observe actual completed rows and schema through the ordinary bounded
/// publication export. Expected rows/schema are authored separately in Node.
#export_name("workersFiniteFixtureOutput")
pub fn finite_fixture_output(
  output : @execution.CompletedOutput,
) -> Array[String] {
  let limits : @execution.RowWireLimits = {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_columns: 100,
    max_order_work: 10000,
  }
  let stream = @execution.prepare_completed_relation_export(
    output,
    100,
    compute_test_limits().rows.output_values,
    limits,
    limits,
    { max_fields: 100, max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
    1024,
  ).unwrap()
  defer @execution.cancel_completed_output_export(stream)
  let text = StringBuilder()
  while @execution.next_completed_output_export(stream).unwrap() is Some(part) {
    text.write_string(part)
  }
  let (receipt, tail) = @execution.finish_completed_relation_export(stream).unwrap()
  defer @execution.cancel_completed_relation_export_receipt(receipt)
  text.write_string(tail)
  let schema = @execution.completed_relation_export_schema_identity(receipt)
  [text.to_string(), @execution.relation_schema_wire(schema)]
}
