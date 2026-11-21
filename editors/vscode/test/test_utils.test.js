const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { findOdinTestProcs, getOdinTestName } = require("../out/test_utils");

// Regression test for https://github.com/DanielGavin/ols/issues/1546
// This tests that the test name that will be passed to ODIN_TEST_NAMES uses the name specified with the `package`
// directive at the top of the file, not the name of the containing directory (old behavior).

describe("CodeLens command selection", () => {
	it("uses the declared package for every test, regardless of the directory name", () => {
		const sourcePath = path.join(__dirname, "fixtures", "CodeLens_command_test", "tests.odin");
		const source = fs.readFileSync(sourcePath, "utf8");
		const methods = findOdinTestProcs(source);

		// Make sure someone doesn't rename the directory to match the package directive.
		assert.notStrictEqual(path.basename(path.dirname(sourcePath)), "CodeBens");
		assert.deepStrictEqual(
			methods.map(({ pkg, function: fn }) => getOdinTestName(pkg, fn)),
			[
				"CodeBens.one_test",
				"CodeBens.another_test",
			],
		);
	});

	it("returns no tests when the source has no package declaration", () => {
		assert.deepStrictEqual(findOdinTestProcs("@(test)\ntest_proc :: proc() {}"), []);
	});
});
