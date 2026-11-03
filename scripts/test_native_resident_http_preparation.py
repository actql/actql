"""Source-only orchestration controls; no fixture library is compiled/loaded."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SPEC=importlib.util.spec_from_file_location('http_preparation',Path(__file__).with_name('prepare-native-resident-http-component.py'))
P=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class SignedInputs(unittest.TestCase):
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


class ExistingProducerComposition(unittest.TestCase):
    def compose(self,target,fail=False,key_fingerprint='A'*40):
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
            def build_tls(*args):
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
                    curl_archive=curl,curl_signature=signature,release_key=key,tls_archive=tls)
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

    def test_component_refusal_cannot_publish_complete_preparation(self):
        self.compose('darwin-arm64',fail=True)

    def test_foreign_primary_key_refuses_before_either_producer(self):
        self.compose('darwin-arm64',key_fingerprint='B'*40)


class OwnedTlsReceipt(unittest.TestCase):
    def test_copying_headers_preserves_the_selected_serializable_target(self):
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
            def execute(command,**kwargs):
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
                result=P.HTTP.TLS.build(source,archive,output,root/'cc',None,root/'make',root/'perl',30,'linux-x64')
            self.assertEqual(result['target'],'linux-x64')
            self.assertEqual(json.loads((output/'build.json').read_text())['target'],'linux-x64')


if __name__=='__main__':unittest.main()
