import { describe, it, expect, beforeAll } from 'vitest';
import MagicString from 'magic-string';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

interface ScenarioResult {
  name: string;
  content: string;
  map: string; // JSON string of map
}

describe('Consistency Check with Zig Implementation', () => {
  let zigResults: ScenarioResult[] = [];

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

  it('should match "complex_combination" scenario', () => {
    const zigResult = zigResults.find(r => r.name === 'complex_combination');
    if (!zigResult) throw new Error('Scenario "complex_combination" not found in Zig output');

    const ms = new MagicString('var x = 1');
    ms.appendLeft(0, '// Comment\n');
    ms.overwrite(4, 5, 'answer');
    ms.appendRight(9, ';');

    const content = ms.toString();
    const map = ms.generateMap({
      source: 'input.js',
      file: 'output.js',
      includeContent: true,
    });

    // 验证内容一致
    expect(content).toBe(zigResult.content);

    // 验证 Source Map 一致
    // Zig 输出的 map 是字符串，需要 parse
    const zigMap = JSON.parse(zigResult.map);
    
    // 规范化 map 进行比较
    // magic-string JS 版本生成的 map version 是 number 3
    expect(zigMap.version).toBe(map.version);
    expect(zigMap.file).toBe(map.file);
    expect(zigMap.sources).toEqual(map.sources);
    expect(zigMap.sourcesContent).toEqual(map.sourcesContent);
    expect(zigMap.mappings).toBe(map.mappings);
  });

  it('should match "multiple_edits" scenario', () => {
    const zigResult = zigResults.find(r => r.name === 'multiple_edits');
    if (!zigResult) throw new Error('Scenario "multiple_edits" not found in Zig output');

    const ms = new MagicString('1234567890');
    ms.overwrite(0, 2, 'A'); // 12 -> A
    ms.appendLeft(5, '-');   // after 5
    ms.appendRight(5, '+');  // after 5
    ms.overwrite(8, 10, ''); // 90 -> ""

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
    expect(zigMap.mappings).toBe(map.mappings);
  });
});

