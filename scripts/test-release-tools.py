#!/usr/bin/env python3
"""发布边界回归：防止不同提交、被替换的文件或错误平台包进入 Release。"""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('prepare_release', Path(__file__).with_name('prepare-release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        for sdk in ('iphoneos', 'iphonesimulator'):
            self.fixture(sdk)

    def fixture(self, sdk, prefix=None):
        name = f'MelodyCamera-{sdk}'
        archive = self.output / (name + ('.ipa' if sdk == 'iphoneos' else '.zip'))
        prefix = prefix or ('Payload/MelodyCamera.app/' if sdk == 'iphoneos' else 'MelodyCamera.app/')
        with zipfile.ZipFile(archive, 'w') as package:
            for file in ('Info.plist', 'MelodyCamera', 'Legal/dependencies.json'):
                package.writestr(prefix + file, '固定打包测试数据，非真实应用')
        metadata = {'file': archive.name, 'sdk': sdk, 'commit': 'a' * 40,
                    'source_dirty': False, 'version': '0.1.0', 'build': '3',
                    'configuration': 'Release', 'architecture': 'arm64',
                    'models_included': False, 'api_key_included': False,
                    'bytes': archive.stat().st_size, 'sha256': release.digest(archive)}
        (self.output / (name + '.json')).write_text(json.dumps(metadata))

    def change(self, **values):
        path = self.output / 'MelodyCamera-iphoneos.json'
        metadata = json.loads(path.read_text())
        metadata.update(values)
        path.write_text(json.dumps(metadata))

    def check(self):
        return release.validate_assets(self.output, 'a' * 40, '0.1.0')

    def test_matching_pair_passes(self):
        self.assertEqual(self.check(), '3')

    def test_different_commit_rejected(self):
        self.change(commit='b' * 40)
        with self.assertRaises(ValueError): self.check()

    def test_uncommitted_source_rejected(self):
        self.change(source_dirty=True)
        with self.assertRaises(ValueError): self.check()

    def test_replaced_archive_rejected(self):
        (self.output / 'MelodyCamera-iphoneos.ipa').write_bytes(b'changed')
        with self.assertRaises(ValueError): self.check()

    def test_simulator_disguised_as_ipa_rejected(self):
        self.fixture('iphoneos', prefix='MelodyCamera.app/')
        with self.assertRaises(ValueError): self.check()

    def test_different_builds_rejected(self):
        self.change(build='4')
        with self.assertRaises(ValueError): self.check()

    def test_path_escape_rejected(self):
        self.change(file='../private.ipa')
        with self.assertRaises(ValueError): self.check()

    def test_model_metadata_rejected(self):
        self.change(models_included=True)
        with self.assertRaises(ValueError): self.check()


if __name__ == '__main__':
    unittest.main()
