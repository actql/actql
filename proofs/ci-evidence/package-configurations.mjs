// A reviewed finite input policy, not a general package-language parser.
// At this revision these literal options contain only native stubs, native
// linker settings and native/not-native file predicates. For the pinned Moon
// JS execution path they select bound source files but cannot run a native
// linker/stub compiler. All package/source bytes and memberships remain inputs.
// Changes to this table, the toolchain or any configuration force fresh work.
// Unknown options and other targets require separate review; matching a digest
// is configuration identity, not a proof of compiler or OS correctness.
export const packageConfigurationReview = Object.freeze({
  revision: 'b98a50ff763d1367e344fdfa8aea380ec8749132',
  target: 'js',
  toolchainDigest: '8a3a1396f02ba4d5d780382960d1bcf95ccc8d6b97c3da446c0899b98874819a',
  moonRevision: '94521db',
  rule: 'literal-native-options-with-bound-source-membership',
});

export const reviewedPackageConfigurations = Object.freeze({
  'src/connectors/duckdb/adapters/native/moon.pkg': '7283cc7667b9293a7132672ce9edf375901ffb35eb02e25af9eb9eba55a1e89d',
  'src/platform_native/filesystem/moon.pkg': 'cf42efdf2f6fb6285a1a099fca4c71e9f149a9fa940d05d5f42a3b0b47a60651',
  'src/platform_native/http_client/moon.pkg': 'f2def56166ae8d5566441f011296f2f8ec9a93167d18f405f1894e4871267a08',
  'src/platform_native/https_server/moon.pkg': '880ad74137ab58e0f92f43465f9bc2bcd096eb2b29461b9f93d68883ed5d22bd',
  'src/platform_native/publication_store/moon.pkg': '35d6c3f1c56d57b9f11dcc2798f82a1cebe98d1022c2ec35885c79e7b4e10bf7',
  'src/platform_native/remote_client/moon.pkg': '67756b13c514822718fe21600a9e807392d7c2c4ee5b99cc6e2ab09616761a59',
  'src/platform_native/remote_journal/moon.pkg': 'd0c6ba5ca3760d425f90ceafcc6c06d22737c4c2978995ccd31ac3c2b228d90e',
  'src/platform_native/remote_standard_host/moon.pkg': '14c80ec28c7c4f706f8aa55c2a73fa0c2f3023c4f91d4cb016094d0170b04f87',
  'src/platform_native/remote_transfer_client/moon.pkg': '95f25cf39e6857265915ea63db4f4de47b8e209b6bb32bb6566bd9297f87a8f0',
  'src/platform_native/remote_transfer_journal/moon.pkg': '5baf57142f807ae0121c9bdd1c40173a81d9e8248b3b5dbcee3cd969f4e23601',
  'src/platform_native/retained_task_file/moon.pkg': 'e3050859982bfa2a176e04f44c08dcf073be7405e42be6f0af81f51a680347de',
  'src/platform_native/runtime_bundle/moon.pkg': 'a853c9fd5ca1ae9c3ca8744b48efaf1ffbc41c13d7c2b5fa67989d3b9950e9cc',
  'src/platform_native/signature/moon.pkg': '5d60d6863d370f759ec4c1b80f43999ab11c93158c7d61577eacb324b6807c7f',
  'src/platform_native/sqlite/moon.pkg': '05340cbc4e922feb361cd58cc8da0cec23671f76eacaaf28aafdfba682ec049d',
  'src/query_integration/moon.pkg': '3990008f0b98a6cedd8465fe11c23d84e0c35a286339ba8a1bd7c2639f5ea955',
});

export function reviewedPackageConfiguration({path, digest, target, toolchainDigest}) {
  return target === packageConfigurationReview.target &&
    toolchainDigest === packageConfigurationReview.toolchainDigest &&
    Object.hasOwn(reviewedPackageConfigurations, path) && reviewedPackageConfigurations[path] === digest;
}
