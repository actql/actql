///|
fn values_filter_pipeline_prepared(
  count : Int,
) -> @publication_host.PreparedClientProgram {
  let assets = @publication_host.client_local_product_assets()
  let body = @json.parse(assets.environment) catch {
    _ => abort("bundled Environment JSON invalid")
  }
  guard body is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    abort("bundled Environment identity missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let rows = Array::makei(count, id => {
    "{\"id\":" + id.to_string() + ",\"bucket\":" + (id % 10).to_string() + "}"
  }).join(",")
  let template =
    #|{"version":"actql/0.1","id":"values-filter-pipeline","stages":[{"id":"main","inputs":{},"steps":[{"as":"input","values":{"schema":{"id":{"type":"number","nullable":false},"bucket":{"type":"number","nullable":false}},"rows":[]}},{"from":"input","filter":"id >= 50","as":"filtered"},{"from":"filtered","derive":{"next":"id + 1"},"as":"derived"},{"from":"derived","group":{"by":["bucket"],"aggregates":{"n":{"fn":"count","field":"next"}}},"as":"grouped"},{"from":"grouped","sort":[{"field":"bucket","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["bucket","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let document = template.replace(
    old="\"rows\":[]",
    new="\"rows\":[" + rows + "]",
  )
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  @publication_host.with_prepared_client_values_row_limit(prepared, 2000).unwrap()
}

///|
test "larger filtered Values compose derive group and sort with exact independent rows" {
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  for count in [500, 1000] {
    let prepared = values_filter_pipeline_prepared(count)
    let sequence = prepare_client_local_sequences(
        prepared,
        asset_contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      ).unwrap()[0]
    let (_, execution, measurement) = client_local_execution_limits(
      max_rows=2000,
    )
    let provider = @local.local_bounded_relation_provider(
      execution, measurement, sequence,
    ).unwrap()
    let active = @local.start_managed_provider_with_execution(
      provider,
      sequence,
      [],
      2000,
      10000,
      execution,
    ).unwrap()
    let mut output : @execution.CompletedOutput? = None
    let mut work = 0L
    for _ in 0..<100000 {
      let poll = @local.advance_managed_provider(active, 64).unwrap()
      let (used, terminal) = match poll {
        @local.Continue(work=used, ..) | @local.Waiting(work=used, ..) =>
          (used, false)
        @local.Settling(_, work=used, ..) => (used, false)
        @local.Complete(value, work=used, ..) => {
          output = Some(value)
          (used, true)
        }
        @local.Failed(
          @connector.Execution(
            @execution.Rows(_, @execution.LogicalRows(@execution.InputRowLimit))
          ),
          ..
        ) => {
          values_filter_capacity_cleanup(active)
          fail("pipeline first typed refusal: LogicalRows(InputRowLimit)")
          (0L, true)
        }
        _ => {
          values_filter_capacity_cleanup(active)
          fail("pipeline returned another typed failure or unexpected stop")
          (0L, true)
        }
      }
      work += used
      assert_true(work <= execution.max_work.to_int64())
      if terminal {
        break
      }
    }
    let output = output.unwrap()
    assert_eq(@execution.completed_row_count(output), 10)
    for bucket in 0..<10 {
      // Exactly five original rows per bucket fail id >= 50; COUNT(next)
      // consumes the derived, required Number and remains an ordinary Number.
      let expected = count / 10 - 5
      assert_eq(
        @execution.completed_output_row_wire(output, bucket, 1000, 10, 3).unwrap(),
        "{\"bucket\":" +
        bucket.to_string() +
        ",\"n\":" +
        expected.to_string() +
        "}",
      )
    }
    values_filter_capacity_cleanup(active)
  }
}
