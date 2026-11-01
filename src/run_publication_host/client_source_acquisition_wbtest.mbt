///|
// Independent fixture facts explicitly declare id as a candidate key, as
// required for the authored Sort's total order. This is checker DATA only.
let source_input_ordered_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[{"capability_contract_cids":["sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d","sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929"],"read_mode":"snapshot","source_contract_cid":"sha256:87c867504045bffca4c41d82a311e20086c85543b9969a6e090a8e68c20f6ca0","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:87c867504045bffca4c41d82a311e20086c85543b9969a6e090a8e68c20f6ca0"},{"capability_contract_cids":["sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d","sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929"],"read_mode":"snapshot","source_contract_cid":"sha256:c340e4a0cfd9a02b5d62418459779e30246332618acc6a4601f31dd31ab23db4","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:c340e4a0cfd9a02b5d62418459779e30246332618acc6a4601f31dd31ab23db4"}],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]},{"catalog_cid":"sha256:bd0767b265770ae57853a01e0e37f66b6c2fbe2dfac844298dce698b2085fb52","commands":[],"connector_id":"crm/right","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"relation_keys":{"candidate_keys":[["id"]]}},"cid":"sha256:5e6c57616cc7db4bc59c643f88883c71403a181f436979488ba86c8e2d7da3f9","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:c340e4a0cfd9a02b5d62418459779e30246332618acc6a4601f31dd31ab23db4","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:5e6c57616cc7db4bc59c643f88883c71403a181f436979488ba86c8e2d7da3f9","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:7203a52aa81976ebdfb9326a547e5733e0bae49911565be7d728e0d23a73b8ca","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"relation_keys":{"candidate_keys":[["id"]]}},"cid":"sha256:5e6c57616cc7db4bc59c643f88883c71403a181f436979488ba86c8e2d7da3f9","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:87c867504045bffca4c41d82a311e20086c85543b9969a6e090a8e68c20f6ca0","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:5e6c57616cc7db4bc59c643f88883c71403a181f436979488ba86c8e2d7da3f9","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"connector_manifest":{"connectors":[{"connector":"crm/main","connector_id":"crm/main","connector_version":"fixture"},{"connector":"crm/right","connector_id":"crm/right","connector_version":"fixture"},{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"classification":"unknown","source_ref":"connector://crm/right/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{"relation_keys":{"candidate_keys":[["id"]]}},"cid":"sha256:5e6c57616cc7db4bc59c643f88883c71403a181f436979488ba86c8e2d7da3f9","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:15a2df79e3aa9df4c2f0e1a06b86bcd9b9b2e3bbc336876acaabf27ebadf63e0","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:f298b9a108471ac14005fa6146e6499213826bad153c16b4dab9ae60d0aad8ab","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"create","permissions":["scope:create"],"selector_class":"none","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:1208f407bf69f466944f865797ce7407361d822605d1fbbb502177af4b63958f","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:c340e4a0cfd9a02b5d62418459779e30246332618acc6a4601f31dd31ab23db4","source_data_policy_cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","source_ref":"connector://crm/right/r#v","source_view_contract_cid":"sha256:c340e4a0cfd9a02b5d62418459779e30246332618acc6a4601f31dd31ab23db4"},{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:87c867504045bffca4c41d82a311e20086c85543b9969a6e090a8e68c20f6ca0","source_data_policy_cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:87c867504045bffca4c41d82a311e20086c85543b9969a6e090a8e68c20f6ca0"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:87c867504045bffca4c41d82a311e20086c85543b9969a6e090a8e68c20f6ca0","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:5e6c57616cc7db4bc59c643f88883c71403a181f436979488ba86c8e2d7da3f9","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"},{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/right","connector_version":"fixture","contract_cid":"sha256:c340e4a0cfd9a02b5d62418459779e30246332618acc6a4601f31dd31ab23db4","output":{"carrier":"relation","data_policy":{"cid":"sha256:605efefa0cce486485b8d8bc350cfe7a7d84de4741496b8466503038714da786","id":"fixture-right-data-policy","version":"fixture"},"facts":{"cid":"sha256:5e6c57616cc7db4bc59c643f88883c71403a181f436979488ba86c8e2d7da3f9","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}

