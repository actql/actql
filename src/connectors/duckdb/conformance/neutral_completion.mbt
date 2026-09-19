///|
/// The ordinary generated standard Host with exactly one Compute module.
/// Acquisition remains the already completed observation, not a fresh read.
#export_name("strategyFixtureDuckDBOnly")
pub fn strategy_fixture_duckdb_only(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  strategy_fixture_duckdb_only_impl(f, false)
}

///|
/// The same product installation with managed file capacity selected before
/// offers and strategy comparison.
#export_name("strategyFixtureManagedDispatch")
pub fn strategy_fixture_managed_dispatch(
  f : StrategyFixture,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  strategy_fixture_duckdb_only_impl(f, true)
}

///|
fn strategy_fixture_duckdb_only_impl(
  f : StrategyFixture,
  managed : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] {
  let generated = Array::makei(@strategy.graph_task_count(f.graph) - 1, i => {
    fixture_generated(
      @strategy.graph_task_owner(f.graph, i + 1).unwrap(),
      f.registry_json,
      f.values_json,
      f.fragment_json,
      true,
    ) catch {
      _ => abort("managed fixture generation")
    }
  })
  let sequences = generated.map(@execution.generated_completion_preparation)
  let count = if managed { 3 } else { 1 }
  let registry = @connector.prepare_capability_registry(
    Array::makei(count, index => {
      name: if index == 0 {
        "duckdb"
      } else if index == 1 {
        "local"
      } else {
        "reference"
      },
      acquisition: false,
      fixed_compute: true,
    }),
    count,
    100,
  ).unwrap()
  let driver = @physical_host.open_dispatch_driver(f.run.unwrap())
  let capacity : @connector.FixedComputeCapacity = {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 1000,
    common_fragment: None,
  }
  let modules = @builtin.configure_compute_modules(
    driver,
    registry,
    count,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_duckdb=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          limits: {
            capacity,
            candidate_work: 100,
            query: {
              max_entries: 100,
              max_sql_bytes: 10000,
              expressions: {
                max_nodes: 1000,
                max_work: 10000,
                max_depth: 100,
                max_literal_nodes: 1000,
                max_literal_text_bytes: 10000,
              },
            },
            join_validation: {
              max_rows: 100,
              max_work: 10000,
              max_entries: 1000,
            },
            execution: {
              values: issued_native_measure_limits(),
              demand: issued_native_measure_limits(),
              physical: {
                max_rows: 100,
                max_cells: 1000,
                max_nodes: 1000,
                max_text_bytes: 10000,
              },
              retention: {
                max_nodes: 10000,
                max_text_bytes: 10000,
                max_depth: 100,
                max_work: 100000,
              },
              metadata_work: 10000,
              completion_entries: 100,
              completion_name_bytes: 10000,
            },
            transport: {
              max_bytes: 100000,
              max_nodes: 10000,
              max_columns: 10,
              max_rows: 100,
              max_text_bytes: 100000,
            },
          },
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
    with_reference_compute=if managed {
      Some(
        (
          @connector.capability_registration_at(registry, 2).unwrap(),
          {
            sequences,
            limits: {
              max_work: 100,
              max_entries: 100,
              max_name_bytes: 10000,
              values: {
                max_nodes: 10000,
                max_text_bytes: 10000,
                max_depth: 100,
                max_work: 100000,
              },
              physical: {
                max_work: 10000,
                max_bytes: 100000,
                max_nodes: 10000,
                max_depth: 100,
              },
              roots: {
                max_work: 10000,
                max_bytes: 100000,
                max_nodes: 10000,
                max_depth: 100,
              },
            },
            expressions: {
              max_nodes: 1000,
              max_work: 10000,
              max_depth: 100,
              max_literal_nodes: 1000,
              max_literal_text_bytes: 10000,
            },
            milliseconds: Some(20L),
            max_work: 100,
          },
          _ => @strategy.RunIssue::ForeignCandidate,
          _ => @strategy.RunIssue::ForeignCandidate,
        ),
      )
    } else {
      None
    },
    with_local=if managed {
      Some(
        (
          @connector.capability_registration_at(registry, 1).unwrap(),
          {
            sequences: generated,
            managed_providers: [],
            managed_capacity: capacity,
            execution: {
              rows: {
                max_rows: 100,
                metadata_entries: 10000,
                retained_entries: 10000,
                operation_entries: 10000,
                input_values: {
                  max_nodes: 10000,
                  max_text_bytes: 10000,
                  max_depth: 100,
                  max_work: 100000,
                },
                output_values: {
                  max_nodes: 10000,
                  max_text_bytes: 10000,
                  max_depth: 100,
                  max_work: 100000,
                },
              },
              max_work: 100000,
              max_frames: 100,
            },
            measurement: issued_native_measure_limits(),
            max_work: 100,
          },
          _ => @strategy.RunIssue::ForeignCandidate,
          _ => @strategy.RunIssue::ForeignCandidate,
        ),
      )
    } else {
      None
    },
  ).unwrap()
  if managed {
    @duckdb_driver.configure_duckdb_retained_output(
      @builtin.configured_duckdb_module(modules).unwrap(),
      100000L,
      Some(1L),
    ).unwrap()
    @local_driver.configure_local_retained_inputs(
      @builtin.configured_local_module(modules).unwrap(),
      {
        max_rows: 100,
        values: {
          max_nodes: 10000,
          max_text_bytes: 10000,
          max_depth: 100,
          max_work: 100000,
        },
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
  }
  let slots = @builtin.duckdb_estimate_work_slots()
  let schedule = @physical_cost.prepare_rate_schedule(
    slots,
    [
      {
        work_slots: Array::makei(slots, i => i),
        fixed_ms: Some(10L),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    100,
  ).unwrap()
  let policy = @builtin.prepare_duckdb_estimate_policy(modules, {
    schedules: Array::make(sequences.length(), schedule),
    capacities: Array::make(sequences.length(), @strategy.PhysicalEnvelope::{
      transfer_bytes: 100000L,
      retained_bytes: 10000000L,
      execution_bytes: 200000000L,
    }),
    max_work: 1000,
  }).unwrap()
  @builtin.install_configured_estimate_policy(policy).unwrap()
  if managed {
    let local_schedule = @physical_cost.prepare_rate_schedule(
      @builtin.local_estimate_work_slots(),
      [
        {
          work_slots: [0, 1, 2, 3, 4],
          fixed_ms: Some(20L),
          per_row_ms: Some(0L),
          per_wire_byte_ms: Some(0L),
          per_pair_ms: Some(0L),
        },
      ],
      100,
    ).unwrap()
    let local_policy = @builtin.prepare_local_estimate_policy(modules, {
      schedules: Array::make(sequences.length(), local_schedule),
      max_work: 1000,
    }).unwrap()
    @builtin.install_configured_estimate_policy(local_policy).unwrap()
  }
  let installed = @builtin.open_configured_compute_host(
    modules, registry, capacity, 100, 10000, count,
  ).unwrap()
  @physical_host.configure_compute_host_estimates(
    @builtin.configured_host_runtime(installed),
    Array::make(sequences.length(), Some(1000)),
    {
      max_offers: sequences.length() * count,
      max_strategies: if managed {
        64
      } else {
        8
      },
      max_work: 10000,
      max_revisions: sequences.length(),
    },
    0,
  ).unwrap()
  installed
}
