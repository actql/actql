// A reviewed finite input policy, not a general package-language parser.
// At this revision these literal options contain only native stubs, native
// linker settings and native/not-native file predicates. For the pinned Moon
// JS execution path they select bound source files but cannot run a native
// linker/stub compiler. All package/source bytes and memberships remain inputs.
// The current import/custody split is reviewed in
// docs/reviews/2026-10-10-session-package-configuration-review.md and
// docs/reviews/2026-10-11-session-local-import-configuration-review.md.
// The current Native custody predicates are reviewed in
// docs/reviews/2026-10-12-session-native-custody-configuration-review.md and
// docs/reviews/2026-10-14-session-native-config-refresh-review.md and
// docs/reviews/2026-10-14-session-native-constructor-config-review.md and
// docs/reviews/2026-10-14-session-native-store-failure-scope-review.md and
// docs/reviews/2026-10-14-session-transfer-journal-selector-review.md and
// docs/reviews/2026-10-14-session-directory-census-config-review.md and
// docs/reviews/2026-10-14-session-package-observation-config-review.md and
// docs/reviews/2026-10-14-session-native-http-failure-scope-review.md and
// docs/reviews/2026-10-14-session-site-journal-custody-configuration-review.md and
// docs/reviews/2026-10-14-session-bundle-store-retirement-configuration-review.md and
// docs/reviews/2026-10-15-bounded-root-custody-configuration-review.md and
// docs/reviews/2026-10-15-filesystem-read-layout-configuration-review.md and
// docs/reviews/2026-10-15-scoped-filesystem-acquisition-configuration-review.md and
// docs/reviews/2026-10-15-scoped-bounded-read-configuration-review.md and
// docs/reviews/2026-10-15-sqlite-body-limit-configuration-review.md and
// docs/reviews/2026-10-15-filesystem-child-custody-configuration-review.md and
// docs/reviews/2026-10-15-bounded-catalog-configuration-review.md and
// docs/reviews/2026-11-07-session-source-counts-configuration-review.md.
// Changes to this table, the toolchain or any configuration force fresh work.
// Unknown options and other targets require separate review; matching a digest
// is configuration identity, not a proof of compiler or OS correctness.
// A separate exact JS foreign-library review is recorded below; it does not
// inherit the native-options rule or authorize arbitrary package kinds.
export const packageConfigurationReview = Object.freeze({
  revision: '202aed1b7f33bb825d8b5c3e9c313a80f04d6f7f',
  target: 'js',
  toolchainDigest: '8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a',
  moonRevision: '94521db',
  rule: 'literal-native-options-with-bound-source-membership',
});

