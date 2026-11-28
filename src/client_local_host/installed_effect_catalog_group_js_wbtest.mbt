///|
fn catalog_group_root(
  cid : String,
) -> @publication.CapturedEffectDependencyBody {
  @publication.admit_captured_effect_dependency_body(
    "data_policy",
    None,
    "{\"classification\":\"unknown\",\"source_data_policy_cids\":[\"" +
    cid +
    "\"],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    1000000,
    100000,
    64,
  ).unwrap()
}

///|
// Use the actual same-Run Resource/Work runner. The semantic root is already
// admitted fixture DATA; this exercises construction, not a physical Source
// read, Artifact issuer, public permission or ordinary cold campaign.
fn catalog_group_test_issue(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  roots : Array[@publication.CapturedEffectDependencyBody],
  cold? : Bool = false,
  copies? : Int = 1,
  conflict? : String? = None,
) -> Result[
  (
    @publication.CapturedEffectDependencyInventory,
    @encode.EncodingConstructionGeometry,
  ),
  ClientInstalledManagedRunIssue,
] {
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, original) &&
    physical_equal(original, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) else {
    return Err(ForeignOriginal)
  }
  let refused : Ref[@resources.LedgerIssue?] = Ref(None)
  let grow = capacity => {
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, capacity,
    )
  }
  let segment = fn(
    task : ((Int) -> Bool) -> Result[
      ClientEffectDependencyGroupStep,
      ClientInstalledManagedRunIssue,
    ],
  ) -> Result[ClientEffectDependencyGroupStep, ClientInstalledManagedRunIssue] {
    let result = with_installed_effect_dependency_work(
      control,
      admission,
      plan,
      ledger,
      () => {
        check_installed_effect_operation_original(
          owner,
          ledger,
          preparation,
          Some(control),
        )
      },
      control.reservation,
      () => !owner.effect_operation_closing,
      spend => {
        task(units => {
          match spend(units) {
            Ok(_) => true
            Err(issue) => {
              refused.val = Some(issue)
              false
            }
          }
        }).map_err(issue => {
          @resources.NodeManagedRunOperationIssue::Original(issue)
        })
      },
    )
    result.map_err(issue => {
      match refused.val {
        Some(original) => ClientInstalledManagedRunIssue::Ledger(original)
        None => installed_effect_operation_reservation_issue(issue)
      }
    })
  }
  let kinds = []
  let identities = []
  let wires = []
  for copy in 0..<copies {
    for root in roots {
      kinds.push(@publication.captured_effect_dependency_body_kind(root))
      identities.push(
        Some(@publication.captured_effect_dependency_body_cid(root)),
      )
      wires.push(
        if copy == copies - 1 && conflict is Some(changed) {
          changed
        } else {
          @publication.captured_effect_dependency_body_json(root)
        },
      )
    }
  }
  prepare_funded_effect_dependency_inventory(
    kinds,
    identities,
    wires,
    roots,
    Some(control.dependency_static),
    1000000,
    100000,
    64,
    grow,
    segment,
    catalog_original=if cold {
      None
    } else {
      Some(
        (
          @checked.effect_program_static_checked_computation(
            @publication_host.prepared_client_effect_computation_candidate(
              plan.prepared,
            ),
          ),
          control,
        ),
      )
    },
  )
}

