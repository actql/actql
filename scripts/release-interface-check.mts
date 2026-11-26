// Normal release verification and normal builder checks remain authoritative.
// This composes their actual installed members with existing Owner references;
// it does not turn reference consistency into runtime behavior evidence.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join, relative} from 'node:path';
import {checkoutState} from './packed-client-packages.mjs';
import {verifyPackageRelease, inventory, unpack} from './package-release.mjs';
import {npmInterfaceRoots} from './distribution-interface-roots.mjs';
import {interfaceOwnerDeclarations} from './interface-owner-discovery.mjs';
import {checkInterfaceOwners} from './check-interface-owners.mjs';
import {installedInterfaceInventory} from './installed-interface-inventory.mjs';
import {installedInterfaceCorrespondence, assertInstalledDependencyClosure, installedDeclarationEmits,
  installedOriginalInputs} from './installed-interface-correspondence.mjs';
import {typescriptInterfaceInputs} from './typescript-interface-inventory.mjs';
import {runtimePackageInputs} from './runtime-package-inputs.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {buildLocalNodeAdapters, localNodeAdapterSourceInputs} from './build-local-node-adapters.mjs';
import {buildLocalNodeAssets} from './build-local-node-assets.mjs';
import {sourceInterfaceClosure} from './source-interface-closure.mjs';
import {initialControlPackageOriginal} from './initial-control-package-images.mjs';
import {buildConnectorAuthoring} from './build-connector-authoring.mjs';
import {authoringBinPath, authoringToolkitPath} from './connector-authoring-toolkit.mjs';

import type {BinaryLike} from 'node:crypto';

type Correspondence = Parameters<typeof installedInterfaceCorrespondence>[0];
type Artifacts = ReturnType<typeof installedInterfaceInventory>['artifacts'];
type SourceArtifact = Awaited<ReturnType<typeof sourceInterfaceClosure>>['artifacts'][number];
// Unchecked descriptor DATA. The builder and original member checks below
// remain responsible for validating the physical artifact and its provenance.
type NativeRecord = {platform: string; arch: string; source: {path: string};
  binary: {path: string; sha256: string; bytes: number}};
type NativeDescriptor = NativeRecord & {version: unknown; targets?: {original: NativeRecord}[]};

const hash = (bytes: BinaryLike) => createHash('sha256').update(bytes).digest('hex');