export const reviewedPackageConfigurations = Object.freeze({
  'src/platform_native/bounded_files/moon.pkg': '383a532bbbee2be32d5c4c7ccab853fa392892667451095a7b553c495d5c578d',
  'src/native_values_integration/moon.pkg': '7e6c593d713e34a6c57ef95eae7e29f483b63a9f7f4ab2804e0d5106b1d009c5',
  'src/connectors/duckdb/adapters/native/moon.pkg': '7283cc7667b9293a7132672ce9edf375901ffb35eb02e25af9eb9eba55a1e89d',
  'src/platform_native/filesystem/moon.pkg': 'a39f92dff1dba87ca4d59dfdcc3fb81ea4167b4f3e48c36bba69b9f28bda44e9',
  'src/platform_native/http_client/moon.pkg': '3cdde0301c89f7a3a2c79aca654cfb4c48b49751847561c27a8e88232e099baf',
  'src/platform_native/https_server/moon.pkg': '880ad74137ab58e0f92f43465f9bc2bcd096eb2b29461b9f93d68883ed5d22bd',
  'src/platform_native/publication_store/moon.pkg': 'da2ed748a2cee398537d8be64de7e695446009fcdce04a6cf09ec69f0d9f0fa0',
  'src/platform_native/result_access/moon.pkg': '0ed904ab54effb2f116b1eb3b7b285f20c94ec75ce099b93f47f4a08377a0d37',
  'src/platform_native/remote_client/moon.pkg': '4ab04b27d2c7be75c9d5521f3e2e0d53d8cc8d8d612cb6cbb13115b240eafb6e',
  'src/platform_native/remote_journal/moon.pkg': 'c83f1565e76f17043331ef9220ad6e0811f5699a0b537f13e3280aed857c8b9f',
  'src/platform_native/remote_standard_host/moon.pkg': '14c80ec28c7c4f706f8aa55c2a73fa0c2f3023c4f91d4cb016094d0170b04f87',
  'src/platform_native/remote_transfer_client/moon.pkg': 'b026d1ada91a1f113c33df63fae999c0a05e197b2b50b0d29d9e7258d830baeb',
  'src/platform_native/remote_transfer_journal/moon.pkg': '4af6a1f153011554ab829bb6b494cbd8a8cf32110ed39f66de7c7974993411b5',
  'src/platform_native/retained_task_file/moon.pkg': 'e3050859982bfa2a176e04f44c08dcf073be7405e42be6f0af81f51a680347de',
  'src/platform_native/runtime_bundle/moon.pkg': '4a6441d96a441ac67adf1f38d806ae59bf4936217faf2b8269310f2e500aac00',
  'src/platform_native/signature/moon.pkg': '7d5f82f21d707d93d0ad352324cbdc65b7b4eebe6c8456413430699ff084eab3',
  'src/platform_native/sqlite/moon.pkg': 'f05438392188f1d1f2c08a6872f25e07c782ec6fbc3b9769c09b155b564face5',
  'src/query_integration/moon.pkg': 'eeeb572afaf8f9b708362db6308b080cc715e65601d54f3ff53d8e1a01f65966',
});

// See docs/reviews/2026-10-13-session-js-foreign-library-configuration-review.md and
// docs/reviews/2026-10-14-session-js-foreign-library-refresh-review.md.
// This literal kind force-links a JS artifact; it contains no build hook or
// external source resolver. Imports and every source member remain keyed.
export const foreignLibraryConfigurationReview = Object.freeze({
  revision: '55ea9534de476e7e9308da349b8afd072bc8426d',
  target: 'js',
  toolchainDigest: packageConfigurationReview.toolchainDigest,
  moonRevision: packageConfigurationReview.moonRevision,
  rule: 'literal-js-foreign-library-with-bound-source-membership',
});
const foreignLibraryConfigurations = Object.freeze({
  'src/connectors_builtin_node/moon.pkg': '1e8b80ac31bd7af9eb61dd9b0dc1b1f40542083217ffea09be4a7e7cfcf4f43c',
});

