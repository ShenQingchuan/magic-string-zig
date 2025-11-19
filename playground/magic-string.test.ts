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

