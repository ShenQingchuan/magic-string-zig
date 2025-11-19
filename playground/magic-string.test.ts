import { describe, it, expect, afterEach } from 'vitest';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import os from 'os';

const require = createRequire(import.meta.url);
const __dirname = dirname(fileURLToPath(import.meta.url));

const platform = os.platform();
const arch = os.arch();

const addonPath = join(__dirname, `../zig-out/lib/magic-string.${platform}-${arch}.node`);

interface MagicStringAddon {
  createMagicString(source: string): number;
  toString(handle: number): string;
  appendLeft(handle: number, index: number, content: string): void;
  appendRight(handle: number, index: number, content: string): void;
  overwrite(handle: number, start: number, end: number, content: string): void;
  generateMap(handle: number): string;
  destroy(handle: number): void;
}

const addon = require(addonPath) as MagicStringAddon;

describe('MagicString - Phase 1: 基础功能', () => {
  const handles: number[] = [];

  afterEach(() => {
    // 清理所有测试中创建的 handle
    handles.forEach(h => addon.destroy(h));
    handles.length = 0;
  });

  it('应该正确初始化并返回原始字符串', () => {
    const handle = addon.createMagicString("Hello, World!");
    handles.push(handle);
    
    const result = addon.toString(handle);
    expect(result).toBe("Hello, World!");
  });

  it('应该处理空字符串', () => {
    const handle = addon.createMagicString("");
    handles.push(handle);
    
    const result = addon.toString(handle);
    expect(result).toBe("");
  });

  it('应该正确处理特殊字符和 Unicode', () => {
    const handle = addon.createMagicString("你好 🎉 \n\t");
    handles.push(handle);
    
    const result = addon.toString(handle);
    expect(result).toBe("你好 🎉 \n\t");
  });

  it('应该处理较长的字符串', () => {
    const longStr = "a".repeat(1000);
    const handle = addon.createMagicString(longStr);
    handles.push(handle);
    
    const result = addon.toString(handle);
    expect(result).toBe(longStr);
  });
});

describe('MagicString - Phase 2: appendLeft/appendRight', () => {
  const handles: number[] = [];

  afterEach(() => {
    handles.forEach(h => addon.destroy(h));
    handles.length = 0;
  });

  it('应该在开头 appendLeft', () => {
    const handle = addon.createMagicString("world");
    handles.push(handle);
    
    addon.appendLeft(handle, 0, "Hello ");
    const result = addon.toString(handle);
    expect(result).toBe("Hello world");
  });

  it('应该在末尾 appendRight', () => {
    const handle = addon.createMagicString("Hello");
    handles.push(handle);
    
    addon.appendRight(handle, 5, " world");
    const result = addon.toString(handle);
    expect(result).toBe("Hello world");
  });

  it('应该在中间 appendLeft', () => {
    const handle = addon.createMagicString("ac");
    handles.push(handle);
    
    addon.appendLeft(handle, 1, "b");
    const result = addon.toString(handle);
    expect(result).toBe("abc");
  });

  it('应该在中间 appendRight', () => {
    const handle = addon.createMagicString("ac");
    handles.push(handle);
    
    addon.appendRight(handle, 1, "b");
    const result = addon.toString(handle);
    expect(result).toBe("abc");
  });

  it('应该支持多次 appendLeft', () => {
    const handle = addon.createMagicString("world");
    handles.push(handle);
    
    addon.appendLeft(handle, 0, "Hello ");
    addon.appendLeft(handle, 0, ">>> ");
    const result = addon.toString(handle);
    expect(result).toBe(">>> Hello world");
  });

  it('应该支持多次 appendRight', () => {
    const handle = addon.createMagicString("Hello");
    handles.push(handle);
    
    addon.appendRight(handle, 5, " world");
    addon.appendRight(handle, 5, " <<<");
    const result = addon.toString(handle);
    expect(result).toBe("Hello <<< world");
  });

  it('应该支持混合使用 appendLeft 和 appendRight', () => {
    const handle = addon.createMagicString("var x = 1");
    handles.push(handle);
    
    addon.appendLeft(handle, 0, "// Comment\n");
    addon.appendRight(handle, 9, ";");
    const result = addon.toString(handle);
    expect(result).toBe("// Comment\nvar x = 1;");
  });
});

