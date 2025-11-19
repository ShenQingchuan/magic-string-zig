import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import os from 'os';

const require = createRequire(import.meta.url);
const __dirname = dirname(fileURLToPath(import.meta.url));

const platform = os.platform();
const arch = os.arch();

// 根据平台和架构加载对应的 .node 文件
const addonPath = join(__dirname, `zig-out/lib/magic-string.${platform}-${arch}.node`);

// 定义 N-API 接口类型
interface MagicStringAddon {
  createMagicString(source: string): number;
  toString(handle: number): string;
  appendLeft(handle: number, index: number, content: string): void;
  appendRight(handle: number, index: number, content: string): void;
  overwrite(handle: number, start: number, end: number, content: string): void;
  generateMap(handle: number): string;
  destroy(handle: number): void;
}

let addon: MagicStringAddon;
try {
  addon = require(addonPath);
} catch (e) {
  console.error(`Failed to load addon from ${addonPath}`);
  throw e;
}

// 使用 FinalizationRegistry 自动管理内存
// 当 MagicString 实例被垃圾回收时，自动调用 addon.destroy 释放 Zig 端内存
const registry = new FinalizationRegistry((handle: number) => {
  addon.destroy(handle);
});

export interface SourceMapOptions {
  source?: string;
  file?: string;
  includeContent?: boolean;
  hires?: boolean;
}

export class MagicString {
  private handle: number;
  private original: string;

  constructor(source: string) {
    this.original = source;
    this.handle = addon.createMagicString(source);
    // 注册到 FinalizationRegistry
    registry.register(this, this.handle);
  }

  toString(): string {
    return addon.toString(this.handle);
  }

  appendLeft(index: number, content: string): this {
    addon.appendLeft(this.handle, index, content);
    return this;
  }

  appendRight(index: number, content: string): this {
    addon.appendRight(this.handle, index, content);
    return this;
  }

  overwrite(start: number, end: number, content: string): this {
    addon.overwrite(this.handle, start, end, content);
    return this;
  }

  generateMap(options?: SourceMapOptions): any {
    const mapJson = addon.generateMap(this.handle);
    const map = JSON.parse(mapJson);
    
    // 补全 options 中的字段
    if (options?.source) {
      map.sources = [options.source];
    }
    if (options?.file) {
      map.file = options.file;
    }
    if (options?.includeContent) {
        map.sourcesContent = [this.original];
    }

    return map;
  }
  
  // 手动销毁方法（可选，如果用户想显式释放）
  // 调用后该实例不应再被使用
  destroy(): void {
    registry.unregister(this);
    addon.destroy(this.handle);
    // 防止重复调用导致崩溃，可以将 handle 设为无效值
    (this as any).handle = 0; 
  }
}

