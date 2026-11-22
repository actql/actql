"""Build one explicit file-backed libcurl input for the Native HTTP owner.

This runs under the ordinary local guard. It never installs a library, imports
a runtime, creates a Host, or acknowledges transport/global resource cleanup.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[1]
RECIPE = ROOT / 'scripts/native-http-component-source.json'
MODEL_RESOLVER_RECIPE = ROOT / 'scripts/native-model-http-resolver-source.json'
spec = importlib.util.spec_from_file_location(
    'native_original_inputs', ROOT / 'scripts/produce-native-remote-scoped-runtime.py')
if spec is None or spec.loader is None:
    raise ValueError('Existing native input observer is unavailable')
NATIVE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(NATIVE)
tls_spec = importlib.util.spec_from_file_location('native_http_tls_recipe',
    ROOT / 'scripts/produce-native-http-tls.py')
TLS = importlib.util.module_from_spec(tls_spec)
tls_spec.loader.exec_module(TLS)

CURL_EXPORTS = frozenset(('curl_global_init', 'curl_global_init_mem', 'curl_global_cleanup',
    'curl_version', 'curl_version_info', 'curl_easy_init', 'curl_easy_setopt',
    'curl_easy_perform', 'curl_easy_getinfo', 'curl_easy_cleanup',
    'curl_easy_strerror', 'curl_slist_append', 'curl_slist_free_all'))
MODEL_MULTI_EXPORTS = frozenset('curl_multi_' + name for name in (
    'init', 'add_handle', 'perform', 'poll', 'info_read', 'remove_handle', 'cleanup'))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def original(path: Path) -> dict:
    before = path.stat(follow_symlinks=False)
    value = NATIVE.original(path)
    after = path.stat(follow_symlinks=False)
    require((before.st_dev, before.st_ino, before.st_mode, before.st_size,
             before.st_mtime_ns, before.st_ctime_ns) ==
            (after.st_dev, after.st_ino, after.st_mode, after.st_size,
             after.st_mtime_ns, after.st_ctime_ns), 'Input changed while read')
    return {**value, 'dev': str(after.st_dev), 'ino': str(after.st_ino), 'mode': str(after.st_mode)}


def bind_model_resolver_allocator(source: Path, patch: dict) -> None:
    # curl_global_init_mem selects these exact allocator functions before
    # Curl_async_global_init. c-ares must never bypass them on scoped Reads.
    path = source / patch['path']
    before = path.read_bytes()
    require(hashlib.sha256(before).hexdigest() == patch['beforeSha256'],
            'Original curl resolver source differs')
    old = b'  if(ares_library_init(ARES_LIB_INIT_ALL)) {'
    new = (b'  if(ares_library_init_mem(ARES_LIB_INIT_ALL, Curl_cmalloc, Curl_cfree,\n'
           b'                           Curl_crealloc)) {')
    require(before.count(old) == 1, 'Original c-ares allocator boundary differs')
    after = before.replace(old, new)
    require(hashlib.sha256(after).hexdigest() == patch['afterSha256'],
            'Bound curl resolver source differs')
    path.write_bytes(after)


def require_private_model_resolver(exports: str, imports: str) -> None:
    # Dynamic symbols would let an ambient shared c-ares image override the
    # static resolver or its allocator globals. Disallow both directions.
    symbol = re.compile(r'(?:^|\s)_*ares(?:x)?_[a-zA-Z0-9_]+(?=@|\s|$)', re.M)
    require(symbol.search(exports) is None and symbol.search(imports) is None,
            'Model resolver symbols must remain private to the selected HTTP image')


def inspect_linux_component(library: Path, dynamic: str, exports: str) -> list[str]:
    with library.open('rb') as stream:
        header = stream.read(64)
    require(len(header) == 64 and header[:7] == b'\x7fELF\x02\x01\x01' and
            int.from_bytes(header[16:18], 'little') == 3 and
            int.from_bytes(header[18:20], 'little') == 62,
            'HTTP component requires ELF64 little-endian x86-64 shared image')
    require('(RPATH)' not in dynamic and '(RUNPATH)' not in dynamic,
            'HTTP component has an ambient loader search path')
    require(re.findall(r'\(SONAME\).*?\[([^\]]+)\]', dynamic) == [library.name],
            'HTTP component SONAME differs')
    dependencies = re.findall(r'\(NEEDED\).*?\[([^\]]+)\]', dynamic)
    allowed = {'libc.so.6', 'libm.so.6', 'libdl.so.2', 'libpthread.so.0',
               'librt.so.1', 'libz.so.1', 'libgcc_s.so.1', 'ld-linux-x86-64.so.2'}
    require(len(dependencies) == len(set(dependencies)) and 'libc.so.6' in dependencies
            and set(dependencies) <= allowed, 'Unselected HTTP shared dependency')
    names = {line.split()[-1].split('@', 1)[0] for line in exports.splitlines() if line.strip()}
    require(CURL_EXPORTS | {'curl_actql_native_tls_api_v3'} <= names,
            'HTTP original Read/TLS cleanup or loader export is missing')
    return dependencies


def build(source: str, archive: Path, signature: Path, keyring: Path,
          openssl: Path, clang: Path, sdk: Path | None, make: Path, gpgv: Path,
          destination: Path, seconds: int, owned_openssl_receipt: Path | None = None,
          target: str = 'darwin-arm64', minimum_macos: str | None = None, *,
          model_resolver_archive: Path | None = None) -> dict:
    actual = ('darwin-arm64' if sys.platform == 'darwin' and platform.machine() == 'arm64'
              else 'linux-x64' if sys.platform == 'linux' and platform.machine() == 'x86_64' else None)
    require(actual == target, 'Selected HTTP component target differs')
    profile = TLS.command_profile(target, clang, sdk, destination, minimum_macos)
    require(target != 'linux-x64' or owned_openssl_receipt is not None,
            'Linux HTTP requires the original owned TLS receipt')
    require(re.fullmatch(r'[a-f0-9]{40}', source) is not None and type(seconds) is int and seconds > 0,
            'Invalid selected source or build budget')

    def clean() -> None:
        require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT,
                text=True).strip() == source and not subprocess.check_output(
                ['git', 'status', '--porcelain'], cwd=ROOT),
                'Exact clean committed HTTP component source is required')

    clean()
    recipe = json.loads(RECIPE.read_bytes())
    for path, expected in [(archive, recipe['upstream']['archive']),
                           (signature, recipe['upstream']['signature'])]:
        item = original(path)
        require({key: item[key] for key in ('bytes', 'sha256')} == expected,
                'Selected signed source input differs')
    # Linux binutils entry points may be aliases. Pin and invoke the same
    # resolved original; ordinary source inputs still refuse aliases.
    nm = Path('/usr/bin/nm')
    if sdk is None:
        nm = nm.resolve(strict=True)
    selected = [archive, signature, keyring, RECIPE,
                Path(__file__).resolve(), ROOT / 'scripts/produce-native-remote-scoped-runtime.py',
                ROOT / 'scripts/produce-native-http-tls.py',
                clang, make, gpgv, Path(sys.executable).resolve(), nm]
    if model_resolver_archive is not None:
        require(owned_openssl_receipt is not None,
                'Model HTTP requires the original owned TLS receipt')
        resolver = json.loads(MODEL_RESOLVER_RECIPE.read_bytes())
        resolver_recipe = original(MODEL_RESOLVER_RECIPE)
        resolver_original = original(model_resolver_archive)
        require({key: resolver_original[key] for key in ('bytes', 'sha256')} ==
                resolver['archive'], 'Selected Model resolver source differs')
        selected.extend([MODEL_RESOLVER_RECIPE, model_resolver_archive])
    if sdk is not None:
        selected.extend([sdk / 'SDKSettings.json', Path('/usr/bin/otool'),
                         Path('/usr/bin/codesign'), Path('/usr/bin/install_name_tool')])
    else:
        readelf = Path('/usr/bin/readelf').resolve(strict=True)
        selected.append(readelf)
    if owned_openssl_receipt is not None:
        owned = json.loads(owned_openssl_receipt.read_bytes())
        TLS.validate_receipt_profile(owned, target, profile['minimumMacOS'])
        require(owned['upstream'] == recipe['ownedOpenSSLSource'] and
                Path(owned['stage']) == openssl, 'Owned TLS source/recipe differs')
        # Reuse the exact static input when its actual producer/source/tool
        # inputs remain unchanged. A later HTTP adapter child does not retag
        # the TLS build or justify compiling those same libraries again.
        for item in owned['inputs']:
            require(NATIVE.original(Path(item['path'])) == item,
                    'Owned TLS producer original changed')
        tls_files = {}
        for item in owned['files']:
            relative = Path(item['path']).relative_to(openssl).as_posix()
            tls_files[relative] = {key: item[key] for key in ('bytes', 'sha256')}
        selected.extend([owned_openssl_receipt,
                         ROOT / 'src/platform_native/http_client/component_tls_lifetime.c',
                         ROOT / 'src/platform_native/http_client/component_tls_lifetime.h'])
    else:
        require(profile['minimumMacOS'] == recipe['minimumMacOS'],
                'A different deployment profile requires its original owned TLS receipt')
        tls_files = recipe['openssl']['files']
    for relative, expected in tls_files.items():
        path = openssl / relative
        item = original(path)
        require({key: item[key] for key in ('bytes', 'sha256')} == expected,
                'Selected original OpenSSL input differs: ' + relative)
        selected.append(path)
    inputs = [original(path) for path in selected]
    require(not destination.exists() and not destination.is_symlink(), 'Output already exists')
    destination.mkdir(parents=True)
    (destination / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    deadline, steps = time.monotonic() + seconds, []
    environment = {**profile['environment'], 'PKG_CONFIG': '/usr/bin/false', 'OPENSSL_CONF': '/dev/null'}
    if sdk is not None:
        environment.update({'DEVELOPER_DIR': '/Library/Developer/CommandLineTools',
                            'MACOSX_DEPLOYMENT_TARGET': profile['minimumMacOS'],
                            'LDFLAGS': '-arch arm64 -isysroot ' + str(sdk) +
                                (' -mmacosx-version-min=11.0' if profile['minimumMacOS'] == '11.0' else '')})

    def run(name: str, command: list[str], cwd: Path = ROOT) -> str:
        remaining = deadline - time.monotonic()
        require(remaining > 0, 'HTTP component build budget exhausted')
        result = subprocess.run(command, cwd=cwd, env=environment,
                                capture_output=True, text=True, timeout=remaining)
        (destination / (name + '.stdout')).write_text(result.stdout)
        (destination / (name + '.stderr')).write_text(result.stderr)
        steps.append({'name': name, 'command': command, 'cwd': str(cwd), 'exit': result.returncode})
        (destination / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        require(result.returncode == 0, 'HTTP component command failed: ' + name)
        return result.stdout

    model_resolver = None
    model_configure = []
    if model_resolver_archive is not None:
        resolver_top = 'c-ares-' + resolver['version']
        resolver_build = destination / 'resolver-build'
        resolver_build.mkdir()
        with tarfile.open(model_resolver_archive, 'r:gz') as tar:
            members = tar.getmembers()
            require(sum(item.size for item in members) <= 16 * 1024 * 1024 and
                    all(item.name == resolver_top or item.name.startswith(resolver_top + '/')
                        for item in members), 'Unexpected Model resolver archive layout')
            tar.extractall(resolver_build, filter='data')
        resolver_source = resolver_build / resolver_top
        resolver_prefix = destination / 'resolver-input'
        run('configure-model-resolver', ['/bin/sh', str(resolver_source / 'configure'),
            '--prefix=' + str(resolver_prefix), '--disable-shared', '--enable-static',
            '--disable-tests', '--disable-cares-threads'], resolver_source)
        run('build-model-resolver', [str(make), '-j1'], resolver_source)
        run('stage-model-resolver', [str(make), 'install'], resolver_source)
        resolver_library = resolver_prefix / 'lib/libcares.a'
        require(resolver_library.is_file() and not resolver_library.is_symlink(),
                'Static Model resolver original is unavailable')
        model_resolver = {'source': resolver_original, 'version': resolver['version'],
                          'recipe_sha256': resolver_recipe['sha256'],
                          'backend': 'c-ares', 'addressLookup': 'c-ares',
                          'allocatorPatch': resolver['allocatorPatch'],
                          'staticLibrary': original(resolver_library)}
        model_configure = ['--enable-ares=' + str(resolver_prefix),
                           '--disable-threaded-resolver', '--disable-httpsrr']

    keyhome = destination / 'public-key-verifier'
    keyhome.mkdir(mode=0o700)
    verified = run('verify-signed-source', [str(gpgv), '--homedir', str(keyhome),
        '--keyring', str(keyring), '--status-fd', '1', str(signature), str(archive)])
    require(any(line.startswith('[GNUPG:] VALIDSIG ') and
                recipe['upstream']['signerFingerprint'] in line.split()
                for line in verified.splitlines()), 'Required upstream signature was not observed')
    # Only the two exact static archives are visible in this private prefix.
    # Header links are read-only; no tool installation or donor edit occurs.
    loans = []
    try:
        prefix = destination / 'openssl-input'
        (prefix / 'lib').mkdir(parents=True)
        (prefix / 'include').symlink_to(openssl / 'include', target_is_directory=True)
        loans.append((prefix / 'include', openssl / 'include'))
        for name in ('libssl.a', 'libcrypto.a'):
            (prefix / 'lib' / name).symlink_to(openssl / 'lib' / name)
            loans.append((prefix / 'lib' / name, openssl / 'lib' / name))
        stage = destination / 'source'
        stage.mkdir()
        with tarfile.open(archive, 'r:xz') as tar:
            members = tar.getmembers()
            top = 'curl-' + recipe['upstream']['version']
            require(sum(item.size for item in members) <= 128 * 1024 * 1024 and
                    all(item.name == top or item.name.startswith(top + '/') for item in members),
                    'Unexpected selected source archive layout')
            tar.extractall(stage, filter='data')
        source_root = stage / top
        if model_resolver is not None:
            bind_model_resolver_allocator(source_root, model_resolver['allocatorPatch'])
        build_root = destination / 'build'
        build_root.mkdir()
        configuration = run('configure', ['/bin/sh', str(source_root / 'configure'),
            '--prefix=/actql-native-http-component', '--with-openssl=' + str(prefix),
            *recipe['configure'], *model_configure], build_root)
        require('unrecognized options' not in configuration and 'unrecognized options' not in
                (destination / 'configure.stderr').read_text(), 'Unknown component configure option')
        if model_resolver is not None:
            config = (build_root / 'lib/curl_config.h').read_text()
            require(re.search(r'^#define USE_RESOLV_ARES 1$', config, re.M) is not None and
                    re.search(r'^#define HAVE_GETADDRINFO 1$', config, re.M) is not None and
                    re.search(r'^#define USE_(?:RESOLV_THREADED|HTTPSRR)\b', config, re.M) is None and
                    re.search(r'^\s*resolver:\s+c-ares\s*$', configuration, re.M) is not None,
                    'HTTP configure did not select c-ares address lookups exclusively')
        build_command = [str(make), '-C', 'lib', '-j1', 'V=1']
        if owned_openssl_receipt is not None:
            physical_adapter = destination / 'component-tls-lifetime.o'
            run('compile-tls-lifetime', [str(clang), '-std=c11', '-O2', '-fPIC',
                '-fvisibility=hidden', *profile['compilerFlags'],
                '-I', str(openssl / 'include'), '-I', str(ROOT / 'src/platform_native/http_client'),
                '-c', str(ROOT / 'src/platform_native/http_client/component_tls_lifetime.c'),
                '-o', str(physical_adapter)])
            build_command.append('libcurl_la_LIBADD=' + str(physical_adapter))
        # GNU libtool uses -release in both the file name and ELF SONAME.
        # Keep the original version-info expression and add the Model suffix
        # only on this resolver-aware Linux image.
        if model_resolver is not None and sdk is None:
            build_command.append(
                'VERSIONINFO=-version-info $(VERSIONCHANGE):$(VERSIONADD):$(VERSIONDEL) -release model')
        run('build-library', build_command, build_root)
        if sdk is not None:
            produced_name = 'libcurl.4.dylib'
            library_name = 'libcurl-model.4.dylib' if model_resolver is not None else produced_name
        else:
            library_name = 'libcurl-model.so.4' if model_resolver is not None else 'libcurl.so.4'
            produced_name = library_name
        produced = build_root / 'lib/.libs' / produced_name
        require(produced.is_file(), 'Expected shared HTTP library was not produced')
        bundle = destination / 'bundle'
        bundle.mkdir()
        library = bundle / library_name
        shutil.copy2(produced.resolve(), library)
        minimum_macos = None
        if sdk is None:
            dynamic = run('observed-dependencies', [str(readelf), '--dynamic', '--wide', str(library)])
            exports = run('observed-exports', [str(nm), '-D', '--defined-only', str(library)])
            observed_dependencies = inspect_linux_component(library, dynamic, exports)
            run('observed-imports', [str(nm), '-D', '--undefined-only', str(library)])
        else:
            observed_dependencies, minimum_macos = inspect_darwin_component(
                library, openssl, prefix, {**recipe, 'minimumMacOS': profile['minimumMacOS']},
                owned_openssl_receipt, run)
        shutil.copy2(source_root / 'COPYING', bundle / 'CURL-COPYING')
        shutil.copy2(openssl / 'LICENSE.txt', bundle / 'OPENSSL-LICENSE.txt')
        if model_resolver is not None:
            exports = (destination / 'observed-exports.stdout').read_text()
            imports = (destination / 'observed-imports.stdout').read_text()
            require_private_model_resolver(exports, imports)
            names = {line.split()[-1].split('@', 1)[0] for line in
                     exports.splitlines() if line.strip()}
            prefix_name = '_' if sdk is not None else ''
            require({prefix_name + name for name in MODEL_MULTI_EXPORTS} <= names,
                    'Original Model HTTP multi operations are missing')
            require(original(resolver_library) == model_resolver['staticLibrary'],
                    'Original Model resolver changed during HTTP production')
            notice = bundle / 'CARES-LICENSE.md'
            shutil.copy2(resolver_source / 'LICENSE.md', notice)
            model_resolver['notice'] = original(notice)
    finally:
        returned = []
        for path, target_path in reversed(loans):
            require(path.is_symlink() and path.readlink() == target_path, 'Original component input alias changed')
            path.unlink()
            returned.append({'path': str(path), 'target': str(target_path)})
        (destination / 'input-alias-closure.json').write_text(json.dumps({'returned': returned, 'remainingOwnAliases': 0}, indent=2) + '\n')
    (destination / 'configure-summary.txt').write_text(configuration)
    for item in inputs:
        require(original(Path(item['path'])) == item, 'Original input changed during component production')
    clean()
    receipt = {'source': source, 'target': target, 'upstream': recipe['upstream'],
               'recipe_sha256': hashlib.sha256(RECIPE.read_bytes()).hexdigest(), 'inputs': inputs,
               'library': original(library), 'loaded': 0, 'initialized': 0,
               'installed_supplier': False, 'normal_profile': None, 'public_e2e': 0,
               'minimumMacOS': minimum_macos, 'systemDependencies': observed_dependencies,
               'scope': 'File-backed dependency only. No Native Host/Read funding, transport/thread stop or runtime acceptance.'}
    receipt['ownedOpenSSLReceipt'] = original(owned_openssl_receipt) if owned_openssl_receipt else None
    if model_resolver is not None:
        receipt['modelResolver'] = model_resolver
    (destination / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def inspect_darwin_component(library, openssl, prefix, recipe, owned_openssl_receipt, run):
    install_name = '@rpath/' + library.name
    run('original-install-name', ['/usr/bin/install_name_tool', '-id', install_name, str(library)])
    run('sign-component', ['/usr/bin/codesign', '--force', '--sign', '-', str(library)])
    run('verify-component-signature', ['/usr/bin/codesign', '--verify', '--strict', str(library)])
    observed_identity = run('observed-install-name', ['/usr/bin/otool', '-D', str(library)])
    require(observed_identity.splitlines()[1:] == [install_name],
            'HTTP component install identity differs')
    loads = run('observed-load-commands', ['/usr/bin/otool', '-l', str(library)])
    require('cmd LC_RPATH' not in loads, 'HTTP component has an ambient loader search path')
    minimum = re.search(r'cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform 1\s+minos (\d+\.\d+(?:\.\d+)?)', loads)
    require(minimum is not None and minimum[1] == recipe['minimumMacOS'],
            'Observed HTTP component deployment requirement differs')
    header = run('observed-mach-header', ['/usr/bin/otool', '-hv', str(library)])
    require(re.search(r'\bARM64\b', header) is not None, 'Unexpected HTTP component machine ABI')
    dependencies = run('observed-dependencies', ['/usr/bin/otool', '-L', str(library)])
    require(str(openssl) not in dependencies and str(prefix) not in dependencies,
            'Static TLS input unexpectedly became an external dynamic dependency')
    observed_dependencies = []
    for line in dependencies.splitlines()[1:]:
        name = line.strip().split(' (compatibility version ', 1)[0]
        if name == install_name:
            continue
        require(name.startswith(('/usr/lib/', '/System/Library/Frameworks/')),
                'Unselected non-system HTTP library dependency')
        observed_dependencies.append(name)
    exports = run('observed-exports', ['/usr/bin/nm', '-gU', str(library)])
    names = {line.split()[-1] for line in exports.splitlines() if line.strip()}
    require({'_' + name for name in ('curl_global_init', 'curl_global_init_mem', 'curl_global_cleanup',
             'curl_version', 'curl_version_info', 'curl_easy_init', 'curl_easy_setopt',
             'curl_easy_perform', 'curl_easy_getinfo', 'curl_easy_cleanup',
             'curl_easy_strerror', 'curl_slist_append', 'curl_slist_free_all')} <= names,
            'Existing Native HTTP loader symbols are incomplete')
    if owned_openssl_receipt is not None:
        require('_curl_actql_native_tls_api_v3' in names, 'Original Read/TLS cleanup export is missing')
    run('observed-imports', ['/usr/bin/nm', '-u', str(library)])
    return observed_dependencies, minimum[1]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    for name in ('archive', 'signature', 'keyring', 'openssl', 'clang', 'make', 'gpgv', 'destination'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--target', choices=('darwin-arm64', 'linux-x64'), default='darwin-arm64')
    parser.add_argument('--minimum-macos', choices=('11.0', '26.0'))
    parser.add_argument('--seconds', type=int, required=True)
    parser.add_argument('--owned-openssl-receipt', type=Path)
    parser.add_argument('--model-resolver-archive', type=Path)
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.archive, args.signature, args.keyring,
        args.openssl, args.clang, args.sdk, args.make, args.gpgv, args.destination, args.seconds,
        args.owned_openssl_receipt, args.target, args.minimum_macos,
        model_resolver_archive=args.model_resolver_archive)))
