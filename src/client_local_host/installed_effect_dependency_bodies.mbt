///|
// Closed managed static group. Every selection/control vector is funded
// before construction; the census emits no wire/hash/admission. Actual owned
// bodies are funded before a fresh canonical pass on the SAME Work counter.
// No Source/Model is executed here and no Account/claim is reconstructed.
pub fn prepare_installed_effect_dependency_bodies(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  inputs : @strategy.CapturedEffectInputs,
  unit : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, @checked.CheckedLocalDependencyBody)],
  ClientInstalledManagedRunIssue,
] {
  let result = prepare_installed_effect_dependency_bodies_original(
    owner, prepared, request, expected_plan, inputs, unit, max_bytes, max_nodes,
    max_depth,
  )
  match result {
    Err(issue) => Err(issue)
    Ok(value) =>
      match
        complete_installed_effect_dependency_construction(
          owner, prepared, request, expected_plan,
        ) {
        Err(issue) => Err(issue)
        Ok(_) => Ok(value)
      }
  }
}

///|
fn prepare_installed_effect_dependency_bodies_original(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  inputs : @strategy.CapturedEffectInputs,
  unit : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, @checked.CheckedLocalDependencyBody)],
  ClientInstalledManagedRunIssue,
] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    owner.source_free_captured is Some(captured) &&
    control.dependency_inputs is Some(original_inputs) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(plan, expected_plan) ||
    !physical_equal(inputs, original_inputs) ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) ||
    !@strategy.captured_effect_inputs_match_captured_run(inputs, captured) ||
    !@strategy.captured_effect_inputs_match_computation(
      inputs,
      @publication_host.prepared_client_effect_computation_graph(prepared),
    ) ||
    !@strategy.captured_effect_inputs_retained(inputs) ||
    max_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 0 ||
    max_depth > 64 {
    return Err(ForeignOriginal)
  }
  let program = @checked.effect_program_static_checked_computation(
    @publication_host.prepared_client_effect_computation_candidate(prepared),
  )
  guard @checked.checked_local_dependency_static_count(program, unit)
    is Some(count) &&
    installed_effect_dependency_fixed_capacity(count, 0, max_depth)
    is Some(fixed) else {
    return Err(InsufficientCapacity)
  }
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, fixed,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let refused : Ref[@resources.LedgerIssue?] = Ref(None)
  let censuses = match
    with_installed_effect_dependency_work(
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
      () => {
        owner.effect_operation_opening &&
        !owner.effect_operation_closing &&
        @strategy.captured_effect_inputs_match_captured_run(inputs, captured)
      },
      spend => {
        let values : Array[(String, @checked.CheckedLocalDependencyCensus)] = []
        for index in 0..<count {
          match spend(1) {
            Err(issue) =>
              return Err(
                @resources.NodeManagedRunOperationIssue::Control(issue),
              )
            Ok(_) => ()
          }
          guard @checked.checked_local_dependency_static_selection(
              program, unit, index,
            )
            is Some((role, kind)) else {
            return Err(
              @resources.NodeManagedRunOperationIssue::Original(ForeignOriginal),
            )
          }
          let value = match
            @checked.census_checked_local_dependency_body(
              program,
              unit,
              kind,
              max_bytes,
              max_nodes,
              max_depth,
              units => {
                match spend(units) {
                  Ok(_) => true
                  Err(issue) => {
                    refused.val = Some(issue)
                    false
                  }
                }
              },
            ) {
            Ok(value) => value
            Err(_) =>
              return Err(
                @resources.NodeManagedRunOperationIssue::Original(Unsupported),
              )
          }
          values.push((role, value))
        }
        Ok(values)
      },
    ) {
    Ok(values) => values
    Err(issue) =>
      return Err(
        match refused.val {
          Some(issue) => Ledger(issue)
          None => installed_effect_operation_reservation_issue(issue)
        },
      )
  }
  // O(1) borrowed lengths and actual count, before owned composite keys,
  // first-occurrence indexes or Maps. This is DATA(kind,CID) only.
  let key_units = match
    with_installed_effect_dependency_work(
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
      () => {
        owner.effect_operation_opening &&
        !owner.effect_operation_closing &&
        @strategy.captured_effect_inputs_match_captured_run(inputs, captured)
      },
      spend => {
        let mut key_units = 0L
        for (role, census) in censuses {
          match spend(1) {
            Err(issue) => return Err(Control(issue))
            Ok(_) => ()
          }
          key_units += role.length().to_int64() +
            @checked.checked_local_dependency_census_cid(census)
            .length()
            .to_int64() +
            1L
        }
        Ok(key_units)
      },
    ).map_err(installed_effect_operation_reservation_issue) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard installed_effect_dependency_key_capacity(count, key_units)
    is Some(keys_capacity) else {
    return Err(InsufficientCapacity)
  }
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, keys_capacity,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (keys, firsts) = match
    with_installed_effect_dependency_work(
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
      () => {
        owner.effect_operation_opening &&
        !owner.effect_operation_closing &&
        @strategy.captured_effect_inputs_match_captured_run(inputs, captured)
      },
      spend => {
        let keys : Array[String] = []
        let firsts : Array[Int] = []
        let seen : Map[String, Int] = Map([])
        for index in 0..<count {
          let (role, census) = censuses[index]
          let cid = @checked.checked_local_dependency_census_cid(census)
          // Concat + hash/lookup over the actual borrowed ASCII coordinate.
          match spend(role.length() + 1) {
            Err(issue) =>
              return Err(
                @resources.NodeManagedRunOperationIssue::Control(issue),
              )
            Ok(_) => ()
          }
          match spend(cid.length()) {
            Err(issue) =>
              return Err(
                @resources.NodeManagedRunOperationIssue::Control(issue),
              )
            Ok(_) => ()
          }
          match spend(role.length() + cid.length() + 2) {
            Err(issue) =>
              return Err(
                @resources.NodeManagedRunOperationIssue::Control(issue),
              )
            Ok(_) => ()
          }
          let key = role + "\u0000" + cid
          keys.push(key)
          match seen.get(key) {
            Some(first) => firsts.push(first)
            None => {
              seen[key] = index
              firsts.push(index)
            }
          }
        }
        Ok((keys, firsts))
      },
    ).map_err(installed_effect_operation_reservation_issue) {
    Ok(values) => values
    Err(issue) => return Err(issue)
  }
  let bodies = match
    with_installed_effect_dependency_work(
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
      () => {
        owner.effect_operation_opening &&
        !owner.effect_operation_closing &&
        @strategy.captured_effect_inputs_match_captured_run(inputs, captured)
      },
      spend => {
        let mut bodies = @execution.execution_capacity(0L, 0L).unwrap()
        // The persistent same-Run cache retains only DATA(kind,CID). A repeated
        // occurrence buys its wrapper, not another raw/tree/canonical body packet.
        for index in 0..<count {
          match spend(1) {
            Err(issue) => return Err(Control(issue))
            Ok(_) => ()
          }
          match spend(keys[index].length()) {
            Err(issue) => return Err(Control(issue))
            Ok(_) => ()
          }
          let geometry = @checked.checked_local_dependency_census_geometry(
            censuses[index].1,
          )
          let already = control.dependency_static.get(keys[index])
          if already is Some((_, original_geometry)) &&
            original_geometry != geometry {
            return Err(Original(ForeignOriginal))
          }
          let added = if firsts[index] == index && already is None {
            installed_effect_dependency_body_capacity(geometry)
          } else {
            installed_effect_dependency_shared_body_capacity()
          }
          guard added is Some(added) &&
            standard_create_sum_capacities(
              [bodies, added],
              sequential_workspace=true,
            )
            is Some(next) else {
            return Err(Original(InsufficientCapacity))
          }
          bodies = next
        }
        Ok(bodies)
      },
    ).map_err(installed_effect_operation_reservation_issue) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, bodies,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
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
    () => {
      owner.effect_operation_opening &&
      !owner.effect_operation_closing &&
      @strategy.captured_effect_inputs_match_captured_run(inputs, captured)
    },
    spend => {
      let values : Array[(String, @checked.CheckedLocalDependencyBody)] = []
      let shared = control.dependency_static
      for index in 0..<count {
        match spend(1) {
          Err(issue) =>
            return Err(@resources.NodeManagedRunOperationIssue::Control(issue))
          Ok(_) => ()
        }
        let (role, census) = censuses[index]
        let body = match
          @checked.emit_censused_checked_local_dependency_body(
            census,
            units => {
              match spend(units) {
                Ok(_) => true
                Err(issue) => {
                  refused.val = Some(issue)
                  false
                }
              }
            },
            shared=shared.get(keys[index]).map(value => value.0),
          ) {
          Ok(body) => body
          Err(_) =>
            return Err(
              @resources.NodeManagedRunOperationIssue::Original(Unsupported),
            )
        }
        // Compare the SAME full canonical wire before sharing. Every distinct
        // source occurrence and every import/interface role remains present.
        shared[keys[index]] = (
          body,
          @checked.checked_local_dependency_census_geometry(census),
        )
        values.push((role, body))
      }
      Ok(values)
    },
  )
  match result {
    Ok(values) => Ok(values)
    Err(issue) =>
      Err(
        match refused.val {
          Some(issue) => Ledger(issue)
          None => installed_effect_operation_reservation_issue(issue)
        },
      )
  }
}
