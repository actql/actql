"""Source-only orchestration controls; no fixture library is compiled/loaded."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

SPEC=importlib.util.spec_from_file_location('http_preparation',Path(__file__).with_name('prepare-native-resident-http-component.py'))
P=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class SignedInputs(unittest.TestCase):
    def test_release_key_uses_exact_source_or_original_without_network(self):
        key=json.loads((P.ROOT/'scripts/native-http-component-source.json').read_text())['upstream']['releaseKey']
        source=P.ROOT/key['sourcePath']
        with tempfile.TemporaryDirectory() as raw:
            destination=Path(raw)/'downloaded-key'
            with patch.object(P.urllib.request,'urlopen',side_effect=urllib.error.URLError('Network is unreachable')) as network:
                for original in (None,source):
                    with self.subTest(explicit=original is not None):
                        self.assertEqual(P.acquire_release_key(key,destination,original,1),source)
                network.assert_not_called()
            self.assertFalse(destination.exists())

    def test_bad_source_key_refuses_without_keyserver_fallback(self):
        key=json.loads((P.ROOT/'scripts/native-http-component-source.json').read_text())['upstream']['releaseKey']
        with tempfile.TemporaryDirectory() as raw:
            root=Path(raw);source=root/key['sourcePath'];source.parent.mkdir(parents=True)
            source.write_bytes(b'x'*key['bytes'])
            with patch.object(P,'ROOT',root),patch.object(P.urllib.request,'urlopen',side_effect=AssertionError('network fallback')) as network:
                with self.assertRaisesRegex(ValueError,'original HTTP preparation input differs'):
                    P.acquire_release_key(key,root/'output',None,1)
                source.unlink()
                with self.assertRaises((OSError,ValueError)):
                    P.acquire_release_key(key,root/'output',None,1)
                network.assert_not_called()
            self.assertFalse((root/'output').exists())

    def test_unavailable_download_does_not_publish_unverified_input(self):
        with tempfile.TemporaryDirectory() as raw:
            destination=Path(raw)/'download'
            with patch.object(P.urllib.request,'urlopen',side_effect=urllib.error.URLError('Network is unreachable')):
                with self.assertRaises(urllib.error.URLError):
                    P.acquire('https://unused',{'bytes':1,'sha256':'0'*64},destination,None,1)
            self.assertFalse(destination.exists())

    def test_original_metadata_roundtrips_as_exact_decimal_strings(self):
        with tempfile.TemporaryDirectory() as raw:
            path=Path(raw)/'original';path.write_bytes(b'original');current=path.stat()
            item=P.HTTP.original(path)
            for key,value in [('dev',current.st_dev),('ino',current.st_ino),('mode',current.st_mode)]:
                self.assertEqual(item[key],str(value))
                self.assertEqual(json.loads(json.dumps(item))[key],str(value))

    def test_changed_original_is_refused_without_downloading_or_copying(self):
        with tempfile.TemporaryDirectory() as raw:
            root=Path(raw);original=root/'original';original.write_bytes(b'changed')
            with patch.object(P.urllib.request,'urlopen',side_effect=AssertionError('network fallback')):
                with self.assertRaisesRegex(ValueError,'original HTTP preparation input differs'):
                    P.acquire('https://unused',{'bytes':1,'sha256':'0'*64},root/'output',original,1)
            self.assertFalse((root/'output').exists())


class LinuxInspectionTools(unittest.TestCase):
    """Real input/alias/receipt checks with explicit build and inspector ports."""

    def produce(self, root, *, change_tool=False, missing_tool=False):
        source='a'*40
        (root/'scripts').mkdir()
        lifetime=root/'src/platform_native/http_client'
        lifetime.mkdir(parents=True)
        for path in (root/'scripts/produce-native-remote-scoped-runtime.py',
                     root/'scripts/produce-native-http-tls.py',
                     lifetime/'component_tls_lifetime.c', lifetime/'component_tls_lifetime.h'):
            path.write_bytes(b'Explicit source fixture; never compiled')
        curl=root/'curl-source';curl.mkdir()
        (curl/'COPYING').write_text('Fixture license')
        (curl/'configure').write_text('Explicit configure port')
        archive=root/'curl.tar.xz'
        with tarfile.open(archive,'w:xz') as stream:stream.add(curl,arcname='curl-test')
        signature=root/'signature';signature.write_bytes(b'Explicit signature-verifier port')
        pin=lambda path:{'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        recipe={'upstream':{'version':'test','archive':pin(archive),'signature':pin(signature),
                           'signerFingerprint':'A'*40},'ownedOpenSSLSource':{'version':'fixture'},'configure':[]}
        (root/'scripts/native-http-component-source.json').write_text(json.dumps(recipe))
        stage=root/'tls';(stage/'lib').mkdir(parents=True);(stage/'include').mkdir()
        for name in ('lib/libssl.a','lib/libcrypto.a','LICENSE.txt'):
            (stage/name).write_bytes(b'Explicit TLS input; never loaded')
        owned=root/'tls.json'
        owned.write_text(json.dumps({'target':'linux-x64','minimumMacOS':None,
            'upstream':recipe['ownedOpenSSLSource'],'stage':str(stage),'inputs':[],
            'files':[P.HTTP.NATIVE.original(stage/name) for name in ('lib/libssl.a','lib/libcrypto.a','LICENSE.txt')]}))
        paths={}
        for name in ('nm','readelf','foreign-nm','cc','make','gpgv','keyring'):
            paths[name]=root/name;paths[name].write_bytes(('Original '+name).encode())
        aliases={name:root/(name+'-link') for name in ('nm','readelf')}
        for name,path in aliases.items():path.symlink_to(paths[name])
        if missing_tool:paths['nm'].unlink()
        output=root/'output';commands=[]
        def selected_path(*args,**kwargs):
            path=Path(*args,**kwargs)
            return {Path('/usr/bin/nm'):aliases['nm'],Path('/usr/bin/readelf'):aliases['readelf']}.get(path,path)
        def execute(command,**kwargs):
            commands.append(command)
            text=''
            if command[0]==str(paths['gpgv']):
                text='[GNUPG:] VALIDSIG '+'A'*40+'\n'
                aliases['nm'].unlink();aliases['nm'].symlink_to(paths['foreign-nm'])
            elif command[0]==str(paths['make']):
                library=output/'build/lib/.libs/libcurl.so.4';library.parent.mkdir(parents=True)
                header=bytearray(64);header[:7]=b'\x7fELF\x02\x01\x01'
                header[16:18]=(3).to_bytes(2,'little');header[18:20]=(62).to_bytes(2,'little')
                library.write_bytes(header)
            elif command[0]==str(paths['readelf']):
                text='(NEEDED) Shared library: [libc.so.6]\n(SONAME) Library soname: [libcurl.so.4]\n'
            elif command[0]==str(paths['nm']):
                if '--defined-only' in command:
                    text='\n'.join('0000 T '+name for name in P.HTTP.CURL_EXPORTS|{'curl_actql_native_tls_api_v3'})
                elif change_tool:paths['nm'].write_bytes(b'Changed original inspection tool')
            else:self.assertIn(command[0],('/bin/sh',str(paths['cc'])))
            return subprocess.CompletedProcess(command,0,text,'')
        with patch.object(P.HTTP,'ROOT',root),patch.object(P.HTTP,'RECIPE',root/'scripts/native-http-component-source.json'),\
                patch.object(P.HTTP,'Path',side_effect=selected_path),\
                patch.object(P.HTTP.sys,'platform','linux'),patch.object(P.HTTP.platform,'machine',return_value='x86_64'),\
                patch.object(P.HTTP.subprocess,'check_output',side_effect=lambda args,**kw:source+'\n' if 'rev-parse' in args else ''),\
                patch.object(P.HTTP.subprocess,'run',side_effect=execute):
            result=P.HTTP.build(source,archive,signature,paths['keyring'],stage,paths['cc'],None,
                                paths['make'],paths['gpgv'],output,30,owned,'linux-x64')
        return result,commands,paths,aliases

    def test_aliases_pin_and_invoke_the_same_original_inspection_tools(self):
        with tempfile.TemporaryDirectory() as raw:
            result,commands,paths,aliases=self.produce(Path(raw).resolve())
            for name in ('nm','readelf'):
                item=next(item for item in result['inputs'] if item['path']==str(paths[name]))
                self.assertEqual(item,P.HTTP.original(paths[name]))
                self.assertTrue(any(command[0]==str(paths[name]) for command in commands))
                self.assertFalse(any(command[0]==str(aliases[name]) for command in commands))
            self.assertEqual(aliases['nm'].resolve(),paths['foreign-nm'])
            with self.assertRaisesRegex(ValueError,'Original build input unavailable'):
                P.HTTP.original(aliases['nm'])
            self.assertEqual(result['loaded'],0);self.assertEqual(result['initialized'],0)

    def test_changed_original_tool_is_refused_before_receipt_publication(self):
        with tempfile.TemporaryDirectory() as raw:
            root=Path(raw).resolve()
            with self.assertRaisesRegex(ValueError,'Original input changed during component production'):
                self.produce(root,change_tool=True)
            self.assertFalse((root/'output/build.json').exists())

    def test_missing_inspection_target_refuses_before_output_creation(self):
        with tempfile.TemporaryDirectory() as raw:
            root=Path(raw).resolve()
            with self.assertRaises((OSError,ValueError)):self.produce(root,missing_tool=True)
            self.assertFalse((root/'output').exists())


class ExistingProducerComposition(unittest.TestCase):
    def compose(self,target,fail=False,key_fingerprint='A'*40,tls_jobs=1):
        with tempfile.TemporaryDirectory() as raw:
            root=Path(raw).resolve();(root/'scripts').mkdir()
            data=b'pinned Source-only input';pin={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
            recipe={'upstream':{'url':'https://curl.invalid/source','archive':pin,'signature':pin,
                'releaseKey':{'url':'https://key.invalid/key',**pin},'signerFingerprint':'A'*40},
                'ownedOpenSSLSource':{'url':'https://tls.invalid/source','archive':pin}}
            (root/'scripts/native-http-component-source.json').write_text(json.dumps(recipe))
            files=[]
            for name in ('curl','signature','key','tls','cc','make','perl','gpg','gpgv'):
                path=root/name;path.write_bytes(data);files.append(path)
            curl,signature,key,tls,cc,make,perl,gpg,gpgv=files
            calls=[]
            def gpg_run(command,**kwargs):
                self.assertIn('--no-autostart',command)
                self.assertIn('--no-auto-key-retrieve',command)
                output=(('pub:-\nfpr:::::::::'+key_fingerprint+':\nsub:-\nfpr:::::::::'+'C'*40+':\n').encode() if '--with-colons' in command
                        else b'public key bytes' if '--dearmor' in command else b'')
                if '--dearmor' in command:
                    self.assertEqual(command[command.index('--output')+1],'-')
                else:self.assertIn('show-only',command)
                return subprocess.CompletedProcess(command,0,output,b'')
            def build_tls(*args,**kwargs):
                self.assertEqual(kwargs,{'jobs':tls_jobs})
                calls.append(('tls',args));destination=args[2];destination.mkdir()
                stage=destination/'stage';stage.mkdir()
                (destination/'build.json').write_text(json.dumps({'source':args[0],'target':args[-2]}))
                return {'stage':str(stage)}
            def build_http(*args):
                calls.append(('http',args))
                if fail: raise ValueError('original signed component refusal')
                args[9].mkdir();(args[9]/'build.json').write_text(json.dumps({'source':args[0]}))
            source='a'*40;output=root/'output';sdk=root/'SDK' if target=='darwin-arm64' else None
            with patch.object(P,'ROOT',root),patch.object(P.subprocess,'check_output',
                    side_effect=lambda args,**kw:source+'\n' if 'rev-parse' in args else ''),\
                    patch.object(P.subprocess,'run',side_effect=gpg_run),\
                    patch.object(P.HTTP.TLS,'build',side_effect=build_tls),\
                    patch.object(P.HTTP,'build',side_effect=build_http),\
                    patch.object(P.urllib.request,'urlopen',side_effect=AssertionError('duplicate download')):
                invoke=lambda:P.prepare(source,target,cc,sdk,make,perl,gpg,gpgv,output,60,
                    curl_archive=curl,curl_signature=signature,release_key=key,tls_archive=tls,tls_jobs=tls_jobs)
                if key_fingerprint!='A'*40:
                    with self.assertRaisesRegex(ValueError,'release key fingerprint differs'):invoke()
                    self.assertFalse(calls);self.assertFalse((output/'preparation.json').exists());return
                if fail:
                    with self.assertRaisesRegex(ValueError,'original signed component refusal'): invoke()
                    self.assertFalse((output/'preparation.json').exists());return
                result=invoke()
            minimum='11.0' if sdk else None
            self.assertEqual([name for name,_ in calls],['tls','http'])
            self.assertEqual(calls[0][1][-2:],(target,minimum))
            self.assertEqual(calls[1][1][-2:],(target,minimum))
            self.assertEqual(calls[1][1][-3],output/'owned-tls/build.json')
            self.assertEqual(result['minimumMacOS'],minimum)
            self.assertEqual(result['loaded'],0);self.assertFalse(result['installed_supplier'])
            self.assertTrue((output/'preparation.json').is_file())

    def test_same_existing_producers_select_linux_and_compatible_macos_explicitly(self):
        for target in ('linux-x64','darwin-arm64'):
            with self.subTest(target=target):self.compose(target)

    def test_explicit_two_jobs_reach_the_same_tls_producer(self):
        self.compose('darwin-arm64',tls_jobs=2)

    def test_component_refusal_cannot_publish_complete_preparation(self):
        self.compose('darwin-arm64',fail=True)

    def test_foreign_primary_key_refuses_before_either_producer(self):
        self.compose('darwin-arm64',key_fingerprint='B'*40)


class OwnedTlsReceipt(unittest.TestCase):
    def produce(self,jobs=None):
        with tempfile.TemporaryDirectory() as raw:
            root=Path(raw).resolve();(root/'scripts').mkdir()
            source='a'*40;original=root/'original/openssl-test'
            (original/'crypto').mkdir(parents=True);(original/'include/openssl').mkdir(parents=True)
            before=b'OPENSSL_zalloc(sizeof(pthread_rwlock_t))\nOPENSSL_zalloc(sizeof(pthread_mutex_t))\n'
            after=before.replace(b'OPENSSL_zalloc(sizeof(pthread_rwlock_t))',b'CRYPTO_zalloc(sizeof(pthread_rwlock_t), NULL, 0)').replace(
                b'OPENSSL_zalloc(sizeof(pthread_mutex_t))',b'CRYPTO_zalloc(sizeof(pthread_mutex_t), NULL, 0)')
            (original/'crypto/threads_pthread.c').write_bytes(before)
            (original/'include/openssl/original.h').write_bytes(b'Source-only header')
            (original/'LICENSE.txt').write_bytes(b'Source-only license')
            archive=root/'source.tar.gz'
            with tarfile.open(archive,'w:gz') as stream:stream.add(original,arcname='openssl-test')
            recipe={'version':'test','archive':{'bytes':archive.stat().st_size,
                'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()},'configure':[],
                'lockAllocationRefusal':{'path':'crypto/threads_pthread.c',
                    'beforeSha256':hashlib.sha256(before).hexdigest(),'afterSha256':hashlib.sha256(after).hexdigest()}}
            (root/'scripts/native-http-component-source.json').write_text(json.dumps({'ownedOpenSSLSource':recipe}))
            (root/'scripts/produce-native-remote-scoped-runtime.py').write_bytes(b'Source-only original observer')
            for name in ('cc','make','perl'):(root/name).write_bytes(b'Source-only tool')
            output=root/'output'
            commands=[]
            def execute(command,**kwargs):
                commands.append(command)
                if 'build_libs' in command:
                    build=output/'build'
                    for name in ('libssl.a','libcrypto.a'):(build/name).write_bytes(b'Fixture archive; never loaded')
                    (build/'include/openssl').mkdir(parents=True)
                    (build/'include/openssl/configuration.h').write_text('#define OPENSSL_NO_PINSHARED\n#define OPENSSL_NO_ATEXIT\n')
                return subprocess.CompletedProcess(command,0,'','')
            with patch.object(P.HTTP.TLS,'ROOT',root),patch.object(P.HTTP.TLS.sys,'platform','linux'),\
                    patch.object(P.HTTP.TLS.platform,'machine',return_value='x86_64'),\
                    patch.object(P.HTTP.TLS.subprocess,'check_output',
                        side_effect=lambda args,**kw:source+'\n' if 'rev-parse' in args else ''),\
                    patch.object(P.HTTP.TLS.subprocess,'run',side_effect=execute):
                result=P.HTTP.TLS.build(source,archive,output,root/'cc',None,root/'make',root/'perl',30,'linux-x64',
                    **({} if jobs is None else {'jobs':jobs}))
            self.assertEqual(result['target'],'linux-x64')
            receipt=json.loads((output/'build.json').read_text())
            self.assertEqual(receipt['target'],'linux-x64')
            self.assertEqual(receipt['buildJobs'],1 if jobs is None else jobs)
            self.assertIn([str(root/'make'),'-j'+str(1 if jobs is None else jobs),'build_libs'],commands)

    def test_copying_headers_preserves_the_selected_serializable_target(self):
        self.produce()

    def test_two_job_build_keeps_target_headers_and_records_actual_parallelism(self):
        self.produce(jobs=2)

    def test_invalid_parallelism_refuses_before_io_or_commands(self):
        for jobs in (True,False,0,3,-1,1.5,'2',None):
            with self.subTest(jobs=jobs),patch.object(P.HTTP.TLS.subprocess,'check_output',side_effect=AssertionError('Source read')):
                with self.assertRaisesRegex(ValueError,'TLS build jobs'):
                    P.HTTP.TLS.build('a'*40,None,None,None,None,None,None,30,jobs=jobs)
                with self.assertRaisesRegex(ValueError,'TLS build jobs'):
                    P.prepare('a'*40,'linux-x64',None,None,None,None,None,None,None,30,tls_jobs=jobs)


if __name__=='__main__':unittest.main()