///|
test "COMMON same Run resolves actual missing Catalog from admitted4097 metadata before graph and envelope" {
  let (environment, _) = effect_model_plan_source(catalog_registry_count=4097)
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture(
    current=() => calls.val += 1,
    selected_environment=Some(environment),
  )
  let inputs = pin_installed_effect_sources(
    owner, prepared, request, plan, captured, 64,
  ).unwrap()
  let copied = { ..plan, rows: plan.rows, }
  let before = @resources.ledger_usage(ledger)
  assert_true(
    reserve_installed_effect_dependency_group(
      owner, prepared, request, copied, 1, 1,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  reserve_installed_effect_dependency_group(
    owner, prepared, request, plan, 1, 1,
  ).unwrap()
  let root = catalog_group_root(
    "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf",
  )
  let program = @checked.effect_program_static_checked_computation(
    @publication_host.prepared_client_effect_computation_candidate(prepared),
  )
  assert_eq(
    @environment.member_count(
      @checked.checked_environment(program),
      @environment.ContractRegistry,
    ),
    4097,
  )
  assert_true(
    @checked.checked_local_catalog_dependency_body(
      program, 0, "data_policy", "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf",
      1000000, 100000, 64,
    )
    is Err(BudgetExceeded),
  )
  let before = @resources.ledger_usage(ledger)
  let before_calls = calls.val
  let (inventory, geometry) = catalog_group_test_issue(owner, plan, [root]).unwrap()
  assert_true(calls.val > before_calls && calls.val - before_calls <= 64)
  assert_eq(
    @publication.captured_effect_dependency_inventory_count(inventory),
    2,
  )
  assert_true(geometry.bytes > 0)
  let after = @resources.ledger_usage(ledger)
  assert_true(after.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_eq(after.attempts, before.attempts)
  assert_eq(
    owner.effect_operation_controls.unwrap().dependency_group,
    Some((2, 1)),
  )
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "COMMON missing Catalog and cold absent resolver refuse complete closure without new owners" {
  for cold in [false, true] {
    let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
    let inputs = pin_installed_effect_sources(
      owner, prepared, request, plan, captured, 64,
    ).unwrap()
    reserve_installed_effect_dependency_group(
      owner, prepared, request, plan, 1, 1,
    ).unwrap()
    let root = catalog_group_root(
      if cold {
        "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf"
      } else {
        "sha256:" + "0".repeat(64)
      },
    )
    assert_true(
      catalog_group_test_issue(owner, plan, [root], cold~) is Err(Unsupported),
    )
    assert_eq(
      owner.effect_operation_controls.unwrap().dependency_group,
      Some((1, 1)),
    )
    assert_true(@strategy.release_captured_effect_inputs(inputs))
    assert_true(execution.close())
    retire_installed_managed_run(owner).unwrap()
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  }
}

///|
test "COMMON actual changed current refuses before missing Catalog materialization" {
  let live = Ref(true)
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture(current=() => {
      effect_parent_test_require_current(live.val)
    },
  )
  let inputs = pin_installed_effect_sources(
    owner, prepared, request, plan, captured, 64,
  ).unwrap()
  reserve_installed_effect_dependency_group(
    owner, prepared, request, plan, 1, 1,
  ).unwrap()
  let root = catalog_group_root(
    "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf",
  )
  live.val = false
  assert_true(catalog_group_test_issue(owner, plan, [root]) is Err(Resource(_)))
  live.val = true
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "COMMON small same-Control Resource refuses before missing Catalog materialization" {
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
  let inputs = pin_installed_effect_sources(
    owner, prepared, request, plan, captured, 64,
  ).unwrap()
  reserve_installed_effect_dependency_group(
    owner, prepared, request, plan, 1, 1,
  ).unwrap()
  let root = catalog_group_root(
    "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf",
  )
  let before = @resources.ledger_usage(ledger)
  let control = owner.effect_operation_controls.unwrap()
  let (capacity, idle) = installed_effect_control_capacity(Some(control), plan).unwrap()
  let limits = @resources.ledger_limits(ledger)
  let amount = Int64::min(
    limits.retained_bytes -
    before.reserved_retention_bytes -
    before.held_bytes -
    1L,
    limits.execution_bytes -
    before.reserved_execution_bytes -
    (@execution.execution_capacity_execution_bytes(capacity) - idle) -
    1L,
  )
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, _) else {
    fail("actual original preparation")
  }
  match
    retain_installed_effect_dependency_capacity(
      owner,
      preparation,
      admission,
      plan,
      ledger,
      control,
      @execution.execution_capacity(amount, amount).unwrap(),
    ) {
    Ok(_) => ()
    Err(Ledger(ExecutionLimit)) => fail("pressure execution")
    Err(Ledger(RetentionLimit)) => fail("pressure retention")
    Err(Ledger(ResourceParked)) => fail("pressure parked")
    Err(Ledger(_)) => fail("pressure other Ledger")
    Err(Resource(_)) => fail("pressure Resource")
    Err(_) => fail("pressure original")
  }

  assert_true(
    catalog_group_test_issue(owner, plan, [root])
    is Err(Ledger(ExecutionLimit | RetentionLimit)),
  )
  assert_eq(
    owner.effect_operation_controls.unwrap().dependency_group,
    Some((1, 1)),
  )
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "COMMON exhausted original phase Work refuses before Catalog selection and keeps cleanup exact" {
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
  let inputs = pin_installed_effect_sources(
    owner, prepared, request, plan, captured, 64,
  ).unwrap()
  reserve_installed_effect_dependency_group(
    owner, prepared, request, plan, 1, 1,
  ).unwrap()
  let control = owner.effect_operation_controls.unwrap()
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, _) else {
    fail("actual original preparation")
  }
  // Consume this one finite receipt, rather than replacing the original
  // policy, introducing a second allowance or exposing a remaining getter.
  let spent = with_installed_effect_dependency_work(
    control,
    admission,
    plan,
    ledger,
    () => {
      check_installed_effect_operation_original(
        owner,
        ledger,
        preparation,
        Some(control),
      )
    },
    control.reservation,
    () => !owner.effect_operation_closing,
    _ => {
      let receipt = control.dependency_work.unwrap()
      let debit = (amount : Int) => {
        @resources.spend_preparation_phase_work_continuation64(
          receipt,
          amount.to_int64(),
        )
      }
      let mut chunks = 0
      while debit(2147483647) is Ok(_) {
        chunks += 1
        if chunks > 1024 {
          return Err(Control(InvalidCharge))
        }
      }
      let mut piece = 1073741824
      while piece > 0 {
        debit(piece) |> ignore
        piece = piece / 2
      }
      if debit(1) is Err(WorkLimit) {
        Ok(())
      } else {
        Err(Control(InvalidCharge))
      }
    },
  )
  assert_true(spent is Ok(_))
  let root = catalog_group_root(
    "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf",
  )
  assert_true(
    catalog_group_test_issue(owner, plan, [root]) is Err(Ledger(PlanningLimit)),
  )
  assert_eq(control.dependency_group, Some((1, 1)))
  assert_true(control.dependency_inventory is None)
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_true(owner.effect_operation_controls is None)
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "COMMON repeated exact DATA is quoted once before packet construction while conflicting wire refuses" {
  let text = StringBuilder()
  text.write_string("{\"sort\":\"relation\",\"value\":[{\"document\":\"")
  for _ in 0..<100000 {
    text.write_string("x")
  }
  text.write_string("\"}]}")
  let wire = text.to_string()
  let cid = "sha256:" + @sha.text_hex(wire).unwrap()
  let body = @publication.admit_captured_effect_dependency_body(
    "relation_value",
    Some(cid),
    wire,
    1000000,
    100000,
    64,
  ).unwrap()
  let holds = []
  for copies in [1, 25] {
    let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
    let inputs = pin_installed_effect_sources(
      owner, prepared, request, plan, captured, 64,
    ).unwrap()
    let before = @resources.ledger_usage(ledger).reserved_retention_bytes
    let (inventory, _) = catalog_group_test_issue(
      owner,
      plan,
      [body],
      cold=true,
      copies~,
    ).unwrap()
    assert_eq(
      @publication.captured_effect_dependency_inventory_count(inventory),
      1,
    )
    assert_eq(
      @publication.captured_effect_dependency_inventory_json(inventory),
      "[{\"body\":" +
      wire +
      ",\"cid\":\"" +
      cid +
      "\",\"kind\":\"relation_value\"}]",
    )
    holds.push(
      @resources.ledger_usage(ledger).reserved_retention_bytes - before,
    )
    assert_true(@strategy.release_captured_effect_inputs(inputs))
    assert_true(execution.close())
    retire_installed_managed_run(owner).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
  // Candidate-index metadata scales with references; the identical parser/
  // canonical body does not become 25 coheld copies. No tariff snapshot.
  assert_true(holds[1] > holds[0] && holds[1] < 2L * holds[0])
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
  let inputs = pin_installed_effect_sources(
    owner, prepared, request, plan, captured, 64,
  ).unwrap()
  assert_true(
    catalog_group_test_issue(
      owner,
      plan,
      [body],
      cold=true,
      copies=2,
      conflict=Some("{\"sort\":\"relation\",\"value\":[]}"),
    )
    is Err(ForeignOriginal),
  )
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "dependency graph validation funds edge indexes only while constructing" {
  let no_edges = installed_effect_dependency_graph_capacity(9, 2, 0, 810L).unwrap()
  let with_edges = installed_effect_dependency_graph_capacity(9, 2, 37, 4140L).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(no_edges)
  assert_eq(@execution.execution_capacity_retained_bytes(with_edges), retained)
  assert_true(
    @execution.execution_capacity_execution_bytes(with_edges) >
    @execution.execution_capacity_execution_bytes(no_edges),
  )
  let vectors = @shape.reference_array_retained_extent(2L, 11L).unwrap()
  assert_eq(
    retained,
    @execution.preparation_representation_cost({
      record_headers: vectors.record_headers + 3L,
      reference_slots: vectors.reference_slots + 4L,
      scalar_words: vectors.scalar_words + 13L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap(),
  )
}
