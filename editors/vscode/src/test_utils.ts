// The main point of having this as an extra module is to make this function available for regression testing.

export interface OdinTestProc {
	function: string;
	pkg: string;
	index: number;
	length: number;
}

export function findOdinTestProcs(text: string): OdinTestProc[] {
	const packageMatch = /\bpackage\s+(\w+)/.exec(text);
	if (packageMatch === null) {
		return [];
	}

	const reTest = /\@\(?test\)?/g;
	const reFnTest = /\s*\w+\s*::\s*proc\s*\s*\(/g;
	const methods: OdinTestProc[] = [];
	let testMatch: RegExpExecArray | null;

	while ((testMatch = reTest.exec(text)) !== null) {
		reFnTest.lastIndex = reTest.lastIndex;
		const fnMatch = reFnTest.exec(text);
		if (fnMatch === null) {
			continue;
		}

		const fn = fnMatch[0].split(":")[0].trim();
		if (fn.length > 0) {
			methods.push({
				function: fn,
				pkg: packageMatch[1],
				index: reTest.lastIndex,
				length: testMatch[0].length,
			});
		}
	}

	return methods;
}

export function getOdinTestName(pkg: string, fn: string): string {
	return `${pkg}.${fn}`;
}
