"""Tag the selected physical profile; no compilation or binary download."""
import json
from pathlib import Path

from setuptools import Distribution, setup
from wheel.bdist_wheel import bdist_wheel


class LocalDistribution(Distribution):
    def has_ext_modules(self):
        # The ctypes library is platform-specific data, without a CPython ABI.
        # Keep setuptools' installation scheme aligned with the binary wheel.
        return True


class LocalWheel(bdist_wheel):
    def finalize_options(self):
        super().finalize_options()
        self.root_is_pure = False

    def get_tag(self):
        manifest = json.loads(Path('src/actql_local_runtime/artifact.json').read_bytes())
        if manifest['platform'] != 'darwin-arm64':
            raise ValueError('Unsupported selected Python Local wheel profile')
        # The recipe checks the real library target and minimum OS. Other
        # profiles remain unverified, rather than advertised by a universal tag.
        return 'py3', 'none', 'macosx_11_0_arm64'


setup(distclass=LocalDistribution, cmdclass={'bdist_wheel': LocalWheel})
