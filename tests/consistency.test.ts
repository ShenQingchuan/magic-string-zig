import { describe, it, expect, beforeAll } from 'vitest';
import MagicString from 'magic-string';
import { execSync } from 'node:child_process';

interface ScenarioResult {
  name: string;
  content: string;
  map: string; // JSON string of map
}

type ScenarioBuilder = (ms: MagicString, source: string) => void;

const findIndexOrThrow = (text: string, token: string, fromIndex = 0): number => {
  const idx = text.indexOf(token, fromIndex);
  if (idx === -1) {
    throw new Error(`Token "${token}" not found in scenario source`);
  }
  return idx;
};

const findLastIndexOrThrow = (text: string, token: string): number => {
  const idx = text.lastIndexOf(token);
  if (idx === -1) {
    throw new Error(`Token "${token}" not found in scenario source`);
  }
  return idx;
};

describe('Consistency Check with Zig Implementation', () => {
  let zigResults: ScenarioResult[] = [];
  const verifyScenario = (name: string, source: string, build: ScenarioBuilder) => {
    const zigResult = zigResults.find(r => r.name === name);
    if (!zigResult) throw new Error(`Scenario "${name}" not found in Zig output`);

    const ms = new MagicString(source);
    build(ms, source);

    const content = ms.toString();
    const map = ms.generateMap({
      source: 'input.js',
      file: 'output.js',
      includeContent: true,
    });

    expect(content).toBe(zigResult.content);

    const zigMap = JSON.parse(zigResult.map);
    expect(zigMap.version).toBe(map.version);
    expect(zigMap.file).toBe(map.file);
    expect(zigMap.sources).toEqual(map.sources);
    expect(zigMap.sourcesContent).toEqual(map.sourcesContent);
    expect(zigMap.names).toEqual(map.names);
    expect(zigMap.mappings).toBe(map.mappings);
  };

  beforeAll(() => {
    // 1. 构建 Zig 快照生成工具
    console.log('Building Zig snapshot generator...');
    execSync('zig build', { stdio: 'inherit' });

    // 2. 运行工具获取输出
    console.log('Running Zig snapshot generator...');
    const output = execSync('./zig-out/bin/snapshot-gen').toString();
    
    // 3. 解析 JSON
    zigResults = JSON.parse(output);
  });

  it('output should match snapshot', () => {
    expect(zigResults).toMatchSnapshot();
  });

  it('should match "complex_combination" scenario', () => {
    verifyScenario('complex_combination', 'var x = 1', ms => {
      ms.appendLeft(0, '// Comment\n');
      ms.overwrite(4, 5, 'answer');
      ms.appendRight(9, ';');
    });
  });

  it('should match "multiple_edits" scenario', () => {
    verifyScenario('multiple_edits', '1234567890', ms => {
      ms.overwrite(0, 2, 'A');
      ms.appendLeft(5, '-');
      ms.appendRight(5, '+');
      ms.overwrite(8, 10, '');
    });
  });

  it('should match "instrumented_function" scenario', () => {
    const source = `
function math(a, b) {
  const sum = a + b;
  return sum;
}
    `.trim();

    verifyScenario('instrumented_function', source, (ms, original) => {
      ms.appendLeft(0, '/* header */\n');

      const braceBoundary = findIndexOrThrow(original, '{') + 1;
      ms.appendLeft(braceBoundary, '\n  console.time("math");');

      const sumLine = '  const sum = a + b;';
      const sumBoundary = findIndexOrThrow(original, sumLine) + sumLine.length;
      ms.appendRight(sumBoundary, '\n  console.log(sum);');

      const returnLine = '  return sum;';
      const returnIndex = findIndexOrThrow(original, returnLine);
      ms.appendLeft(returnIndex, '  console.timeEnd("math");\n');
      ms.overwrite(returnIndex, returnIndex + returnLine.length, '  return sum * 2;');

      const closingBraceBoundary = findLastIndexOrThrow(original, '}') + 1;
      ms.appendRight(closingBraceBoundary, '\n// done');

      ms.appendRight(original.length, '\n/* footer */');
    });
  });

  it('should match "tracked_calls" scenario', () => {
    const source = `
let result = format(user.firstName);
result += ':' + format(user.lastName);
return result;
    `.trim();

    verifyScenario('tracked_calls', source, (ms, original) => {
      ms.overwrite(0, 'let'.length, 'const');

      const firstCall = 'format(user.firstName)';
      const firstStart = findIndexOrThrow(original, firstCall);
      ms.appendLeft(firstStart, 'track(');
      ms.appendRight(firstStart + firstCall.length, ', "first")');

      const secondCall = 'format(user.lastName)';
      const secondStart = findIndexOrThrow(original, secondCall);
      ms.appendLeft(secondStart, 'track(');
      ms.appendRight(secondStart + secondCall.length, ', "last")');

      const returnIndex = findIndexOrThrow(original, 'return result;');
      ms.appendLeft(returnIndex, '// finalize\n');

      const firstLineTerminator = findIndexOrThrow(original, ';\n');
      ms.appendRight(firstLineTerminator + 1, ' // init done');

      ms.appendRight(original.length, '\nconsole.log(result);');
    });
  });
});

