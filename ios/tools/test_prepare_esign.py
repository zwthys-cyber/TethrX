"""Run on GitHub Actions; exercise the real project in a disposable directory."""

import importlib.util
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest


IOS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("prepare_esign", IOS / "tools/prepare-esign.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ESignConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ios = Path(self.temp.name)
        for relative in ("GrokRemote.xcodeproj/project.pbxproj", "GrokRemote/Info.plist"):
            target = self.ios / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(IOS / relative, target)
        self.project = self.ios / "GrokRemote.xcodeproj/project.pbxproj"
        self.info = self.ios / "GrokRemote/Info.plist"

    def test_single_app_has_no_embed_dependencies_or_original_entitlements(self):
        module.prepare(self.ios, "cn.example.personal")
        text = self.project.read_text()
        main_target = text.split("DEADBEEF0000000000000005 /* GrokRemote */ = {", 1)[1].split("\n\t\t};", 1)[0]
        self.assertNotIn("PBXTargetDependency", main_target)
        self.assertNotIn("Embed Foundation Extensions", main_target)
        self.assertNotIn("Embed Watch Content", main_target)
        self.assertNotIn("CODE_SIGN_ENTITLEMENTS = GrokRemote/GrokRemote.entitlements;", text)
        self.assertEqual(text.count("PRODUCT_BUNDLE_IDENTIFIER = cn.example.personal;"), 2)
        # Retain the extension definitions; this step only disconnects them from
        # the main target. The normal project in the checkout is not repurposed.
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = com.tethrx.app.TethrXShare;", text)
        with self.info.open("rb") as source:
            info = plistlib.load(source)
        self.assertTrue(info["TethrXStandalone"])
        self.assertFalse(info["NSSupportsLiveActivities"])
        self.assertNotIn("TethrXSharedKeychainGroup", info)
        self.assertEqual(info["CFBundleURLTypes"][0]["CFBundleURLName"], "cn.example.personal")
        self.assertIn("tethrx", info["CFBundleURLTypes"][0]["CFBundleURLSchemes"])
        self.assertTrue(info["NSAppTransportSecurity"]["NSAllowsArbitraryLoads"])

    def test_project_drift_fails_without_partial_writes(self):
        original = self.project.read_text().replace("/* Embed Watch Content */,", "/* Renamed embed */,")
        self.project.write_text(original)
        info_before = self.info.read_bytes()
        with self.assertRaises(ValueError):
            module.prepare(self.ios, "cn.example.personal")
        self.assertEqual(self.project.read_text(), original)
        self.assertEqual(self.info.read_bytes(), info_before)

    def test_invalid_bundle_id_does_not_modify_checkout(self):
        before = self.project.read_bytes()
        with self.assertRaises(ValueError):
            module.prepare(self.ios, 'bad.id; INJECTED = YES;')
        self.assertEqual(self.project.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