describe('MagicString - Phase 3: overwrite', () => {
  const handles: number[] = [];

  afterEach(() => {
    handles.forEach(h => addon.destroy(h));
    handles.length = 0;
  });

  it('应该能替换整个字符串', () => {
    const handle = addon.createMagicString("problems = 99");
    handles.push(handle);
    
    addon.overwrite(handle, 0, 8, "answer");
    const result = addon.toString(handle);
    expect(result).toBe("answer = 99");
  });

  it('应该能替换字符串的一部分', () => {
    const handle = addon.createMagicString("var x = 1");
    handles.push(handle);
    
    addon.overwrite(handle, 4, 5, "answer");
    const result = addon.toString(handle);
    expect(result).toBe("var answer = 1");
  });

  it('应该能替换末尾的字符', () => {
    const handle = addon.createMagicString("var x = 99");
    handles.push(handle);
    
    addon.overwrite(handle, 8, 10, "42");
    const result = addon.toString(handle);
    expect(result).toBe("var x = 42");
  });

  it('应该能用空字符串替换（删除效果）', () => {
    const handle = addon.createMagicString("var x = 1");
    handles.push(handle);
    
    addon.overwrite(handle, 0, 4, "");
    const result = addon.toString(handle);
    expect(result).toBe("x = 1");
  });

  it('应该保留 overwrite 前的 appendLeft/Right', () => {
    const handle = addon.createMagicString("var x = 1");
    handles.push(handle);
    
    addon.appendLeft(handle, 0, "// Start\n");
    addon.appendRight(handle, 9, ";");
    addon.overwrite(handle, 4, 5, "answer");
    
    const result = addon.toString(handle);
    expect(result).toBe("// Start\nvar answer = 1;");
  });

  it('应该能多次 overwrite 不同的位置', () => {
    const handle = addon.createMagicString("var x = 1 + 2");
    handles.push(handle);
    
    addon.overwrite(handle, 4, 5, "a");
    addon.overwrite(handle, 8, 9, "10");
    addon.overwrite(handle, 12, 13, "20");
    
    const result = addon.toString(handle);
    expect(result).toBe("var a = 10 + 20");
  });

  it('应该能用更长的字符串替换', () => {
    const handle = addon.createMagicString("x = 1");
    handles.push(handle);
    
    addon.overwrite(handle, 0, 1, "answer");
    const result = addon.toString(handle);
    expect(result).toBe("answer = 1");
  });

  it('应该能在 overwrite 后的位置继续 appendLeft', () => {
    const handle = addon.createMagicString("abc");
    handles.push(handle);
    
    addon.overwrite(handle, 1, 2, "XXX");
    expect(addon.toString(handle)).toBe("aXXXc");
    
    addon.appendLeft(handle, 1, ">>>");
    const result = addon.toString(handle);
    expect(result).toBe("a>>>XXXc");
  });

  it('应该能在 overwrite 后的位置继续 appendRight', () => {
    const handle = addon.createMagicString("abc");
    handles.push(handle);
    
    addon.overwrite(handle, 1, 2, "XXX");
    expect(addon.toString(handle)).toBe("aXXXc");
    
    addon.appendRight(handle, 1, "<<<");
    const result = addon.toString(handle);
    expect(result).toBe("a<<<XXXc");
  });

  it('应该能在 overwrite 范围内的多个位置 append', () => {
    const handle = addon.createMagicString("abcdef");
    handles.push(handle);
    
    addon.overwrite(handle, 2, 4, "XX");
    expect(addon.toString(handle)).toBe("abXXef");
    
    addon.appendLeft(handle, 2, "[");
    addon.appendRight(handle, 4, "]");
    const result = addon.toString(handle);
    expect(result).toBe("ab[XX]ef");
  });
});

describe('MagicString - Phase 4: Source Map', () => {
  const handles: number[] = [];

  afterEach(() => {
    handles.forEach(h => addon.destroy(h));
    handles.length = 0;
  });

  it('应该生成基础的 Source Map', () => {
    const handle = addon.createMagicString("abc");
    handles.push(handle);

    const mapJson = addon.generateMap(handle);
    const map = JSON.parse(mapJson);

    // 验证必需字段
    expect(map.version).toBe(3);
    expect(map.sources).toEqual(['']);
    expect(map.names).toEqual([]);
    expect(typeof map.mappings).toBe('string');
    expect(map.mappings.length).toBeGreaterThan(0);
  });

  it('应该为 overwrite 操作生成正确的映射', () => {
    const handle = addon.createMagicString("var x = 1");
    handles.push(handle);

    addon.overwrite(handle, 4, 5, "answer");
    const result = addon.toString(handle);
    expect(result).toBe("var answer = 1");

    const mapJson = addon.generateMap(handle);
    const map = JSON.parse(mapJson);

    // 验证基本结构
    expect(map.version).toBe(3);
    expect(map.mappings).toBeTruthy();
    // mappings 应该包含映射信息
    expect(map.mappings.length).toBeGreaterThan(0);
  });

  it('应该为 appendLeft 操作生成映射', () => {
    const handle = addon.createMagicString("hello");
    handles.push(handle);

    addon.appendLeft(handle, 0, ">>> ");
    const result = addon.toString(handle);
    expect(result).toBe(">>> hello");

    const mapJson = addon.generateMap(handle);
    const map = JSON.parse(mapJson);
    
    expect(map.version).toBe(3);
    expect(map.mappings).toBeTruthy();
  });
});

