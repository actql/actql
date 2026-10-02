// Generated independent Model dependency admission vectors.

///|
test "Model dependency: prompt object" {
  let value = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":{\"format\":\"fixture-risk/0.1\",\"instructions\":\"Classify the text.\"},\"self_cid\":\"sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(
    model_dependency_identity(admitted),
    "sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268",
  )
  assert_eq(model_dependency_usage(admitted), (197, 6, 709))
  let limits : Limits = {
    max_bytes: 197,
    max_nodes: 6,
    max_depth: 20,
    max_members: 3,
  }
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":{\"format\":\"fixture-risk/0.1\",\"instructions\":\"Classify the text.\"},\"self_cid\":\"sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268",
      limits,
      709,
    )
    is Ok(_),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":{\"format\":\"fixture-risk/0.1\",\"instructions\":\"Classify the text.\"},\"self_cid\":\"sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268",
      limits,
      708,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":{\"format\":\"fixture-risk/0.1\",\"instructions\":\"Classify the text.\"},\"self_cid\":\"sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268",
      { ..limits, max_bytes: limits.max_bytes - 1, },
      709,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":{\"format\":\"fixture-risk/0.1\",\"instructions\":\"Classify the text.\"},\"self_cid\":\"sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268",
      { ..limits, max_nodes: limits.max_nodes - 1, },
      709,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Model dependency: prompt null" {
  let value = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":null,\"self_cid\":\"sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(
    model_dependency_identity(admitted),
    "sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56",
  )
  assert_eq(model_dependency_usage(admitted), (136, 4, 526))
  let limits : Limits = {
    max_bytes: 136,
    max_nodes: 4,
    max_depth: 20,
    max_members: 3,
  }
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":null,\"self_cid\":\"sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56",
      limits,
      526,
    )
    is Ok(_),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":null,\"self_cid\":\"sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56",
      limits,
      525,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":null,\"self_cid\":\"sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56",
      { ..limits, max_bytes: limits.max_bytes - 1, },
      526,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":null,\"self_cid\":\"sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:eb8a48012a361caa2a0dbb0925570b04bc732255bf2ebb4cbfe3665dfa6f1c56",
      { ..limits, max_nodes: limits.max_nodes - 1, },
      526,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Model dependency: nested self is payload" {
  let value = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":{\"self_cid\":\"ordinary business data\"},\"self_cid\":\"sha256:62e485910119957d4537cf74663e9653120f26460f5ee3d771d49e2a6e737469\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:62e485910119957d4537cf74663e9653120f26460f5ee3d771d49e2a6e737469",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(
    model_dependency_identity(admitted),
    "sha256:62e485910119957d4537cf74663e9653120f26460f5ee3d771d49e2a6e737469",
  )
  assert_eq(model_dependency_usage(admitted), (169, 5, 625))
  let limits : Limits = {
    max_bytes: 169,
    max_nodes: 5,
    max_depth: 20,
    max_members: 3,
  }
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":{\"self_cid\":\"ordinary business data\"},\"self_cid\":\"sha256:62e485910119957d4537cf74663e9653120f26460f5ee3d771d49e2a6e737469\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:62e485910119957d4537cf74663e9653120f26460f5ee3d771d49e2a6e737469",
      limits,
      625,
    )
    is Ok(_),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":{\"self_cid\":\"ordinary business data\"},\"self_cid\":\"sha256:62e485910119957d4537cf74663e9653120f26460f5ee3d771d49e2a6e737469\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:62e485910119957d4537cf74663e9653120f26460f5ee3d771d49e2a6e737469",
      limits,
      624,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":{\"self_cid\":\"ordinary business data\"},\"self_cid\":\"sha256:62e485910119957d4537cf74663e9653120f26460f5ee3d771d49e2a6e737469\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:62e485910119957d4537cf74663e9653120f26460f5ee3d771d49e2a6e737469",
      { ..limits, max_bytes: limits.max_bytes - 1, },
      625,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(
        "{\"payload\":{\"self_cid\":\"ordinary business data\"},\"self_cid\":\"sha256:62e485910119957d4537cf74663e9653120f26460f5ee3d771d49e2a6e737469\",\"version\":\"actql-model-prompt/0.1\"}",
      ),
      "sha256:62e485910119957d4537cf74663e9653120f26460f5ee3d771d49e2a6e737469",
      { ..limits, max_nodes: limits.max_nodes - 1, },
      625,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Model dependency: no retries" {
  let value = read_model_dependency(
    ModelRetryPolicy,
    @utf8.encode(
      "{\"retryable_failures\":[],\"self_cid\":\"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90\",\"version\":\"actql-model-retry-policy/0.1\"}",
    ),
    "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(
    model_dependency_identity(admitted),
    "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
  )
  assert_eq(model_dependency_usage(admitted), (151, 4, 588))
  let limits : Limits = {
    max_bytes: 151,
    max_nodes: 4,
    max_depth: 20,
    max_members: 3,
  }
  assert_true(
    read_model_dependency(
      ModelRetryPolicy,
      @utf8.encode(
        "{\"retryable_failures\":[],\"self_cid\":\"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90\",\"version\":\"actql-model-retry-policy/0.1\"}",
      ),
      "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
      limits,
      588,
    )
    is Ok(_),
  )
  assert_true(
    read_model_dependency(
      ModelRetryPolicy,
      @utf8.encode(
        "{\"retryable_failures\":[],\"self_cid\":\"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90\",\"version\":\"actql-model-retry-policy/0.1\"}",
      ),
      "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
      limits,
      587,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelRetryPolicy,
      @utf8.encode(
        "{\"retryable_failures\":[],\"self_cid\":\"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90\",\"version\":\"actql-model-retry-policy/0.1\"}",
      ),
      "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
      { ..limits, max_bytes: limits.max_bytes - 1, },
      588,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelRetryPolicy,
      @utf8.encode(
        "{\"retryable_failures\":[],\"self_cid\":\"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90\",\"version\":\"actql-model-retry-policy/0.1\"}",
      ),
      "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
      { ..limits, max_nodes: limits.max_nodes - 1, },
      588,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Model dependency: ordered transient classes" {
  let value = read_model_dependency(
    ModelRetryPolicy,
    @utf8.encode(
      "{\"retryable_failures\":[\"rate_limit\",\"timeout\",\"provider_error\"],\"self_cid\":\"sha256:cf9220e9c88bf3cc1b512b56d05580506cded222e330af22acdc8e84978ddbf6\",\"version\":\"actql-model-retry-policy/0.1\"}",
    ),
    "sha256:cf9220e9c88bf3cc1b512b56d05580506cded222e330af22acdc8e84978ddbf6",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(
    model_dependency_identity(admitted),
    "sha256:cf9220e9c88bf3cc1b512b56d05580506cded222e330af22acdc8e84978ddbf6",
  )
  assert_eq(model_dependency_usage(admitted), (190, 7, 739))
  let limits : Limits = {
    max_bytes: 190,
    max_nodes: 7,
    max_depth: 20,
    max_members: 3,
  }
  assert_true(
    read_model_dependency(
      ModelRetryPolicy,
      @utf8.encode(
        "{\"retryable_failures\":[\"rate_limit\",\"timeout\",\"provider_error\"],\"self_cid\":\"sha256:cf9220e9c88bf3cc1b512b56d05580506cded222e330af22acdc8e84978ddbf6\",\"version\":\"actql-model-retry-policy/0.1\"}",
      ),
      "sha256:cf9220e9c88bf3cc1b512b56d05580506cded222e330af22acdc8e84978ddbf6",
      limits,
      739,
    )
    is Ok(_),
  )
  assert_true(
    read_model_dependency(
      ModelRetryPolicy,
      @utf8.encode(
        "{\"retryable_failures\":[\"rate_limit\",\"timeout\",\"provider_error\"],\"self_cid\":\"sha256:cf9220e9c88bf3cc1b512b56d05580506cded222e330af22acdc8e84978ddbf6\",\"version\":\"actql-model-retry-policy/0.1\"}",
      ),
      "sha256:cf9220e9c88bf3cc1b512b56d05580506cded222e330af22acdc8e84978ddbf6",
      limits,
      738,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelRetryPolicy,
      @utf8.encode(
        "{\"retryable_failures\":[\"rate_limit\",\"timeout\",\"provider_error\"],\"self_cid\":\"sha256:cf9220e9c88bf3cc1b512b56d05580506cded222e330af22acdc8e84978ddbf6\",\"version\":\"actql-model-retry-policy/0.1\"}",
      ),
      "sha256:cf9220e9c88bf3cc1b512b56d05580506cded222e330af22acdc8e84978ddbf6",
      { ..limits, max_bytes: limits.max_bytes - 1, },
      739,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelRetryPolicy,
      @utf8.encode(
        "{\"retryable_failures\":[\"rate_limit\",\"timeout\",\"provider_error\"],\"self_cid\":\"sha256:cf9220e9c88bf3cc1b512b56d05580506cded222e330af22acdc8e84978ddbf6\",\"version\":\"actql-model-retry-policy/0.1\"}",
      ),
      "sha256:cf9220e9c88bf3cc1b512b56d05580506cded222e330af22acdc8e84978ddbf6",
      { ..limits, max_nodes: limits.max_nodes - 1, },
      739,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Model dependency: no backoff" {
  let value = read_model_dependency(
    ModelBackoff,
    @utf8.encode(
      "{\"delays_ms\":[],\"self_cid\":\"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56\",\"version\":\"actql-model-backoff/0.1\"}",
    ),
    "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(
    model_dependency_identity(admitted),
    "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56",
  )
  assert_eq(model_dependency_usage(admitted), (137, 4, 532))
  let limits : Limits = {
    max_bytes: 137,
    max_nodes: 4,
    max_depth: 20,
    max_members: 3,
  }
  assert_true(
    read_model_dependency(
      ModelBackoff,
      @utf8.encode(
        "{\"delays_ms\":[],\"self_cid\":\"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56\",\"version\":\"actql-model-backoff/0.1\"}",
      ),
      "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56",
      limits,
      532,
    )
    is Ok(_),
  )
  assert_true(
    read_model_dependency(
      ModelBackoff,
      @utf8.encode(
        "{\"delays_ms\":[],\"self_cid\":\"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56\",\"version\":\"actql-model-backoff/0.1\"}",
      ),
      "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56",
      limits,
      531,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelBackoff,
      @utf8.encode(
        "{\"delays_ms\":[],\"self_cid\":\"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56\",\"version\":\"actql-model-backoff/0.1\"}",
      ),
      "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56",
      { ..limits, max_bytes: limits.max_bytes - 1, },
      532,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelBackoff,
      @utf8.encode(
        "{\"delays_ms\":[],\"self_cid\":\"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56\",\"version\":\"actql-model-backoff/0.1\"}",
      ),
      "sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56",
      { ..limits, max_nodes: limits.max_nodes - 1, },
      532,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Model dependency: finite backoff" {
  let value = read_model_dependency(
    ModelBackoff,
    @utf8.encode(
      "{\"delays_ms\":[0,125,9007199254740991],\"self_cid\":\"sha256:9c45eb3fb51ccec7834fbebd0f4f18873b68eeec7f6cc588b3deb59f35221d0a\",\"version\":\"actql-model-backoff/0.1\"}",
    ),
    "sha256:9c45eb3fb51ccec7834fbebd0f4f18873b68eeec7f6cc588b3deb59f35221d0a",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(
    model_dependency_identity(admitted),
    "sha256:9c45eb3fb51ccec7834fbebd0f4f18873b68eeec7f6cc588b3deb59f35221d0a",
  )
  assert_eq(model_dependency_usage(admitted), (159, 7, 604))
  let limits : Limits = {
    max_bytes: 159,
    max_nodes: 7,
    max_depth: 20,
    max_members: 3,
  }
  assert_true(
    read_model_dependency(
      ModelBackoff,
      @utf8.encode(
        "{\"delays_ms\":[0,125,9007199254740991],\"self_cid\":\"sha256:9c45eb3fb51ccec7834fbebd0f4f18873b68eeec7f6cc588b3deb59f35221d0a\",\"version\":\"actql-model-backoff/0.1\"}",
      ),
      "sha256:9c45eb3fb51ccec7834fbebd0f4f18873b68eeec7f6cc588b3deb59f35221d0a",
      limits,
      604,
    )
    is Ok(_),
  )
  assert_true(
    read_model_dependency(
      ModelBackoff,
      @utf8.encode(
        "{\"delays_ms\":[0,125,9007199254740991],\"self_cid\":\"sha256:9c45eb3fb51ccec7834fbebd0f4f18873b68eeec7f6cc588b3deb59f35221d0a\",\"version\":\"actql-model-backoff/0.1\"}",
      ),
      "sha256:9c45eb3fb51ccec7834fbebd0f4f18873b68eeec7f6cc588b3deb59f35221d0a",
      limits,
      603,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelBackoff,
      @utf8.encode(
        "{\"delays_ms\":[0,125,9007199254740991],\"self_cid\":\"sha256:9c45eb3fb51ccec7834fbebd0f4f18873b68eeec7f6cc588b3deb59f35221d0a\",\"version\":\"actql-model-backoff/0.1\"}",
      ),
      "sha256:9c45eb3fb51ccec7834fbebd0f4f18873b68eeec7f6cc588b3deb59f35221d0a",
      { ..limits, max_bytes: limits.max_bytes - 1, },
      604,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelBackoff,
      @utf8.encode(
        "{\"delays_ms\":[0,125,9007199254740991],\"self_cid\":\"sha256:9c45eb3fb51ccec7834fbebd0f4f18873b68eeec7f6cc588b3deb59f35221d0a\",\"version\":\"actql-model-backoff/0.1\"}",
      ),
      "sha256:9c45eb3fb51ccec7834fbebd0f4f18873b68eeec7f6cc588b3deb59f35221d0a",
      { ..limits, max_nodes: limits.max_nodes - 1, },
      604,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Model dependency: unknown envelope member" {
  let value = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"extra\":null,\"payload\":{\"format\":\"fixture-risk/0.1\",\"instructions\":\"Classify the text.\"},\"self_cid\":\"sha256:5096324d8bfccdc931254185fd64b8741d978df19b310c1a1e9cc498771131bb\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:5096324d8bfccdc931254185fd64b8741d978df19b310c1a1e9cc498771131bb",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Model dependency: unknown version" {
  let value = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"payload\":{\"format\":\"fixture-risk/0.1\",\"instructions\":\"Classify the text.\"},\"self_cid\":\"sha256:301a4cb2a4bd11a2eac3723eadc39100fc10062196e0404baffbbf277ff49544\",\"version\":\"actql-model-prompt/invalid\"}",
    ),
    "sha256:301a4cb2a4bd11a2eac3723eadc39100fc10062196e0404baffbbf277ff49544",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Model dependency: missing payload" {
  let value = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"self_cid\":\"sha256:593039eb06459fd14ef73579612880a1d8d2554c684bd6d69b646ba66b95c5cb\",\"version\":\"actql-model-prompt/0.1\"}",
    ),
    "sha256:593039eb06459fd14ef73579612880a1d8d2554c684bd6d69b646ba66b95c5cb",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Model dependency: unknown retry class" {
  let value = read_model_dependency(
    ModelRetryPolicy,
    @utf8.encode(
      "{\"retryable_failures\":[\"schema_invalid\"],\"self_cid\":\"sha256:783af78ec5634194cba3f1a7677787f6b42998b8592832daa831c19a0a19e3b3\",\"version\":\"actql-model-retry-policy/0.1\"}",
    ),
    "sha256:783af78ec5634194cba3f1a7677787f6b42998b8592832daa831c19a0a19e3b3",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Model dependency: duplicate retry class" {
  let value = read_model_dependency(
    ModelRetryPolicy,
    @utf8.encode(
      "{\"retryable_failures\":[\"timeout\",\"timeout\"],\"self_cid\":\"sha256:4c895bda30bb0c70cb4a718d29ba96544637184e25e658635d3455d48e86d69c\",\"version\":\"actql-model-retry-policy/0.1\"}",
    ),
    "sha256:4c895bda30bb0c70cb4a718d29ba96544637184e25e658635d3455d48e86d69c",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Model dependency: retry order violation" {
  let value = read_model_dependency(
    ModelRetryPolicy,
    @utf8.encode(
      "{\"retryable_failures\":[\"timeout\",\"rate_limit\"],\"self_cid\":\"sha256:b319ce875eeb6e70e32ec1feb7ff94d7803d0e5c10ef706bd2a323637a13a52e\",\"version\":\"actql-model-retry-policy/0.1\"}",
    ),
    "sha256:b319ce875eeb6e70e32ec1feb7ff94d7803d0e5c10ef706bd2a323637a13a52e",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Model dependency: negative delay" {
  let value = read_model_dependency(
    ModelBackoff,
    @utf8.encode(
      "{\"delays_ms\":[-1],\"self_cid\":\"sha256:d954af173d08bf71a1660276aba0319fa7782e90a89ac8d57fd939c3ff73d473\",\"version\":\"actql-model-backoff/0.1\"}",
    ),
    "sha256:d954af173d08bf71a1660276aba0319fa7782e90a89ac8d57fd939c3ff73d473",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Model dependency: fractional delay" {
  let value = read_model_dependency(
    ModelBackoff,
    @utf8.encode(
      "{\"delays_ms\":[0.5],\"self_cid\":\"sha256:755de3dd163d61c57df58c8a211b60805f4048b17d00b2541f40bb51a759af7f\",\"version\":\"actql-model-backoff/0.1\"}",
    ),
    "sha256:755de3dd163d61c57df58c8a211b60805f4048b17d00b2541f40bb51a759af7f",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Model dependency: unsafe delay" {
  let value = read_model_dependency(
    ModelBackoff,
    @utf8.encode(
      "{\"delays_ms\":[9007199254740992],\"self_cid\":\"sha256:dae89659e96e673dff9653003469773a6493811c14d4834858a3f1de6708166e\",\"version\":\"actql-model-backoff/0.1\"}",
    ),
    "sha256:dae89659e96e673dff9653003469773a6493811c14d4834858a3f1de6708166e",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Model dependency: NULL delay" {
  let value = read_model_dependency(
    ModelBackoff,
    @utf8.encode(
      "{\"delays_ms\":[null],\"self_cid\":\"sha256:d54109ce26a9b5b8f79f9e72f9fa64b8800da47e4a801da2a9c8346b51906af3\",\"version\":\"actql-model-backoff/0.1\"}",
    ),
    "sha256:d54109ce26a9b5b8f79f9e72f9fa64b8800da47e4a801da2a9c8346b51906af3",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Model dependency: wrong role" {
  let value = read_model_dependency(
    ModelPrompt,
    @utf8.encode(
      "{\"retryable_failures\":[],\"self_cid\":\"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90\",\"version\":\"actql-model-retry-policy/0.1\"}",
    ),
    "sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 3, },
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Model dependency rejects reference substitution, body substitution and noncanonical bytes" {
  let wire = "{\"payload\":{\"format\":\"fixture-risk/0.1\",\"instructions\":\"Classify the text.\"},\"self_cid\":\"sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268\",\"version\":\"actql-model-prompt/0.1\"}"
  let pin = "sha256:224ba600372e391b8752faea22afb647ff659fec52b6709b4fea4f3e2fccb268"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 3,
  }
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(wire),
      "sha256:" + "f".repeat(64),
      limits,
      100000,
    )
    is Err({ kind: IdentityMismatch, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(wire.replace(old="Classify", new="Ignore")),
      pin,
      limits,
      100000,
    )
    is Err({ kind: IdentityMismatch, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(" " + wire),
      pin,
      limits,
      100000,
    )
    is Err({ kind: InvalidBody, .. }),
  )
  assert_true(
    read_model_dependency(
      ModelPrompt,
      @utf8.encode(wire),
      pin,
      { ..limits, max_depth: 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}
