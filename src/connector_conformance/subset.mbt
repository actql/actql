///|
/// Conformance configuration only. Execution, settlement and publication are
/// entirely in the installed modules and the standard Host, on every target.
/// 0 = Local only, 1 = independent numeric only, 2 = both.
pub fn configure_subset(
  run : @strategy.CapturedDAG,
  sequences : Array[@execution.GeneratedSequence],
  mode : Int,
  managed_providers? : Array[@local.ManagedProvider] = [],
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  if mode < 0 || mode > 2 {
    abort("invalid conformance configuration")
  }
  let count = if mode == 2 { 2 } else { 1 }
  let registry = @connector.prepare_capability_registry(
    Array::makei(count, i => {
      name: if i == 0 {
        "first-installed"
      } else {
        "second-installed"
      },
      acquisition: false,
      fixed_compute: true,
    }),
    count,
    100,
  ).unwrap()
  let driver = @host.open_dispatch_driver(run)
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let modules = @builtin.configure_compute_modules(
    driver,
    registry,
    count,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=if mode != 1 {
      Some(
        (
          @connector.capability_registration_at(registry, 0).unwrap(),
          {
            sequences,
            managed_providers,
            managed_capacity: {
              contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
              max_rows: 100,
              max_value_bytes: 10000,
              common_fragment: None,
            },
            execution: {
              rows: {
                max_rows: 100,
                metadata_entries: 10000,
                retained_entries: 10000,
                operation_entries: 10000,
                input_values: values,
                output_values: values,
              },
              max_work: 100000,
              max_frames: 100,
            },
            measurement,
            max_work: 100,
          },
          _ => @strategy.RunIssue::ForeignCandidate,
          _ => @strategy.RunIssue::ForeignCandidate,
        ),
      )
    } else {
      None
    },
    with_reference_compute=if mode != 0 {
      Some(
        (
          @connector.capability_registration_at(registry, count - 1).unwrap(),
          {
            sequences: sequences.map(
              @execution.generated_completion_preparation,
            ),
            limits: {
              max_work: 100,
              max_entries: 100,
              max_name_bytes: 10000,
              values,
              physical: measurement,
              roots: measurement,
            },
            expressions: {
              max_nodes: 1000,
              max_work: 10000,
              max_depth: 100,
              max_literal_nodes: 1000,
              max_literal_text_bytes: 10000,
            },
            milliseconds: Some(1L),
            max_work: 100,
          },
          issue => issue,
          issue => issue,
        ),
      )
    } else {
      None
    },
  ).unwrap()
  if mode != 1 {
    @local_driver.configure_local_retained_inputs(
      @builtin.configured_local_module(modules).unwrap(),
      {
        max_rows: 100,
        values,
        wire: {
          max_columns: 100,
          max_order_work: 10000,
          max_bytes: 10000,
          max_nodes: 10000,
          max_depth: 64,
        },
        row: {
          max_bytes: 10000,
          max_nodes: 10000,
          max_depth: 64,
          max_text_bytes: 10000,
        },
        max_batch_bytes: 10000,
      },
      Some(1L),
    ).unwrap()
    let schedule = @cost.prepare_rate_schedule(
      @builtin.local_estimate_work_slots(),
      [
        {
          work_slots: [0, 1, 2, 3, 4],
          fixed_ms: Some(10L),
          per_row_ms: Some(0L),
          per_wire_byte_ms: Some(0L),
          per_pair_ms: Some(0L),
        },
      ],
      100,
    ).unwrap()
    let policy = @builtin.prepare_local_estimate_policy(modules, {
      schedules: Array::make(sequences.length(), schedule),
      eligible: [],
      max_work: 1000,
    }).unwrap()
    @builtin.install_configured_estimate_policy(policy).unwrap()
  }
  let installed = @builtin.open_configured_compute_host(
    modules,
    registry,
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    },
    100,
    10000,
    count,
  ).unwrap()
  @host.configure_compute_host_estimates(
    @builtin.configured_host_runtime(installed),
    Array::make(sequences.length(), Some(1000)),
    {
      max_offers: sequences.length() * count,
      max_strategies: 8,
      max_work: 10000,
      max_revisions: sequences.length(),
    },
    0,
  ).unwrap()
  installed
}
