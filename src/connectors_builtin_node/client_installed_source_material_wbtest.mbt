///|
#external
priv type SourceMaterialTestLoader

///|
#module("node:module")
extern "js" fn source_material_test_loader(
  url : String,
) -> SourceMaterialTestLoader = "createRequire"

///|
extern "js" fn source_material_test_url() -> String =
  #|() => import.meta.url

///|
extern "js" fn source_material_test_input() -> ClientLocalPreparationInputOriginal =
  #|() => Object.freeze({sourceMaterialFixture:true})

///|
// Preserve the existing actual Array boundary; no remapping of the quote.
#warnings("-deprecated")
extern "js" fn source_material_test_original(
  loader : SourceMaterialTestLoader,
  input : ClientLocalPreparationInputOriginal,
  quote : Array[Int64],
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,input,quote) => loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(input,{planningWork:Number(quote[0]),attempts:Number(quote[1]),holdings:Number(quote[2]),transferBytes:quote[3],retainedBytes:quote[4],executionBytes:quote[5]},()=>{},()=>false,'local-preparation')

///|
test "Source Node bridge keeps the original initial tuple and typed Environment borrow" {
  // Actual ordinary Node Resource and bridge with an independently owned
  // typed fixture Environment. No normal Source constructor/funding or actual
  // SDK Request, Account, Credential or physical stop is qualified here.
  let environment = keyed_source_environment()
  let prepared = client_program_prepare_public_source_environment(
    environment,
    "{\"environmentCid\":\"" +
    client_program_checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let input = source_material_test_input()
  let initial = client_program_prepare_local_preparation_admission(
    source_material_test_original(
      source_material_test_loader(source_material_test_url()),
      input,
      client_local_preparation_resource_limits(
        client_local_resource_policy_original(),
      ),
    ),
    input,
  ).unwrap()
  let host = client_program_begin_host_initialization_preparation(
    initial,
    input,
    client_local_resource_policy_original(),
  ).unwrap()
  let (original, capacity) = client_program_take_host_initialization_source_capacity(
    host,
  ).unwrap()
  assert_true(physical_equal(original, input))
  assert_true(
    client_program_take_host_initialization_source_capacity(host)
    is Err(@client_local_host.WrongPhase),
  )
  assert_true(
    client_program_continue_installed_source_material(
      capacity,
      source_material_test_input(),
    )
    is Err(@resources.ForeignOriginal),
  )
  let next = client_program_continue_installed_source_material(
    capacity, original,
  ).unwrap()
  let peak = client_program_installed_source_construction_capacity(
    1L, 3L, 8L, 2L, 4L, 9L,
  ).unwrap()
  assert_true(
    client_program_reserve_installed_source_construction(
      next,
      source_material_test_input(),
      peak,
    )
    is Err(@resources.ForeignOriginal),
  )
  client_program_reserve_installed_source_construction(next, original, peak).unwrap()
  let retained = client_program_installed_source_construction_capacity(
    1L, 3L, 8L, 0L, 0L, 0L,
  ).unwrap()
  client_program_reconcile_installed_source_construction(
    next, original, retained,
  ).unwrap()
  client_program_complete_installed_source_material(
    next, original, input, prepared, retained,
  ).unwrap()
  let borrowed = client_program_borrow_installed_source_material(next).unwrap()
  assert_true(
    physical_equal(
      client_program_borrowed_installed_source_environment(borrowed, input).unwrap(),
      prepared,
    ),
  )
  assert_true(
    client_program_borrowed_installed_source_environment(
      borrowed,
      source_material_test_input(),
    )
    is Err(@resources.ForeignOriginal),
  )
  assert_false(
    client_program_retire_installed_source_material(next, original).unwrap(),
  )
  assert_true(
    client_program_close_host_initialization_preparation(host)
    is Err(@client_local_host.WrongPhase),
  )
  assert_true(
    client_program_return_installed_source_material(borrowed).unwrap(),
  )
  assert_true(
    client_program_borrowed_installed_source_environment(borrowed, input)
    is Err(@resources.BorrowReturned),
  )
  client_program_close_host_initialization_preparation(host).unwrap()
}
