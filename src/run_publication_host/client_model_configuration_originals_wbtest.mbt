///|
// Independent canonical material vectors hashed with Python hashlib.
fn model_configuration_inputs() -> (String, String, String) {
  (
    (
      #|{"revision": "new é\r\n", "provider_id": "models/ordinary", "metadata": {"é": "one", "é": "two"}}
    ),
    (
      #|{"version": "actql-provider-config/0.1", "required": ["model_defaults"]}
    ),
    (
      #|{"model_defaults": {"models": [{"model": "m", "generation_config": {"top_p": 0.875, "temperature": 0.25, "max_output_tokens": 100}}], "default_model": "m"}}
    ),
  )
}

///|
test "normal Model originals preserve data text and feed the existing binding and defaults readers" {
  let (installation, contract, configuration) = model_configuration_inputs()
  let result = prepare_client_model_provider_originals(
    installation, contract, configuration, 4096, 256, 16, 100000,
  ).unwrap()
  assert_eq(
    result.0,
    (
      #|{"metadata":{"é":"two","é":"one"},"provider_id":"models/ordinary","revision":"new é\r\n"}
    ),
  )
  assert_eq(
    result.1,
    "sha256:f146c155a6c7a7219c650a3ebcc806cf6448254189ef186a3b9349201ced509a",
  )
  assert_eq(
    result.2,
    (
      #|{"required":["model_defaults"],"version":"actql-provider-config/0.1"}
    ),
  )
  assert_eq(
    result.3,
    "sha256:9c67957ea14f0163f6502ace6f4e9e743ecebfc0a936b8e7fd7d641026bf260d",
  )
  assert_eq(
    result.4,
    (
      #|{"model_defaults":{"default_model":"m","models":[{"generation_config":{"max_output_tokens":100,"temperature":0.25,"top_p":0.875},"model":"m"}]}}
    ),
  )
  assert_eq(
    result.5,
    "sha256:821a19a8b4546e416b58064e23e676ccdd1823efbbf2d9d3dcde745a807635d7",
  )
  let defaults = read_client_model_provider_defaults(
    "models/ordinary",
    result.0,
    result.2,
    result.4,
    installed_defaults_limits(),
    100000,
  ).unwrap()
  let expected = issue_client_model_provider_binding(
    "models/ordinary",
    result.0,
    result.2,
    result.4,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(
      client_model_provider_defaults_binding(defaults),
    ),
    @publication.run_evidence_value_identity(expected),
  )
  let selected = resolve_client_model_provider_defaults(
    defaults,
    None,
    None,
    1000,
  ).unwrap()
  assert_eq(
    client_model_provider_defaults_generation(defaults, selected).unwrap().max_output_tokens,
    100L,
  )
}

///|
test "normal Model original construction refuses malformed input and insufficient bounds" {
  let (installation, contract, configuration) = model_configuration_inputs()
  assert_true(
    prepare_client_model_provider_originals(
      installation, contract, configuration, 4096, 256, 16, 52223,
    )
    is Err({ kind: @environment.WorkLimit, .. }),
  )
  assert_true(
    prepare_client_model_provider_originals(
      installation, contract, configuration, 65537, 256, 16, 1000000,
    )
    is Err({ kind: @environment.InvalidLimits, .. }),
  )
  assert_true(
    prepare_client_model_provider_originals(
      "not JSON", contract, configuration, 4096, 256, 16, 100000,
    )
    is Err({ kind: @environment.InvalidBody, .. }),
  )
  assert_true(
    prepare_client_model_provider_originals(
      "{\"a\":1,\"a\":2}", contract, configuration, 4096, 256, 16, 100000,
    )
    is Err({ kind: @environment.InvalidBody, .. }),
  )
  assert_true(
    prepare_client_model_provider_originals(
      installation, contract, configuration, 1, 256, 16, 100000,
    )
    is Err({ kind: @environment.BodyLimit, .. }),
  )
  assert_true(
    prepare_client_model_provider_originals(
      installation, contract, configuration, 4096, 1, 16, 100000,
    )
    is Err(_),
  )
  assert_true(
    prepare_client_model_provider_originals(
      installation, contract, configuration, 4096, 256, 1, 100000,
    )
    is Err(_),
  )
}
