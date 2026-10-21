///|
test "published Effect parts preserve complete metadata refusal before input parsing" {
  let environment = keyed_source_environment()
  let publication = "{\"environmentCid\":\"" +
    client_program_checking_environment_cid(environment) +
    "\",\"aliases\":[],\"tableWrites\":[],\"updateTargets\":[],\"storeTargets\":[],\"commandTargets\":[]}"
  assert_true(client_program_source_publication_valid(environment, publication))
  assert_true(
    client_program_prepare_published_effect_computation_with_parameters(
      "not a Program",
      "unknown",
      environment,
      publication,
      None,
      [],
    )
    is EffectRejected(Input(InvalidFormat)),
  )
  assert_true(
    client_program_prepare_published_effect_computation_with_parameters(
      "not a Program",
      "json",
      environment,
      publication,
      Some("{"),
      [],
    )
    is EffectRejected(Input(SuppliedSyntax(_))),
  )
  for
    section in [
      "tableWrites", "updateTargets", "storeTargets", "commandTargets",
    ] {
    for body in ["null", "{}", "[{}]"] {
      let invalid = publication.replace(
        old="\"\{section}\":[]",
        new="\"\{section}\":\{body}",
      )
      assert_true(
        !client_program_source_publication_valid(environment, invalid),
      )
      assert_true(
        client_program_prepare_published_effect_computation_with_parameters(
          "not a Program",
          "unknown",
          environment,
          invalid,
          Some("{"),
          [],
        )
        is EffectRejected(Input(SourcePreparation(Publication))),
      )
    }
  }
  let foreign = publication.replace(
    old=client_program_checking_environment_cid(environment),
    new="sha256:" + "0".repeat(64),
  )
  assert_true(!client_program_source_publication_valid(environment, foreign))
  assert_true(
    client_program_prepare_published_effect_computation_with_parameters(
      "not a Program",
      "unknown",
      environment,
      foreign,
      None,
      [],
    )
    is EffectRejected(Input(SourcePreparation(Publication))),
  )
}
