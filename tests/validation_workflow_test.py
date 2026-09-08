import pathlib
import unittest

import yaml


class ValidationWorkflowTests(unittest.TestCase):
    def test_validation_stays_on_trusted_self_hosted_branch_pushes(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        for filename in (root / ".github/workflows").glob("*.yml"):
            with self.subTest(workflow=filename.name):
                workflow = yaml.load(filename.read_text(), Loader=yaml.BaseLoader)
                self.assertEqual(set(workflow["on"]), {"push"})
                self.assertEqual(workflow["permissions"], {"contents": "read"})
                for job in workflow["jobs"].values():
                    self.assertEqual(
                        job["runs-on"],
                        ["self-hosted", "Linux", "X64", "atrium-adapters-validate"],
                    )


if __name__ == "__main__":
    unittest.main()