// Current successor review is separate from every retained historical cohort.
// See docs/reviews/2026-10-25-session-current-configuration-review.json.
// Current updates: docs/reviews/2026-11-02-session-current-input-review.md and
// docs/reviews/2026-11-03-session-current-input-successor-review.md and
// docs/reviews/2026-11-04-session-current-recovery-configuration-review.md and
// docs/reviews/2026-11-06-session-source-test-target-review.md and
// docs/reviews/2026-11-07-session-local-host-successor-review.md and
// docs/reviews/2026-11-08-session-whole-input-text-target-review.md and
// docs/reviews/2026-11-08-session-original-effect-selector-review.md and
// docs/reviews/2026-11-09-session-native-keyed-plan-selector-review.md and
// docs/reviews/2026-11-09-session-native-delivery-chunk-selector-review.md.
// Constants below are reviewed bytes, never hashes computed from current files.
// A per-entry revision records only that exact reviewed input; the default
// revision still applies to every unchanged entry.
export const currentConfigurationReviewRevision = '38e95bfac2907700456de6c53ed0cad3620bb72d';
export const currentPackageConfigurations = Object.freeze({
  'src/client_local_host/moon.pkg': Object.freeze({digest: '1ce3256e4f3b1dc32ee5136fcbbe5076fd996ad0a05c901a5cd175a3b16af326', rule: 'literal-target-selectors-with-bound-source-membership', revision: 'db039dc07a845fc420be9f95b750fe5208183735'}),
  'src/connectors_builtin_node/moon.pkg': Object.freeze({digest: 'd515c9868140c30ef68b5778b71863813cad0d53cc7300e4ba8fcc3e00405d9d', rule: 'literal-js-foreign-library-with-bound-source-membership', revision: '6f27dfdf10aa232977277ec8580557463e44e81f'}),
  'src/execution_relation/moon.pkg': Object.freeze({digest: '2a223e06a52cbb8c01280e9d5c5132485434728f59271ff02900f74ea582d079', rule: 'literal-target-selectors-with-bound-source-membership', revision: '6813ab0330a17f99c8eef5c9f4a70480ecc7e96c'}),
  'src/native_values_integration/moon.pkg': Object.freeze({digest: 'aa3777f1835f552da0ea34a13bbcb0de9afeb6c96adeadfbb26b483ce683c54f', rule: 'literal-native-options-with-bound-source-membership'}),
  'src/physical_resources/moon.pkg': Object.freeze({digest: '508d45513dd76478ece212cd3e9a2da45aa93f2e100d99c44076a31afa46be23', rule: 'literal-target-selectors-with-bound-source-membership', revision: 'bf198225499436c26be2f7d763582b0efaeeae2b'}),
  'src/platform_native/bounded_files/moon.pkg': Object.freeze({digest: '9dcccf37816250ccb794c1467658f3cd4c2ff239ed752b36e59ef167a40553a5', rule: 'literal-native-options-with-bound-source-membership'}),
  'src/platform_native/filesystem/moon.pkg': Object.freeze({digest: 'ccbef60792340068be1ef431d1f8a7336a842dcd1021a84a816c3582a7c6b08b', rule: 'literal-native-options-with-bound-source-membership'}),
  'src/platform_native/http_client/moon.pkg': Object.freeze({digest: '67cf437063d4a099acc9d33736d48fb3cfbff4cd4efa3235dc0239121ee6455e', rule: 'literal-native-options-with-bound-source-membership', revision: '523ada3259bf9e8147f746727fbfd56065036fd5'}),
  'src/platform_native/publication_store/moon.pkg': Object.freeze({digest: 'dfaf6105d166e28289190c97a9aae16bf4eff037da5cbcd5fa767aeb2ebc8598', rule: 'literal-native-options-with-bound-source-membership', revision: '3feeecd4936fcf156d8b5293354332813913e59f'}),
  'src/platform_native/remote_client/moon.pkg': Object.freeze({digest: '2d564b643659ca806c35da2414f432b52292fa8c79a94cffc0706191ae156832', rule: 'literal-native-options-with-bound-source-membership', revision: 'deea413fba8b255cf5be7300d94eccd883b5b5eb'}),
  'src/platform_native/remote_journal/moon.pkg': Object.freeze({digest: '89432a0cc007a76c3af8f2311c98f1838e13e74976bb7d28240a9704830aa60b', rule: 'literal-native-options-with-bound-source-membership'}),
  'src/platform_native/remote_standard_host/moon.pkg': Object.freeze({digest: '01ae0816929d7ae3037f46906d63f999bca640fa20d12433e478c41475229886', rule: 'literal-target-selectors-with-bound-source-membership', revision: '523ada3259bf9e8147f746727fbfd56065036fd5'}),
  'src/platform_native/result_access/moon.pkg': Object.freeze({digest: '3857eed803af513e307d4f6a8f3450edbed4f94e830e38af3b3a88ab5d448697', rule: 'literal-native-options-with-bound-source-membership'}),
  'src/platform_native/runtime_bundle/moon.pkg': Object.freeze({digest: '1d8c003fea820e24835d1b6539d0e42e5908103e8d776a7c91b525b64dee02e4', rule: 'literal-native-options-with-bound-source-membership', revision: '66e7845f75c4eef5ebbb8d59d5fb4b652f73aa0c'}),
  'src/platform_native/signature/moon.pkg': Object.freeze({digest: '0d1a2b5edbd15f8f19232819cdf6e7947ce3d5c53491b25397e61c51ba25f872', rule: 'literal-native-options-with-bound-source-membership', revision: 'f86f409e62d39511380497cb0fe5639d5259f191'}),
  'src/platform_native/sqlite/moon.pkg': Object.freeze({digest: 'c28caf8bc62627196f85a4c1fd729a19a02f08c7ed2bd66f7c0316ede17b4e5f', rule: 'literal-native-options-with-bound-source-membership', revision: 'bddee734fca915cfca815562d1407ceb73d0e087'}),
  'src/platform_native/trusted_clock/moon.pkg': Object.freeze({digest: '19f2c6b1beb2a401a9152b82e679f0df352d11da6efeb1bc79f56ab516537ab0', rule: 'literal-native-options-with-bound-source-membership'}),
  'src/query_integration/moon.pkg': Object.freeze({digest: '85c6a9e865217e88e0322ca57208d43cc60742d508da3f04d5be00c724f8c15b', rule: 'literal-native-options-with-bound-source-membership', revision: 'd0a65454c66690c3725c9cfbcc31ee84fdd4c3f1'}),
  'src/connectors/kintone/host/moon.pkg': Object.freeze({digest: '85ba3f07ed79308b595b1c00cf085a87f2d7ec9f9f40c88be4ffc1c264d216bd', rule: 'literal-target-selectors-with-bound-source-membership', revision: '66e7845f75c4eef5ebbb8d59d5fb4b652f73aa0c'}),
  'src/source_value/moon.pkg': Object.freeze({digest: '7924497475b1578e83add3ebe773c473b6eba23182ed7c8e9b54ec38ecfba44b', rule: 'literal-target-selectors-with-bound-source-membership', revision: '3ce2057976a7c88a13246a6349fbd7a584d11478'}),
});

