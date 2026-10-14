import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {PRODUCT_MEMBERS_FILE, productMembersBody, readProductMembers,
  productMembersCensus, selectedPlatformPlacement, installedProductCensus} from '../packages/native-cli/lib/product-members.mjs';

const expected = {sourceSha: 'a'.repeat(40), platform: 'darwin-arm64', packageName: 'actql'};
const record = {...expected, files: [
  {path: 'LICENSE', bytes: 3, mode: 420, sha256: 'b'.repeat(64)},
  {path: 'bin/actql.mjs', bytes: 7, mode: 493, sha256: 'c'.repeat(64)},
]};
const literal = '{"files":[{"bytes":3,"mode":420,"path":"LICENSE","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},{"bytes":7,"mode":493,"path":"bin/actql.mjs","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}],"packageName":"actql","platform":"darwin-arm64","sourceSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}';

test('private member bytes match independent literal and digest', () => {
  assert.equal(productMembersBody(record), literal);
  assert.equal(createHash('sha256').update(literal).digest('hex'),
    '4c31eaee350e3bc01a9804d0ef14a524df2dc6a629e48918da7c08e7b9538abc');
  assert.deepEqual(readProductMembers(literal, expected), record);
});

test('reader preserves exact source, platform, package and canonical input', () => {
  assert.throws(() => readProductMembers(literal, {...expected, sourceSha: 'b'.repeat(40)}));
  assert.throws(() => readProductMembers(literal, {...expected, platform: 'linux-x64-gnu'}));
  assert.throws(() => readProductMembers(literal, {...expected, packageName: '@actql/cli-darwin-arm64'}));
  for (const wire of [` ${literal}`, `${literal}\n`, literal.replace('"mode":420', '"mode":420,"mode":420'),
    literal.replace('"bytes":3', '"bytes":3.0'), literal.replace('LICENSE', '\\u004cICENSE')]) {
    assert.throws(() => readProductMembers(wire, expected));
  }
  assert.throws(() => readProductMembers(literal, {...expected, allow: true}));
});

test('self exclusion is one exact root path but physical census still requires it', () => {
  assert.equal(PRODUCT_MEMBERS_FILE, 'local-product-members.json');
  assert.deepEqual(productMembersCensus(record), [
    {path: '', entries: [{name: 'LICENSE', kind: 'file'}, {name: 'bin', kind: 'directory'},
      {name: 'local-product-members.json', kind: 'file'}]},
    {path: 'bin', entries: [{name: 'actql.mjs', kind: 'file'}]},
  ]);
  const extra = {...record, files: [...record.files,
    {path: PRODUCT_MEMBERS_FILE, bytes: 1, mode: 420, sha256: 'd'.repeat(64)}]};
  assert.throws(() => productMembersBody(extra), /must not hash itself/u);
  extra.files[2].path = `${PRODUCT_MEMBERS_FILE}.bak`;
  assert(productMembersCensus(extra)[0].entries.some(v => v.name === `${PRODUCT_MEMBERS_FILE}.bak`));
  extra.files[2].path = `lib/${PRODUCT_MEMBERS_FILE}`;
  assert(productMembersCensus(extra).find(v => v.path === 'lib').entries.some(v => v.name === PRODUCT_MEMBERS_FILE));
});

test('closed inventory rejects unknown, duplicate, unsorted or malformed fields', () => {
  assert.throws(() => productMembersBody({...record, grant: true}));
  assert.throws(() => productMembersBody({...record, packageName: '@actql/cli-linux-x64-gnu'}));
  assert.throws(() => productMembersBody({...record, sourceSha: 'A'.repeat(40)}));
  assert.throws(() => productMembersBody({...record, files: [...record.files].reverse()}));
  assert.throws(() => productMembersBody({...record, files: [record.files[0], record.files[0]]}));
  assert.throws(() => productMembersBody({...record, files: [{...record.files[0], unknown: 0}]}));
  for (const sha256 of ['B'.repeat(64), 'c'.repeat(63), `sha256:${'c'.repeat(64)}`]) {
    assert.throws(() => productMembersBody({...record, files: [{...record.files[0], sha256}]}));
  }
});

test('same-root finite paths cannot escape, recurse or conflict with file kinds', () => {
  for (const path of ['../LICENSE', '/LICENSE', 'a//b', 'a/./b', 'a/../b', 'a/b/c',
    'a\\b', 'x\0', 'a'.repeat(129)]) {
    assert.throws(() => productMembersBody({...record, files: [{...record.files[0], path}]}));
  }
  assert.throws(() => productMembersCensus({...record, files: [
    {...record.files[0], path: 'bin'}, record.files[1],
  ]}), /file cannot also be a directory/u);
  // Arbitrary directory names and empty directories are not census exceptions.
  assert.equal(productMembersCensus(record).some(v => v.path === 'extra'), false);
  assert.equal(productMembersCensus(record)[0].entries.some(v => v.name === 'node_modules'), false);
});

test('intake/numeric limits never coerce invalid values or declare workspace Allow', () => {
  for (const bytes of [-1, 67108865, '3', NaN, Infinity]) {
    assert.throws(() => productMembersBody({...record, files: [{...record.files[0], bytes}]}));
  }
  for (const mode of [-1, 512, '420', 420.5]) {
    assert.throws(() => productMembersBody({...record, files: [{...record.files[0], mode}]}));
  }
  assert.throws(() => readProductMembers(' '.repeat(65537), expected));
  assert.throws(() => productMembersBody({...record, files: Array(1638).fill(record.files[0])}));
  const files = Array.from({length: 500}, (_, n) => ({...record.files[0],
    path: `data/${'x'.repeat(124)}${String(n).padStart(4, '0')}`}));
  assert.throws(() => productMembersBody({...record, files}));
});