///|
fn source_input_program_environment() -> @checked.CheckEnvironment {
  admit_client_check_environment(
    bound_effect_source_environment,
    "sha256:e3da0e91ef758728bdf6e58957c09fe044d97d1fa2a21c9c19e3bdf5109bf45b",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn source_input_unfiltered_program() -> PreparedClientProgram raise {
  let (_, _, limits) = client_composed_effect_base_fixture()
  let document =
    #|{"version":"actql/0.1","id":"original-source-input","stages":[{"id":"source","inputs":{"table":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"select":["id","amount"],"as":"selected"},{"sort":[{"id":"asc"}],"as":"sorted"}],"results":{"out":{"from":"sorted","fields":["id","amount"]}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  match
    prepare_effect_free_client_program(
      document,
      Json,
      admit_client_check_environment(
        source_input_ordered_environment,
        "sha256:15a2df79e3aa9df4c2f0e1a06b86bcd9b9b2e3bbc336876acaabf27ebadf63e0",
        { text_time: false, veca: false, },
        {
          rela: true,
          sga: false,
          tea: false,
          calendar: false,
          text_rank: false,
        },
      ).unwrap(),
      None,
      limits.program,
    ) {
    Ok(value) => value
    Err(Check(issue)) => {
      match @checked.diagnostic_cause(issue) {
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(
            Program(Program(Pipeline(_, nested)))
          )
        ) =>
          debug_inspect(
            nested.kind,
            content="original Source fixture must check",
          )
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::Checks(_)
        ) => fail("Source fixture source/checks")
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::Identity(_)
        ) => fail("Source fixture source/identity")
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::Requests(_)
        ) => fail("Source fixture source/requests")
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::Registration(_)
        ) => fail("Source fixture source/registration")
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(
            Program(Program(Order(_, ResultOrder(issue))))
          )
        ) =>
          debug_inspect(
            issue.kind,
            content="original Source Result order must check",
          )
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(
            Program(Program(Results(_, issue)))
          )
        ) =>
          debug_inspect(issue.kind, content="original Source Result must check")
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(Program(BudgetExceeded))
        ) => fail("Source fixture sourceview/program/budget")
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(Program(Program(issue)))
        ) =>
          fail(
            match issue {
              InvalidLimits => "sourceview/program/invalid_limits"
              CheckOnlyPrefix => "sourceview/program/check_only_prefix"
              BudgetExceeded => "sourceview/program/budget"
              ForeignEnvironmentSource =>
                "sourceview/program/foreign_environment_source"
              ForeignModelEnvironment =>
                "sourceview/program/foreign_model_environment"
              SourceViewStageCount => "sourceview/program/stage_count"
              MissingSourceViewRegistrations(_) =>
                "sourceview/program/missing_registration"
              InvalidSourceViewRegistration(_, _) =>
                "sourceview/program/invalid_registration"
              UnsupportedReceipt(_, _) =>
                "sourceview/program/unsupported_receipt"
              LocalInput(_, _) => "sourceview/program/local_input"
              Import(_, _) => "sourceview/program/import"
              Pipeline(_, _) => "sourceview/program/pipeline"
              Collection(_, _) => "sourceview/program/collection"
              Results(_, _) => "sourceview/program/results"
              Order(_, _) => "sourceview/program/order"
              Ports(_, _) => "sourceview/program/ports"
              TableInputs(_, _) => "sourceview/program/table_inputs"
              Wiring(_) => "sourceview/program/wiring"
            },
          )
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(Program(issue))
        ) =>
          fail(
            match issue {
              InvalidLimits => "sourceview/invalid_limits"
              Unavailable => "sourceview/unavailable"
              ForeignEnvironment => "sourceview/foreign_environment"
              ForeignCalendarEnvironment =>
                "sourceview/foreign_calendar_environment"
              CalendarSelection(_) => "sourceview/calendar_selection"
              MissingCalendarArtifact(_) =>
                "sourceview/missing_calendar_artifact"
              MissingCalendarSelection(_, _) =>
                "sourceview/missing_calendar_selection"
              ForeignSource => "sourceview/foreign_source"
              ForeignPartition(_) => "sourceview/foreign_partition"
              BudgetExceeded => "sourceview/budget"
              Program(_) => "sourceview/program"
              Registration(_, _) => "sourceview/registration"
            },
          )
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(Binding(_))
        ) => fail("Source fixture sourceview/binding")
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(Context(Policy(issue)))
        ) =>
          debug_inspect(
            issue,
            content="original Source capacity policy must check",
          )
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(Context(Stages(_)))
        ) => fail("Source fixture sourceview/context/stages")
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(Context(_))
        ) => fail("Source fixture sourceview/context")
        @checked.LocalConstructionFailure::Source(
          @checked.SourceFailure::SourceView(_)
        ) => fail("Source fixture source/sourceview")
        cause => raise cause
      }
      fail("Source fixture check refused")
    }
    Err(_) => fail("Source fixture preparation refused outside checking")
  }
}

///|
test "original unfiltered Program selects Source input without deriving Query capture" {
  let prepared = source_input_unfiltered_program()
  let acquisition = prepare_client_source_acquisition(prepared, 0, 0).unwrap()
  assert_true(
    client_source_acquisition_matches_program(prepared, 0, 0, acquisition),
  )
  assert_false(
    client_source_acquisition_matches_program(prepared, 0, 1, acquisition),
  )
  assert_false(
    client_source_acquisition_matches_program(prepared, 1, 0, acquisition),
  )
  assert_false(
    client_source_acquisition_matches_program(
      source_input_unfiltered_program(),
      0,
      0,
      acquisition,
    ),
  )
  assert_eq(
    @acquisition.source_acquisition_input(acquisition),
    @pipeline.Input(0),
  )
  assert_eq(
    @acquisition.parameterized_request_wire(
      @acquisition.source_acquisition_request(acquisition),
      100,
      10,
      10,
    ).unwrap(),
    "{}",
  )
  assert_true(
    prepare_client_query_acquisition(prepared, 0, 0)
    is Err(UnsupportedAcquisition(@acquisition.UnsupportedShape)),
  )
  assert_true(
    prepare_client_source_acquisition(prepared, -1, 0) is Err(MissingStage),
  )
  assert_true(
    prepare_client_source_acquisition(prepared, 1, 0) is Err(MissingStage),
  )
}

///|
test "original Effect Source input remains bound to its same checked Program" {
  let (_, _, limits) = client_composed_effect_base_fixture()
  let document = bound_effect_source_document.replace(
    old="{\"filter\":{\"gte\":[{\"field\":\"id\"},{\"literal\":0}]}},",
    new="",
  )
  assert_true(document != bound_effect_source_document)
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    source_input_program_environment(),
    None,
    [],
    limits,
  ).unwrap()
  let acquisition = prepare_client_effect_source_acquisition(prepared, 0, 0).unwrap()
  assert_true(
    client_source_acquisition_matches_effect_program(
      prepared, 0, 0, acquisition,
    ),
  )
  assert_false(
    client_source_acquisition_matches_effect_program(
      prepared, 1, 0, acquisition,
    ),
  )
  assert_true(
    prepare_client_effect_query_acquisition(prepared, 0, 0)
    is Err(UnsupportedAcquisition(@acquisition.UnsupportedShape)),
  )
}
