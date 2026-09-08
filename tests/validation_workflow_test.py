import pathlib
import unittest

import yaml


class ValidationWorkflowTests(unittest.TestCase):
    def test_public_repository_validation_uses_free_standard_runners(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        for filename in (root / ".github/workflows").glob("*.yml"):
            with self.subTest(workflow=filename.name):
                workflow = yaml.load(filename.read_text(), Loader=yaml.BaseLoader)
                self.assertEqual(set(workflow["on"]), {"push", "pull_request"})
                self.assertEqual(workflow["permissions"], {"contents": "read"})
                for job in workflow["jobs"].values():
                    self.assertEqual(job["runs-on"], "ubuntu-24.04")


if __name__ == "__main__":
    unittest.main()