describe('MagicString - 对比测试: 对比原版 magic-string', () => {
  // 导入原版 magic-string
  const MagicStringJS = require('magic-string');
  const handles: number[] = [];

  afterEach(() => {
    handles.forEach(h => addon.destroy(h));
    handles.length = 0;
  });

  it('对比测试: 简单字符串应生成相同的 mappings', () => {
    const source = 'abc';
    
    // Zig 版本
    const handleZig = addon.createMagicString(source);
    handles.push(handleZig);
    const mapZig = JSON.parse(addon.generateMap(handleZig));
    
    // JS 版本
    const msJS = new MagicStringJS(source);
    const mapJS = msJS.generateMap();
    
    // 对比关键字段
    expect(mapZig.version).toBe(mapJS.version);
    expect(mapZig.sources).toEqual(mapJS.sources);
    expect(mapZig.names).toEqual(mapJS.names);
    expect(mapZig.mappings).toBe(mapJS.mappings);
  });

  it('对比测试: appendLeft 应生成相同的 mappings', () => {
    const source = 'hello';
    
    // Zig 版本
    const handleZig = addon.createMagicString(source);
    handles.push(handleZig);
    addon.appendLeft(handleZig, 0, '>>> ');
    const resultZig = addon.toString(handleZig);
    const mapZig = JSON.parse(addon.generateMap(handleZig));
    
    // JS 版本
    const msJS = new MagicStringJS(source);
    msJS.appendLeft(0, '>>> ');
    const resultJS = msJS.toString();
    const mapJS = msJS.generateMap();
    
    // 验证输出一致
    expect(resultZig).toBe(resultJS);
    
    // 对比 Source Map
    expect(mapZig.version).toBe(mapJS.version);
    expect(mapZig.sources).toEqual(mapJS.sources);
    expect(mapZig.mappings).toBe(mapJS.mappings);
  });

  it('对比测试: appendRight 应生成相同的 mappings', () => {
    const source = 'hello';
    
    // Zig 版本
    const handleZig = addon.createMagicString(source);
    handles.push(handleZig);
    addon.appendRight(handleZig, 5, ' <<<');
    const resultZig = addon.toString(handleZig);
    const mapZig = JSON.parse(addon.generateMap(handleZig));
    
    // JS 版本
    const msJS = new MagicStringJS(source);
    msJS.appendRight(5, ' <<<');
    const resultJS = msJS.toString();
    const mapJS = msJS.generateMap();
    
    // 验证输出一致
    expect(resultZig).toBe(resultJS);
    
    // 对比 Source Map
    expect(mapZig.mappings).toBe(mapJS.mappings);
  });

  it('对比测试: overwrite 应生成相同的 mappings', () => {
    const source = 'var x = 1';
    
    // Zig 版本
    const handleZig = addon.createMagicString(source);
    handles.push(handleZig);
    addon.overwrite(handleZig, 4, 5, 'answer');
    const resultZig = addon.toString(handleZig);
    const mapZig = JSON.parse(addon.generateMap(handleZig));
    
    // JS 版本
    const msJS = new MagicStringJS(source);
    msJS.overwrite(4, 5, 'answer');
    const resultJS = msJS.toString();
    const mapJS = msJS.generateMap();
    
    // 验证输出一致
    expect(resultZig).toBe(resultJS);
    
    // 对比 Source Map
    expect(mapZig.version).toBe(mapJS.version);
    expect(mapZig.mappings).toBe(mapJS.mappings);
  });

  it('对比测试: 复杂操作组合应生成相同的 mappings', () => {
    const source = 'var x = 1';
    
    // Zig 版本
    const handleZig = addon.createMagicString(source);
    handles.push(handleZig);
    addon.appendLeft(handleZig, 0, '// Comment\n');
    addon.overwrite(handleZig, 4, 5, 'answer');
    addon.appendRight(handleZig, 9, ';');
    const resultZig = addon.toString(handleZig);
    const mapZig = JSON.parse(addon.generateMap(handleZig));
    
    // JS 版本
    const msJS = new MagicStringJS(source);
    msJS.appendLeft(0, '// Comment\n');
    msJS.overwrite(4, 5, 'answer');
    msJS.appendRight(9, ';');
    const resultJS = msJS.toString();
    const mapJS = msJS.generateMap();
    
    // 验证输出一致
    expect(resultZig).toBe(resultJS);
    
    // 对比 Source Map
    expect(mapZig.version).toBe(mapJS.version);
    expect(mapZig.mappings).toBe(mapJS.mappings);
  });

  it('对比测试: 多次 overwrite 应生成相同的 mappings', () => {
    const source = 'var x = 1 + 2';
    
    // Zig 版本
    const handleZig = addon.createMagicString(source);
    handles.push(handleZig);
    addon.overwrite(handleZig, 4, 5, 'a');
    addon.overwrite(handleZig, 8, 9, '10');
    addon.overwrite(handleZig, 12, 13, '20');
    const resultZig = addon.toString(handleZig);
    const mapZig = JSON.parse(addon.generateMap(handleZig));
    
    // JS 版本
    const msJS = new MagicStringJS(source);
    msJS.overwrite(4, 5, 'a');
    msJS.overwrite(8, 9, '10');
    msJS.overwrite(12, 13, '20');
    const resultJS = msJS.toString();
    const mapJS = msJS.generateMap();
    
    // 验证输出一致
    expect(resultZig).toBe(resultJS);
    
    // 对比 Source Map
    expect(mapZig.version).toBe(mapJS.version);
    expect(mapZig.mappings).toBe(mapJS.mappings);
  });
});