test('mode and digest changes are preserved rather than normalised in metadata', () => {
  for (const changed of [{...record.files[0], mode: 493}, {...record.files[0], sha256: 'd'.repeat(64)}]) {
    const wire = productMembersBody({...record, files: [changed, record.files[1]]});
    assert.notEqual(wire, literal);
    assert.deepEqual(readProductMembers(wire, expected).files[0], changed);
  }
});

test('hoisted and nested selected optional platform placements remain distinct', () => {
  assert.deepEqual(selectedPlatformPlacement('/consumer/node_modules/actql',
    '/consumer/node_modules/@actql/cli-darwin-arm64', 'darwin-arm64'), {layout: 'hoisted', route: []});
  assert.deepEqual(selectedPlatformPlacement('/consumer/node_modules/actql',
    '/consumer/node_modules/actql/node_modules/@actql/cli-darwin-arm64', 'darwin-arm64'),
  {layout: 'nested', route: ['node_modules', '@actql', 'cli-darwin-arm64']});
});

test('placement does not permit foreign packages, arbitrary node_modules or path normalisation', () => {
  for (const target of ['/other/node_modules/@actql/cli-darwin-arm64',
    '/consumer/node_modules/@actql/cli-linux-x64-gnu', '/consumer/node_modules/actql/node_modules/foreign',
    '/consumer/node_modules/actql/node_modules/@actql/../@actql/cli-darwin-arm64',
    '/consumer/node_modules//actql/node_modules/@actql/cli-darwin-arm64']) {
    assert.throws(() => selectedPlatformPlacement('/consumer/node_modules/actql', target, 'darwin-arm64'));
  }
  assert.throws(() => selectedPlatformPlacement('/consumer/node_modules/other',
    '/consumer/node_modules/@actql/cli-darwin-arm64', 'darwin-arm64'));
});

const platformRecord = {...record, packageName: '@actql/cli-darwin-arm64', files: [
  record.files[0], {...record.files[1], path: 'bin/actql'},
]};
const launcherRoot = '/consumer/node_modules/actql';
const platformRoot = '/consumer/node_modules/@actql/cli-darwin-arm64';

test('installed hoisted pair keeps independent payload Roots without dependency census exemption', () => {
  assert.deepEqual(installedProductCensus(record, platformRecord, launcherRoot, platformRoot), {
    layout: 'hoisted',
    launcher: {root: launcherRoot, directories: [
      {path: '', entries: [{name: 'LICENSE', kind: 'file'}, {name: 'bin', kind: 'directory'},
        {name: 'local-product-members.json', kind: 'file'}]},
      {path: 'bin', entries: [{name: 'actql.mjs', kind: 'file'}]},
    ]},
    platform: {root: platformRoot, directories: [
      {path: '', entries: [{name: 'LICENSE', kind: 'file'}, {name: 'bin', kind: 'directory'},
        {name: 'local-product-members.json', kind: 'file'}]},
      {path: 'bin', entries: [{name: 'actql', kind: 'file'}]},
    ]},
  });
});

test('installed nested pair closes each route directory around only the selected platform', () => {
  const nested = `${launcherRoot}/node_modules/@actql/cli-darwin-arm64`;
  const view = installedProductCensus(record, platformRecord, launcherRoot, nested);
  assert.equal(view.layout, 'nested');
  assert.equal(view.platform.root, nested);
  assert.deepEqual(view.launcher.directories, [
    {path: '', entries: [{name: 'LICENSE', kind: 'file'}, {name: 'bin', kind: 'directory'},
      {name: 'local-product-members.json', kind: 'file'}, {name: 'node_modules', kind: 'directory'}]},
    {path: 'bin', entries: [{name: 'actql.mjs', kind: 'file'}]},
    {path: 'node_modules', entries: [{name: '@actql', kind: 'directory'}]},
    {path: 'node_modules/@actql', entries: [{name: 'cli-darwin-arm64', kind: 'directory'}]},
  ]);
  assert.equal(view.platform.directories.some(value => value.path.startsWith('node_modules')), false);
});

test('installed pair rejects foreign source platform role route and conflicting payload membership', () => {
  for (const platform of [{...platformRecord, sourceSha: 'b'.repeat(40)},
    {...platformRecord, platform: 'linux-x64-gnu', packageName: '@actql/cli-linux-x64-gnu'},
    {...platformRecord, packageName: 'actql'}]) {
    assert.throws(() => installedProductCensus(record, platform, launcherRoot, platformRoot));
  }
  assert.throws(() => installedProductCensus(platformRecord, record, launcherRoot, platformRoot));
  assert.throws(() => installedProductCensus(record, platformRecord, launcherRoot,
    `${launcherRoot}/node_modules/@other/cli-darwin-arm64`));
  const payload = {...record, files: [...record.files,
    {...record.files[0], path: 'node_modules/declared'}]};
  assert.throws(() => installedProductCensus(payload, platformRecord, launcherRoot,
    `${launcherRoot}/node_modules/@actql/cli-darwin-arm64`), /declared payload member/u);
});

test('installed census does not rewrite descriptor bytes or mutate caller inventories', () => {
  const launcherBefore = JSON.stringify(record), platformBefore = JSON.stringify(platformRecord);
  installedProductCensus(record, platformRecord, launcherRoot,
    `${launcherRoot}/node_modules/@actql/cli-darwin-arm64`);
  assert.equal(JSON.stringify(record), launcherBefore);
  assert.equal(JSON.stringify(platformRecord), platformBefore);
  assert.equal(productMembersBody(record), literal);
  assert.equal(createHash('sha256').update(literal).digest('hex'),
    '4c31eaee350e3bc01a9804d0ef14a524df2dc6a629e48918da7c08e7b9538abc');
});
