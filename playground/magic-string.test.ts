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