export async function releaseInterfaceCheck({repository, directory}: {repository: string; directory: string}) {
  const before = checkoutState(repository);
  assert(before.clean, 'Release interface verification needs clean source HEAD');
  const manifest = await verifyPackageRelease(directory);
  assert.equal(manifest.sourceSha, before.revision, 'Release interface source differs from checkout');
  assert.equal(manifest.recipeSha256, hash(readFileSync(join(repository, 'scripts/package-release.mjs'))),
    'Release interface recipe differs from original source');
  const roots = npmInterfaceRoots(repository), plans = runtimePackageInputs(repository);
  const owners = interfaceOwnerDeclarations(repository);
  const manifestSha256 = hash(readFileSync(join(directory, 'release.json')));
  const members = manifest.packages.flatMap(item => {
    const root = roots.find(value => value.name === item.name);
    assert(root, `Missing normal package source entrance: ${item.name}`);
    return item.files.map(file => join(dirname(root.manifest), file.path));
  });
  let declaredEmits: ReturnType<typeof installedDeclarationEmits> | undefined;
  return {manifest, async verifyConsumer(consumer: string, names: readonly string[]) {
    assert.equal(new Set(names).size, names.length, 'Duplicate installed interface package');
    const reports = [];
    for (const name of names) {
      const item = manifest.packages.find(value => value.name === `@actql/${name}`);
      assert(item, `Package outside original release cohort: ${name}`);
      const root = roots.find(value => value.name === item.name);
      assert(root, `Missing normal package source entrance: ${item.name}`);
      const installed = join(consumer, 'node_modules', item.name);
      assert.deepEqual(await inventory(installed), item.files, `Changed installed release members: ${item.name}`);
      const packageSource = dirname(root.manifest);
      const bindings = new Map<string, Correspondence['bindings'][number]>(item.files.map(file => [file.path,
        {member: file.path, source: `${packageSource}/${file.path}`} ]));
      const plan = plans[name as keyof typeof plans];
      const localArtifacts: Artifacts = [];
      if (name === 'local-node') {
        const inputs = localNodePackageInputs(repository);
        // Generation belongs to the original development context. Its image
        // recipe has both development and selected release manifest facts;
        // rerendering from an installed release manifest would mix versions
        // with the unchanged development dependency graph in this checkout.
        // verifyPackageRelease already proves the metadata/LICENSE-only bridge
        // to these exact installed members; neither payload is regenerated.
        const scratch = await mkdtemp(join(tmpdir(), 'actql-release-original-interface-'));
        try {
          const archive = join(directory, 'development', item.originalFile);
          assert.equal(hash(await readFile(archive)), item.originalSha256, 'Changed original development archive');
          const original = await unpack(archive, scratch), originalInventory = await inventory(original);
          await buildLocalNodeAdapters({root: repository, destination: original, inputs, check: true});
          buildLocalNodeAssets({root: repository, destination: original, inputs, check: true});
          const toolkitPrefix = authoringToolkitPath + '/';
          const toolkitMembers = originalInventory.filter(file => file.path.startsWith(toolkitPrefix));
          const originalMetadata = JSON.parse(await readFile(join(original, 'package.json')) as unknown as string);
          if (toolkitMembers.length || originalMetadata.bin?.['actql-connector'] === authoringBinPath) {
            // The toolkit is an exact authored-copy artifact. Its builder
            // selects the command and normal consumer entries, and excludes
            // producer-only imports from the distributed toolkit.
            const expectedRoot = join(scratch, 'expected-authoring');
            const {inputs: sourceFiles} = buildConnectorAuthoring(repository, expectedRoot);
            const expected = await inventory(join(expectedRoot, authoringToolkitPath), toolkitPrefix);
            assert.deepEqual(expected.map(file => file.path).sort(), sourceFiles.map(path => toolkitPrefix + path).sort());
            assert.deepEqual(toolkitMembers, expected, 'Original connector authoring toolkit differs from the ordinary copy recipe');
            const originalInput = installedOriginalInputs(repository, before.revision, sourceFiles);
            for (const member of toolkitMembers) {
              const path = member.path.slice(toolkitPrefix.length);
              const {author, bytes} = originalInput(path);
              assert.equal(member.sha256, hash(bytes), `Changed original connector authoring input: ${path}`);
              localArtifacts.push({
                module: member.path, sha256: member.sha256, sourceSha: before.revision,
                target: 'node-connector-authoring-copy',
                verification: {manifestSha256, originalSha256: item.originalSha256,
                  build: 'scripts/build-connector-authoring.mjs', sourceFiles: [author],
                  ...(author === path ? {} : {compiler: {configuration: 'tsconfig.tooling.json', emitted: path}}),
                  qualification: 'ordinary authored-copy identity for the selected toolkit'},
              });
            }
          }
          // The normal builder has checked these bytes and their original
          // descriptor. Reuse the existing finite native input references;
          // a filename or the public manifest alone cannot register a binary.
          const nativeMembers = item.files.filter(file => file.path.endsWith('.node'));
          if (nativeMembers.length) {
            const reference = await sourceInterfaceClosure(repository, {distributionRoots: [root]});
            const descriptorModule = '_build/native/directory-original.json';
            const descriptorFile = item.files.find(file => file.path === descriptorModule);
            assert(descriptorFile, 'Missing original native descriptor');
            const descriptor = JSON.parse(await readFile(join(original, descriptorModule)) as unknown as string) as NativeDescriptor;
            const records = descriptor.version === 'actql-node-directory-native-cohort/0.1'
              ? descriptor.targets!.map(target => target.original) : [descriptor];
            for (const file of nativeMembers) {
              const input: SourceArtifact | undefined = reference.artifacts.find(value => value.module === `${packageSource}/${file.path}` &&
                value.package === name && value.target?.endsWith('/node-napi8'));
              const record = records.find(value => value.binary.path === file.path);
              assert(input && record, `Unregistered normal native artifact: ${file.path}`);
              assert.equal(file.sha256, record.binary.sha256, 'Changed original native binary');
              assert.equal(file.bytes, record.binary.bytes, 'Changed original native binary extent');
              assert.equal(input.target, `${record.platform}-${record.arch}/node-napi8`, 'Foreign original native target');
              assert(input.sourceFiles!.includes(record.source.path), 'Foreign original native source');
              localArtifacts.push({module: file.path, sha256: file.sha256, sourceSha: before.revision,
                target: input.target, verification: {build: input.build, sourceFiles: input.sourceFiles,
                  manifestSha256, originalSha256: item.originalSha256,
                  descriptor: {module: descriptorModule, sha256: descriptorFile.sha256},
                  qualification: 'checked normal native original; not operational custody or cross-platform runtime acceptance'}});
            }
          }
          const image = item.files.find(file => file.path === initialControlPackageOriginal);
          if (image) {
            // The normal renderer replaces this Source-only absence template
            // with a fixed generated DATA image. Its actual check above, not
            // a filename exemption, binds the delivered image to this source.
            assert.equal(hash(await readFile(join(original, image.path))), image.sha256,
              'Changed original generated package image');
            const generator = 'scripts/initial-control-package-images.mjs';
            localArtifacts.push({module: image.path, sha256: image.sha256, sourceSha: before.revision,
              target: 'node-package-image-data', verification: {build: 'scripts/build-local-node-adapters.mjs',
                generator: {module: generator, sha256: hash(readFileSync(join(repository, generator)))},
                template: {module: image.path, sha256: hash(readFileSync(join(repository, image.path)))},
                manifestSha256, originalSha256: item.originalSha256,
                qualification: 'checked normal generated package DATA; not an operational issuer'}});
          }
          assert.deepEqual(await inventory(original), originalInventory, 'Normal generation check changed original members');
          assert.equal(hash(await readFile(archive)), item.originalSha256, 'Original archive changed during verification');
        } finally {await rm(scratch, {recursive: true});}
        for (const entry of await localNodeAdapterSourceInputs({root: repository, inputs})) {
          bindings.set(entry.path, {member: entry.path, source: relative(repository, entry.source),
            ...(entry.path.endsWith('.mjs') ? {transform: 'local-node-public-imports'} : {})});
        }
        for (const path of inputs.dataFiles) bindings.set(path, {member: path, source: path});
      }
      const artifacts = (plan?.files ?? []).map<Artifacts[number]>(path => {
        assert(path.startsWith(packageSource + '/'), 'Runtime input outside its original package');
        const module = path.slice(packageSource.length + 1);
        const file = item.files.find(value => value.path === module);
        assert(file, `Missing ordinary runtime interface: ${path}`);
        return {module, sha256: file.sha256, sourceSha: before.revision, target: 'js',
          verification: {manifestSha256, originalSha256: item.originalSha256,
            build: `scripts/${plan.script}.mjs`, sourcePackages: plan.sources}};
      }).concat(localArtifacts);
      const emittedDeclarations = declaredEmits ??= installedDeclarationEmits(repository, before.revision, members);
      const declarations = item.files.flatMap(file => {
        const emit = emittedDeclarations.get(join(packageSource, file.path));
        if (!emit) return [];
        assert.equal(file.sha256, emit.sha256, `Changed original emitted declaration: ${file.path}`);
        return [{module: file.path, sha256: emit.sha256, sourceSha: before.revision,
          target: 'node-typescript-declaration',
          verification: {manifestSha256, originalSha256: item.originalSha256,
            author: emit.author, build: 'tsconfig.tooling.json',
            qualification: 'exact semantic declaration emit from the original TypeScript author'}}];
      });
      const firstInventory = installedInterfaceInventory(installed, {artifacts: [...artifacts, ...declarations]});
      const authoredEntrances = firstInventory.modules.map(module => {
        const binding = bindings.get(module.module);
        assert(binding, `Unbound installed authored interface: ${module.module}`);
        return binding.source;
      });
      const checkedSource = await checkInterfaceOwners(repository, {manifests: [root.manifest], authoredEntrances});
      // Resolve each ordinary configured output from the same checked source
      // and the already verified normal tarball. The generated member cannot
      // pass as authored JavaScript or inherit a dependency's output proof.
      const packagedOutputs = new Map(item.files.map(file => [file.path, file.sha256]));
      const configured = checkedSource.configuredOutputs.filter(output =>
        dirname(output.build) === packageSource);
      for (const output of configured) {
        assert(output.module.startsWith(packageSource + '/'), 'Configured output escaped its package');
        const module = output.module.slice(packageSource.length + 1);
        assert.equal(packagedOutputs.get(module), output.sha256, `Mixed normal Vite output: ${output.module}`);
        artifacts.push({module, sha256: output.sha256, sourceSha: before.revision, target: 'js',
          verification: {manifestSha256, originalSha256: item.originalSha256, build: output.build}});
      }
      const installedArtifacts = [...artifacts, ...declarations];
      const actual = configured.length === 0 ? firstInventory
        : installedInterfaceInventory(installed, {artifacts: installedArtifacts});
      if (declarations.length) {
        const runtimeMembers = new Set(actual.modules.map(file => file.module));
        const typeModules = typescriptInterfaceInputs(installed, declarations.map(file => file.module)).modules;
        assert(!typeModules.some(module => module.unresolvedSyntax?.length), 'Unresolved installed TypeScript interface');
        for (const file of declarations) {
          assert(runtimeMembers.has(file.module.replace(/\.d\.mts$/u, '.mjs')),
            `Missing checked runtime for installed declaration: ${file.module}`);
          const syntax = typeModules.find(module => module.module === file.module);
          assert(syntax, `Unresolved installed declaration syntax: ${file.module}`);
          assert.equal(syntax.sha256, file.sha256, `Changed installed declaration interface: ${file.module}`);
        }
      }
      const bySource = new Map([...bindings.values()].map(value => [value.source, value.member]));
      const runtimeBindings = checkedSource.runtimeBindings.filter(value => bySource.has(value.module))
        .map(value => ({...value, module: bySource.get(value.module)!}));
      const dependencies = await assertInstalledDependencyClosure({directory: installed,
        modules: actual.modules, artifacts: installedArtifacts, runtimeBindings});
      reports.push({...installedInterfaceCorrespondence({repository, directory: installed,
        source: before.revision, bindings: [...bindings.values()], artifacts: installedArtifacts,
        owners, generated: checkedSource.generatedQualification, checkedSource}), dependencies});
    }
    assert.deepEqual(checkoutState(repository), before, 'Release interface source changed during verification');
    return {qualification: 'normal release/source/installed interface correspondence; not runtime or all-I6 acceptance',
      source: before.revision, manifestSha256, reports};
  }};
}