export const currentNestedFixtureConfigurations = Object.freeze({
  'src/connectors_builtin_node/fixtures/readme-deferred-keyed-input.json': '587ea35d738b1b7ecfaad2fd19d0c81260732b698c8e972477aa095dc6068be9',
  'src/platform_native/filesystem/fixtures/command_acl.c': '5c0e689346f89b1b62c5b5ffdb9d18a87d5181ec9082628b80ca1dcdc56bee69',
  'src/platform_native/filesystem/fixtures/command_directory_census.c': 'f6dc46e8338fdb9de7b2f2f34ef6e913230719ac8edf56063605b1d51da92726',
  'src/platform_native/filesystem/fixtures/observed_command_member.c': '147684d8a6ba26619a72de9ecc820a23ca2baca11d1fd5643e1d1511c1ccfbfb',
});

export function currentPackageConfigurationReviewFor({path, digest, target, toolchainDigest}) {
  if (target !== 'js' || toolchainDigest !== packageConfigurationReview.toolchainDigest) return null;
  const entry = currentPackageConfigurations[path];
  if (!entry || entry.digest !== digest) return null;
  return Object.freeze({revision: entry.revision ?? currentConfigurationReviewRevision, target,
    toolchainDigest, moonRevision: packageConfigurationReview.moonRevision, rule: entry.rule});
}

export function reviewedNestedFixture({path, digest, target, toolchainDigest}) {
  return target === 'js' && toolchainDigest === packageConfigurationReview.toolchainDigest &&
    Object.hasOwn(currentNestedFixtureConfigurations, path) && currentNestedFixtureConfigurations[path] === digest;
}

export function packageConfigurationReviewFor({path, digest, target, toolchainDigest}) {
  const current = currentPackageConfigurationReviewFor({path, digest, target, toolchainDigest});
  if (current) return current;
  if (target !== packageConfigurationReview.target ||
      toolchainDigest !== packageConfigurationReview.toolchainDigest) return null;
  if (Object.hasOwn(reviewedPackageConfigurations, path) && reviewedPackageConfigurations[path] === digest)
    return packageConfigurationReview;
  if (Object.hasOwn(foreignLibraryConfigurations, path) && foreignLibraryConfigurations[path] === digest)
    return foreignLibraryConfigurationReview;
  return null;
}

export function reviewedPackageConfiguration(request) {
  return packageConfigurationReviewFor(request) !== null;
}
