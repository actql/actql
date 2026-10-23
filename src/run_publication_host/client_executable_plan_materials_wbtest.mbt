///|
fn executable_plan_emission_array(
  value : @canonical.CanonicalValue,
  key : String,
) -> Array[@canonical.CanonicalValue] {
  match @canonical.object_field(value, key).unwrap() {
    @canonical.Array(items) => @canonical.array_values(items)
    _ => abort("expected original Plan array")
  }
}

///|
test "original Values and Task compilations retain complete prior Plan emission" {
  for tasks in [false, true] {
    let (_, compiled, _) = local_values_invocation_fixture(tasks)
    let original = match compiled.compilation {
      Values(value) => value.plan
      Tasks(value) => value.plan.plan
      Effects(_) => abort("unexpected Effect compilation")
    }
    let admitted = parse_plan_identity_value(original.wire, 65536, 8192, 64).unwrap()
    let profiles = executable_plan_emission_array(admitted, "required_profiles")
    let parts : ClientExecutablePlanBody = {
      fact_values: executable_plan_emission_array(admitted, "plan_facts"),
      limit_values: executable_plan_emission_array(admitted, "resolved_limits"),
      binding_values: executable_plan_emission_array(admitted, "limit_bindings"),
      witness_values: executable_plan_emission_array(
        admitted, "bound_witnesses",
      ),
      nodes: @canonical.object_field(admitted, "nodes").unwrap(),
      edges: @canonical.object_field(admitted, "data_edges").unwrap(),
      roots: @canonical.object_field(admitted, "root_refs").unwrap(),
      material_value: @canonical.object_field(admitted, "execution_material").unwrap(),
      manifest_cid: compiled_run_plan_field(admitted, "plan_fact_manifest_cid"),
      required_profiles: profiles.map(profile => {
        (
          compiled_run_plan_field(profile, "profile_id"),
          compiled_run_plan_field(profile, "contract_cid"),
        )
      }),
    }
    let expected = Ok((original.wire, original.cid))
    assert_eq(
      reference_executable_plan_emission(parts, 65536, 8192, 64),
      expected,
    )
    assert_eq(
      checked_executable_plan_emission(parts, 65536, 8192, 64),
      expected,
    )
  }
}
