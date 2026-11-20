///|
// Actual Local Run/checked preparation and original materials, pure ports only.
// No physical Store, grant, durable admission or execution is claimed here.
test "retained material alias keeps same Plan capture and foreign Plan refusal" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(
    preparation,
    created_at="2026-10-13T00:00:00.001Z",
    valid_until="2026-10-14T00:00:00.001Z",
  )
  let original = capture_local_run_task_materials_original(
    plan,
    environment(),
    environment_wire,
    None,
  ).unwrap()
  assert_true(
    physical_equal(@host.client_task_materials_original_plan(original), plan),
  )
  let wire = export_local_run_materials(
    plan,
    environment(),
    environment_wire,
    None,
  ).unwrap()
  let key = @host.client_request_scope_cid(plan.request)
  let chunks = local_run_task_materials_original_chunks(original)
  let reads = Ref(0)
  let restored = @host.read_client_task_material_with_original(
    key,
    local_run_task_materials_original_cid(original),
    (_, name) => {
      reads.val += 1
      for (chunk_key, body) in chunks {
        if chunk_key == name {
          return Ok(
            Some({ key: name, revision: 0L, body: @utf8.encode(body), }),
          )
        }
      }
      Ok(None)
    },
    "custody",
    Some(original),
  ).unwrap()
  assert_eq(restored, wire)
  assert_eq(reads.val, 4)
  let reference = @host.admit_client_submission_reference_record(
    submitted_rows_reference_wire,
  ).unwrap()
  let prepare = selected => {
    prepare_local_sdk_submitted_run_rows(
      selected,
      preparation,
      reference,
      submitted_rows_before(preparation),
      permit(
        @input.local_submitted_preparation_input(preparation),
        account(Allow),
      ),
      account(Allow),
      tuple(),
      context_cid(),
      1000.0,
      submitted_rows_finite_policy(selected),
      task_materials=Some(original),
    )
  }
  let rows = prepare(plan).unwrap()
  assert_true(
    local_submitted_run_task_materials(rows, plan, preparation) is Ok(Some(_)),
  )
  let foreign = submitted_rows_plan(
    preparation,
    run_id="different nominal Run",
    created_at="2026-10-13T00:00:00.001Z",
    valid_until="2026-10-14T00:00:00.001Z",
  )
  assert_true(prepare(foreign) is Err(ForeignPreparation))
  let equal_preparation = submitted_rows_preparation("SELECT 1 AS n")
  assert_true(
    local_submitted_run_task_materials(rows, plan, equal_preparation)
    is Err(ForeignPreparation),
  )
}
