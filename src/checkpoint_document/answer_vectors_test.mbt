// Independent expected bytes/CIDs from checkpoint-answer-candidates.json.
// No product constructor was used to calculate these frozen expectations.

///|
test "candidate documents preserve six independent profiles preimages signatures and complete wires" {
  {
    let candidate = @checkpoint_document.prepare_answer_candidate(
      "{\"checkpointCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpointId\":\"checkpoint-a\",\"createdAt\":\"2026-11-18T00:00:00.000Z\",\"expiresAt\":\"2026-11-19T00:00:00.000Z\",\"humanSummary\":\"Independent fixture\",\"kind\":\"run_scope\",\"phase\":\"preflight\",\"requiredArtifact\":{\"cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"prepared_invocation\"},\"requirements\":[\"invocation_scope_approved\"],\"reviewProjectionCid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"subject\":{\"kind\":\"prepare_attempt\",\"prepareAttemptId\":\"prepare-a\",\"requestId\":\"request-a\"}}",
      "approved",
      "fixture-key",
      "fixture-reviewer",
      None,
      "2026-11-18T01:02:03.000Z",
      limits(),
    ).unwrap()
    assert_eq(
      @checkpoint_document.answer_candidate_approval_preimage(candidate),
      Some(
        "sha256:c9e85bacb9f463bc44d5f72817045fa25343e4aa42ae2128f49003d5dd41cb80",
      ),
    )
    let resolution = @checkpoint_document.prepare_answer_resolution(
      candidate,
      Some(
        "IH7v4Jm1r2rAfaiYNtsS/Nu4xVd4JYUa6+I478jN+/VnbQKZm3E2qjqfbMUQyCFWTt3GT5o3wBzENhsLe60cDg==",
      ),
    ).unwrap()
    assert_eq(
      @checkpoint_document.answer_resolution_preimage(resolution),
      "sha256:5af4a3c2df6d91856ccc3b26ff2d1c1c80dc4af13e3f61146bb78a50e7799abe",
    )
    assert_eq(
      @checkpoint_document.finish_answer_candidate(
        resolution, "DBH/r1IsSbVoJ6s7/4hvGrPdophBqYNN5KnExxpVQOdo3XsMfYHckUFzo7/jXeZPSGwPhTT0Sgoke9rOge0CDQ==",
      ),
      Ok(
        (
          "sha256:1111111111111111111111111111111111111111111111111111111111111111",
          "{\"actor\":\"fixture-reviewer\",\"approval_evidence_cid\":\"sha256:612e51abac5f2b89e6b33bd561b4693835ed96a97e91302373c016d3e9fced6f\",\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpoint_id\":\"checkpoint-a\",\"decided_at\":\"2026-11-18T01:02:03.000Z\",\"decision\":\"approved\",\"prepare_attempt_id\":\"prepare-a\",\"proof\":{\"key_id\":\"fixture-key\",\"scheme\":\"ed25519-v1\",\"signature\":\"DBH/r1IsSbVoJ6s7/4hvGrPdophBqYNN5KnExxpVQOdo3XsMfYHckUFzo7/jXeZPSGwPhTT0Sgoke9rOge0CDQ==\"},\"required_artifact_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"resolution_cid\":\"sha256:c1f23d2ff803fa651a75c93dfa492437b2bf94873cb5679531b471088ddaef26\",\"resolution_id\":\"resolution-checkpoint-a-approved\",\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-checkpoint-resolution/0.1\"}",
          "{\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"compatibility_approval\":{\"approved_at\":\"2026-11-18T01:02:03.000Z\",\"approver\":\"fixture-reviewer\",\"claim\":\"invocation_scope_approved\",\"expires_at\":\"2026-11-19T00:00:00.000Z\",\"prepared_invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"proof\":{\"key_id\":\"fixture-key\",\"scheme\":\"ed25519-v1\",\"signature\":\"IH7v4Jm1r2rAfaiYNtsS/Nu4xVd4JYUa6+I478jN+/VnbQKZm3E2qjqfbMUQyCFWTt3GT5o3wBzENhsLe60cDg==\"},\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"run_scope_approval_cid\":\"sha256:abf27d9e37f60a854d96ab7f35c9fa1e8649b5707035266ba9f1c350799453de\",\"version\":\"actql-run-scope-approval/0.1\"},\"kind\":\"run_scope\",\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-checkpoint-approval-evidence/0.1\"}",
        ),
      ),
    )
  }
  {
    let candidate = @checkpoint_document.prepare_answer_candidate(
      "{\"checkpointCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpointId\":\"checkpoint-a\",\"createdAt\":\"2026-11-18T00:00:00.000Z\",\"expiresAt\":\"2026-11-19T00:00:00.000Z\",\"humanSummary\":\"Independent fixture\",\"kind\":\"read_access\",\"phase\":\"preflight\",\"requiredArtifact\":{\"cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"read_scope\"},\"requirements\":[\"invocation_scope_approved\"],\"reviewProjectionCid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"subject\":{\"kind\":\"prepare_attempt\",\"prepareAttemptId\":\"prepare-a\",\"requestId\":\"request-a\"}}",
      "rejected",
      "fixture-key",
      "fixture-reviewer",
      None,
      "2026-11-18T01:02:03.000Z",
      limits(),
    ).unwrap()
    assert_eq(
      @checkpoint_document.answer_candidate_approval_preimage(candidate),
      None,
    )
    let resolution = @checkpoint_document.prepare_answer_resolution(
      candidate,
      None,
    ).unwrap()
    assert_eq(
      @checkpoint_document.answer_resolution_preimage(resolution),
      "sha256:3474c3ab5be1cfb5bce4f63ad2d21279d38e0ed07e0e48356474733f76e72ab3",
    )
    assert_eq(
      @checkpoint_document.finish_answer_candidate(
        resolution, "DAdWDWe55gfEWzzqa+j0o/zJSy64c3/pMdisfwZWaLynfuycTsSfxzg4pSIsq4nHbT4X5j0XbOCd/X6owrOkDw==",
      ),
      Ok(
        (
          "sha256:1111111111111111111111111111111111111111111111111111111111111111",
          "{\"actor\":\"fixture-reviewer\",\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpoint_id\":\"checkpoint-a\",\"decided_at\":\"2026-11-18T01:02:03.000Z\",\"decision\":\"rejected\",\"prepare_attempt_id\":\"prepare-a\",\"proof\":{\"key_id\":\"fixture-key\",\"scheme\":\"ed25519-v1\",\"signature\":\"DAdWDWe55gfEWzzqa+j0o/zJSy64c3/pMdisfwZWaLynfuycTsSfxzg4pSIsq4nHbT4X5j0XbOCd/X6owrOkDw==\"},\"required_artifact_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"resolution_cid\":\"sha256:7e34104ca29f10f1d9382f72ec72f0c3b90711f600cf225fe54808362fe40ee9\",\"resolution_id\":\"resolution-checkpoint-a-rejected\",\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-checkpoint-resolution/0.1\"}",
          "",
        ),
      ),
    )
  }
  {
    let candidate = @checkpoint_document.prepare_answer_candidate(
      "{\"checkpointCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpointId\":\"checkpoint-a\",\"createdAt\":\"2026-11-18T00:00:00.000Z\",\"expiresAt\":\"2026-11-19T00:00:00.000Z\",\"humanSummary\":\"Independent fixture\",\"kind\":\"read_access\",\"phase\":\"preflight\",\"requiredArtifact\":{\"cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"read_scope\"},\"requirements\":[\"invocation_scope_approved\"],\"reviewProjectionCid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"subject\":{\"kind\":\"prepare_attempt\",\"prepareAttemptId\":\"prepare-a\",\"requestId\":\"request-a\"}}",
      "approved",
      "fixture-key",
      "fixture-reviewer",
      None,
      "2026-11-18T01:02:03.000Z",
      limits(),
    ).unwrap()
    assert_eq(
      @checkpoint_document.answer_candidate_approval_preimage(candidate),
      Some(
        "sha256:c9e85bacb9f463bc44d5f72817045fa25343e4aa42ae2128f49003d5dd41cb80",
      ),
    )
    let resolution = @checkpoint_document.prepare_answer_resolution(
      candidate,
      Some(
        "IH7v4Jm1r2rAfaiYNtsS/Nu4xVd4JYUa6+I478jN+/VnbQKZm3E2qjqfbMUQyCFWTt3GT5o3wBzENhsLe60cDg==",
      ),
    ).unwrap()
    assert_eq(
      @checkpoint_document.answer_resolution_preimage(resolution),
      "sha256:7127e4922425904d95db1b740b4028f171a5a1960209a1132bb8832e283b8a99",
    )
    assert_eq(
      @checkpoint_document.finish_answer_candidate(
        resolution, "PkebJt28LWSlgqxpAfj7g5jXUwRqapnUg0F5NCRu96NXmnObUHfbi8ZuUO6OMHoT1t+uQte8bWA8ImNiGCO2Cg==",
      ),
      Ok(
        (
          "sha256:1111111111111111111111111111111111111111111111111111111111111111",
          "{\"actor\":\"fixture-reviewer\",\"approval_evidence_cid\":\"sha256:9759b21bf6d5a14288bd0c6de07a1b9d6928cf5d1926f5854c217d1cfa504391\",\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpoint_id\":\"checkpoint-a\",\"decided_at\":\"2026-11-18T01:02:03.000Z\",\"decision\":\"approved\",\"prepare_attempt_id\":\"prepare-a\",\"proof\":{\"key_id\":\"fixture-key\",\"scheme\":\"ed25519-v1\",\"signature\":\"PkebJt28LWSlgqxpAfj7g5jXUwRqapnUg0F5NCRu96NXmnObUHfbi8ZuUO6OMHoT1t+uQte8bWA8ImNiGCO2Cg==\"},\"required_artifact_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"resolution_cid\":\"sha256:2ead77aa066aec55cb7dfe9209941e52917e442a8b475fbaf265bef4bf426bdf\",\"resolution_id\":\"resolution-checkpoint-a-approved\",\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-checkpoint-resolution/0.1\"}",
          "{\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"compatibility_approval\":{\"approved_at\":\"2026-11-18T01:02:03.000Z\",\"approver\":\"fixture-reviewer\",\"claim\":\"invocation_scope_approved\",\"expires_at\":\"2026-11-19T00:00:00.000Z\",\"prepared_invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"proof\":{\"key_id\":\"fixture-key\",\"scheme\":\"ed25519-v1\",\"signature\":\"IH7v4Jm1r2rAfaiYNtsS/Nu4xVd4JYUa6+I478jN+/VnbQKZm3E2qjqfbMUQyCFWTt3GT5o3wBzENhsLe60cDg==\"},\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"run_scope_approval_cid\":\"sha256:abf27d9e37f60a854d96ab7f35c9fa1e8649b5707035266ba9f1c350799453de\",\"version\":\"actql-run-scope-approval/0.1\"},\"kind\":\"read_access\",\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-checkpoint-approval-evidence/0.1\"}",
        ),
      ),
    )
  }
  {
    let candidate = @checkpoint_document.prepare_answer_candidate(
      "{\"checkpointCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpointId\":\"checkpoint-a\",\"createdAt\":\"2026-11-18T00:00:00.000Z\",\"expiresAt\":\"2026-11-19T00:00:00.000Z\",\"humanSummary\":\"Independent fixture\",\"kind\":\"read_access\",\"phase\":\"preflight\",\"requiredArtifact\":{\"cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"read_scope\"},\"requirements\":[\"invocation_scope_approved\"],\"reviewProjectionCid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"subject\":{\"kind\":\"run_unit\",\"runDefinitionCid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"runId\":\"run-a\"}}",
      "approved",
      "fixture-key",
      "fixture-reviewer",
      None,
      "2026-11-18T01:02:03.000Z",
      limits(),
    ).unwrap()
    assert_eq(
      @checkpoint_document.answer_candidate_approval_preimage(candidate),
      Some(
        "sha256:c9e85bacb9f463bc44d5f72817045fa25343e4aa42ae2128f49003d5dd41cb80",
      ),
    )
    let resolution = @checkpoint_document.prepare_answer_resolution(
      candidate,
      Some(
        "IH7v4Jm1r2rAfaiYNtsS/Nu4xVd4JYUa6+I478jN+/VnbQKZm3E2qjqfbMUQyCFWTt3GT5o3wBzENhsLe60cDg==",
      ),
    ).unwrap()
    assert_eq(
      @checkpoint_document.answer_resolution_preimage(resolution),
      "sha256:9903cd375dc04d27b35d56badcba5a8aa0ee88cb695024258c9c2bfd03f37917",
    )
    assert_eq(
      @checkpoint_document.finish_answer_candidate(
        resolution, "LhLu8g+w0SZJ84VA5ia7yG/4jME7c+HHf7rY58tlHoDA5edJNIxZ4+6j4ZTTpovOcgLrA/jdugkSLzwBypznCA==",
      ),
      Ok(
        (
          "sha256:1111111111111111111111111111111111111111111111111111111111111111",
          "{\"actor\":\"fixture-reviewer\",\"approval_evidence_cid\":\"sha256:9759b21bf6d5a14288bd0c6de07a1b9d6928cf5d1926f5854c217d1cfa504391\",\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpoint_id\":\"checkpoint-a\",\"decided_at\":\"2026-11-18T01:02:03.000Z\",\"decision\":\"approved\",\"proof\":{\"key_id\":\"fixture-key\",\"scheme\":\"ed25519-v1\",\"signature\":\"LhLu8g+w0SZJ84VA5ia7yG/4jME7c+HHf7rY58tlHoDA5edJNIxZ4+6j4ZTTpovOcgLrA/jdugkSLzwBypznCA==\"},\"required_artifact_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"resolution_cid\":\"sha256:dcde44e9cd21e864b873bae54ded3b353dcab94634182bac5eebef3f6cd3d048\",\"resolution_id\":\"resolution-checkpoint-a-approved\",\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"run_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"run_id\":\"run-a\",\"version\":\"actql-checkpoint-resolution/0.1\"}",
          "{\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"compatibility_approval\":{\"approved_at\":\"2026-11-18T01:02:03.000Z\",\"approver\":\"fixture-reviewer\",\"claim\":\"invocation_scope_approved\",\"expires_at\":\"2026-11-19T00:00:00.000Z\",\"prepared_invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"proof\":{\"key_id\":\"fixture-key\",\"scheme\":\"ed25519-v1\",\"signature\":\"IH7v4Jm1r2rAfaiYNtsS/Nu4xVd4JYUa6+I478jN+/VnbQKZm3E2qjqfbMUQyCFWTt3GT5o3wBzENhsLe60cDg==\"},\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"run_scope_approval_cid\":\"sha256:abf27d9e37f60a854d96ab7f35c9fa1e8649b5707035266ba9f1c350799453de\",\"version\":\"actql-run-scope-approval/0.1\"},\"kind\":\"read_access\",\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-checkpoint-approval-evidence/0.1\"}",
        ),
      ),
    )
  }
  {
    let candidate = @checkpoint_document.prepare_answer_candidate(
      "{\"checkpointCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpointId\":\"checkpoint-a\",\"createdAt\":\"2026-11-18T00:00:00.000Z\",\"expiresAt\":\"2026-11-19T00:00:00.000Z\",\"humanSummary\":\"Independent fixture\",\"kind\":\"effect_set\",\"phase\":\"commit\",\"requiredArtifact\":{\"cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"effect_set_preview\"},\"requirements\":[\"effect_scope_approved\",\"partial_application_accepted\"],\"reviewProjectionCid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"subject\":{\"kind\":\"run_unit\",\"runDefinitionCid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"runId\":\"run-a\"}}",
      "approved",
      "fixture-key",
      "fixture-reviewer",
      Some(
        "sha256:5555555555555555555555555555555555555555555555555555555555555555",
      ),
      "2026-11-18T01:02:03.000Z",
      limits(),
    ).unwrap()
    assert_eq(
      @checkpoint_document.answer_candidate_approval_preimage(candidate),
      Some(
        "sha256:dbfacb50e4bd46eda672cf68fb0f7575baedbed102904eb5c38701d3ce2d2e59",
      ),
    )
    let resolution = @checkpoint_document.prepare_answer_resolution(
      candidate,
      Some(
        "Mq8ZWkAph8E/yQUgclNcOf42xXIkD0zS6EF3aRbQu04V8LSTEUCw1WU/nTq1+4U4AbbYVbTBUeXJrxgIDk9TDQ==",
      ),
    ).unwrap()
    assert_eq(
      @checkpoint_document.answer_resolution_preimage(resolution),
      "sha256:1553d446e0cdf3929de76ed08e84e9db7c05680b5f980aac5ff96f5a568597bb",
    )
    assert_eq(
      @checkpoint_document.finish_answer_candidate(
        resolution, "RiCPT2Z/hwcO4So5ollmxd21nXRXnXiFY+TOGn6aGBlbJ6W+GcvnW34MUNbSdbo9WTSOHIGvBo2BGmlYOUrdBA==",
      ),
      Ok(
        (
          "sha256:1111111111111111111111111111111111111111111111111111111111111111",
          "{\"actor\":\"fixture-reviewer\",\"approval_evidence_cid\":\"sha256:fee5c50200118603ff4ccd4ffe25bb108f2fa9206c3f9b0fa62f74163c449d99\",\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpoint_id\":\"checkpoint-a\",\"decided_at\":\"2026-11-18T01:02:03.000Z\",\"decision\":\"approved\",\"proof\":{\"key_id\":\"fixture-key\",\"scheme\":\"ed25519-v1\",\"signature\":\"RiCPT2Z/hwcO4So5ollmxd21nXRXnXiFY+TOGn6aGBlbJ6W+GcvnW34MUNbSdbo9WTSOHIGvBo2BGmlYOUrdBA==\"},\"required_artifact_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"resolution_cid\":\"sha256:44a50d96e5c27672f40bc4030bec42e01edf5a0f089cef780d6e12a9ca0e8ff2\",\"resolution_id\":\"resolution-checkpoint-a-approved\",\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"run_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"run_id\":\"run-a\",\"version\":\"actql-checkpoint-resolution/0.1\"}",
          "{\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"compatibility_approval\":{\"approved_at\":\"2026-11-18T01:02:03.000Z\",\"approver\":\"fixture-reviewer\",\"attestation_cid\":\"sha256:d53f6bfc63c54c32383b7128967dc3de0dd6413c5b0805fe85a8346190ffd8d1\",\"authority_scope_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"claims\":[\"effect_scope_approved\",\"partial_application_accepted\"],\"effect_preview_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"proof\":{\"key_id\":\"fixture-key\",\"scheme\":\"ed25519-v1\",\"signature\":\"Mq8ZWkAph8E/yQUgclNcOf42xXIkD0zS6EF3aRbQu04V8LSTEUCw1WU/nTq1+4U4AbbYVbTBUeXJrxgIDk9TDQ==\"},\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-approval-attestation/0.1\"},\"kind\":\"effect_set\",\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-checkpoint-approval-evidence/0.1\"}",
        ),
      ),
    )
  }
  let candidate = @checkpoint_document.prepare_answer_candidate(
    "{\"checkpointCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpointId\":\"checkpoint-a\",\"createdAt\":\"2026-11-18T00:00:00.000Z\",\"expiresAt\":\"2026-11-19T00:00:00.000Z\",\"humanSummary\":\"Independent fixture\",\"kind\":\"model_invocation\",\"phase\":\"preflight\",\"preparedInvocationCid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"requiredArtifact\":{\"cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"model_invocation_scope\"},\"requirements\":[\"invocation_scope_approved\"],\"reviewProjectionCid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"subject\":{\"kind\":\"run_unit\",\"runDefinitionCid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"runId\":\"run-a\"}}",
    "approved",
    "fixture-key",
    "fixture-reviewer",
    None,
    "2026-11-18T01:02:03.000Z",
    limits(),
  ).unwrap()
  assert_eq(
    @checkpoint_document.answer_candidate_approval_preimage(candidate),
    Some(
      "sha256:482c80dabc793da2add402ad7aa51fe9139516e306cd782ef9c402ecc2231763",
    ),
  )
  let resolution = @checkpoint_document.prepare_answer_resolution(
    candidate,
    Some(
      "EAtMzLrgJQMdEfPQX9ceM6S+x6he8ahzRRzhSSFZU8p2KdyYon29XtFPPSKbG8hWeZCUcqC48D59AsiRac+TBw==",
    ),
  ).unwrap()
  assert_eq(
    @checkpoint_document.answer_resolution_preimage(resolution),
    "sha256:9b9d4eb200ac5979271afdd2119a80203150901879a60f8992568c3d673ca3a8",
  )
  assert_eq(
    @checkpoint_document.finish_answer_candidate(
      resolution, "wj1Bza37+1r0T3yAiFccSQKlYMcYBWMDTVo+p+zn6LUS3n2nULqdKoWo7+aU3x963JRzVyJYupM+XLJRgEi+Dw==",
    ),
    Ok(
      (
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        "{\"actor\":\"fixture-reviewer\",\"approval_evidence_cid\":\"sha256:f1c5ecb8d3e7a8dc09b0dcdf22db55288e88a3c28437e04c2a6fae2e774404c1\",\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpoint_id\":\"checkpoint-a\",\"decided_at\":\"2026-11-18T01:02:03.000Z\",\"decision\":\"approved\",\"proof\":{\"key_id\":\"fixture-key\",\"scheme\":\"ed25519-v1\",\"signature\":\"wj1Bza37+1r0T3yAiFccSQKlYMcYBWMDTVo+p+zn6LUS3n2nULqdKoWo7+aU3x963JRzVyJYupM+XLJRgEi+Dw==\"},\"required_artifact_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"resolution_cid\":\"sha256:42d33d1a05a90b579835e296847326b27d04a9f4bb0ddf0e602dea110e730cd7\",\"resolution_id\":\"resolution-checkpoint-a-approved\",\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"run_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"run_id\":\"run-a\",\"version\":\"actql-checkpoint-resolution/0.1\"}",
        "{\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"compatibility_approval\":{\"approved_at\":\"2026-11-18T01:02:03.000Z\",\"approver\":\"fixture-reviewer\",\"claim\":\"invocation_scope_approved\",\"expires_at\":\"2026-11-19T00:00:00.000Z\",\"prepared_invocation_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"proof\":{\"key_id\":\"fixture-key\",\"scheme\":\"ed25519-v1\",\"signature\":\"EAtMzLrgJQMdEfPQX9ceM6S+x6he8ahzRRzhSSFZU8p2KdyYon29XtFPPSKbG8hWeZCUcqC48D59AsiRac+TBw==\"},\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"run_scope_approval_cid\":\"sha256:521808e23267a50762c55e069a6fd31f41abde0004e2e5b5b4fb75ee2e595c36\",\"version\":\"actql-run-scope-approval/0.1\"},\"kind\":\"model_invocation\",\"review_projection_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"version\":\"actql-checkpoint-approval-evidence/0.1\"}",
      ),
    ),
  )
}
