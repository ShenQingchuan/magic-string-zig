import { describe, it, expect } from 'vitest';
import { MagicString } from '../index';
import { createRequire } from 'module';

// 导入原版 magic-string 用于对比测试
const require = createRequire(import.meta.url);
const MagicStringJS = require('magic-string');

describe('MagicString Class Wrapper', () => {
  
  describe('Phase 1: 基础功能', () => {
    it('应该正确初始化并返回原始字符串', () => {
      const s = new MagicString("Hello, World!");
      expect(s.toString()).toBe("Hello, World!");
    });

    it('应该处理空字符串', () => {
      const s = new MagicString("");
      expect(s.toString()).toBe("");
    });

    it('应该正确处理特殊字符和 Unicode', () => {
      const source = "你好，世界！🚀\n\t\r";
      const s = new MagicString(source);
      expect(s.toString()).toBe(source);
    });

    it('应该处理较长的字符串', () => {
      const source = "a".repeat(1000);
      const s = new MagicString(source);
      expect(s.toString()).toBe(source);
    });
  });

  describe('Phase 2: appendLeft / appendRight', () => {
    it('应该在开头 appendLeft', () => {
      const s = new MagicString("world");
      s.appendLeft(0, "Hello ");
      expect(s.toString()).toBe("Hello world");
    });

    it('应该在末尾 appendRight', () => {
      const s = new MagicString("Hello");
      s.appendRight(5, " world");
      expect(s.toString()).toBe("Hello world");
    });

    it('应该在中间 appendLeft', () => {
      const s = new MagicString("ac");
      s.appendLeft(1, "b");
      expect(s.toString()).toBe("abc");
    });

    it('应该在中间 appendRight', () => {
      const s = new MagicString("ac");
      s.appendRight(1, "b");
      expect(s.toString()).toBe("abc");
    });

    it('应该支持多次 appendLeft', () => {
      const s = new MagicString("world");
      s.appendLeft(0, "Hello ");
      s.appendLeft(0, ">>> ");
      expect(s.toString()).toBe(">>> Hello world");
    });

    it('应该支持多次 appendRight', () => {
      const s = new MagicString("Hello");
      s.appendRight(5, " world");
      s.appendRight(5, " <<<");
      expect(s.toString()).toBe("Hello <<< world");
    });

    it('应该支持混合使用 appendLeft 和 appendRight', () => {
      const s = new MagicString("var x = 1");
      s.appendLeft(0, "// Comment\n");
      s.appendRight(9, ";");
      expect(s.toString()).toBe("// Comment\nvar x = 1;");
    });

    it('支持链式调用', () => {
      const s = new MagicString("var x = 1");
      s.appendLeft(0, "// Comment\n")
       .appendRight(9, ";");
      expect(s.toString()).toBe("// Comment\nvar x = 1;");
    });
  });

  describe('Phase 3: overwrite', () => {
    it('应该能替换整个字符串', () => {
      const s = new MagicString("problems = 99");
      s.overwrite(0, 8, "answer");
      expect(s.toString()).toBe("answer = 99");
    });

    it('应该能替换字符串的一部分', () => {
      const s = new MagicString("var x = 1");
      s.overwrite(4, 5, "answer");
      expect(s.toString()).toBe("var answer = 1");
    });

    it('应该能替换末尾的字符', () => {
      const s = new MagicString("var x = 99");
      s.overwrite(8, 10, "42");
      expect(s.toString()).toBe("var x = 42");
    });

    it('应该能用空字符串替换（删除效果）', () => {
      const s = new MagicString("var x = 1");
      s.overwrite(0, 4, "");
      expect(s.toString()).toBe("x = 1");
    });

    it('应该保留 overwrite 前的 appendLeft/Right', () => {
      const s = new MagicString("var x = 1");
      s.appendLeft(0, "// Start\n");
      s.appendRight(9, ";");
      s.overwrite(4, 5, "answer");
      expect(s.toString()).toBe("// Start\nvar answer = 1;");
    });

    it('应该能多次 overwrite 不同的位置', () => {
      const s = new MagicString("var x = 1 + 2");
      s.overwrite(4, 5, "a");
      s.overwrite(8, 9, "10");
      s.overwrite(12, 13, "20");
      expect(s.toString()).toBe("var a = 10 + 20");
    });

    it('应该能用更长的字符串替换', () => {
      const s = new MagicString("x = 1");
      s.overwrite(0, 1, "answer");
      expect(s.toString()).toBe("answer = 1");
    });

    it('应该能在 overwrite 后的位置继续 appendLeft', () => {
      const s = new MagicString("abc");
      s.overwrite(1, 2, "XXX");
      expect(s.toString()).toBe("aXXXc");
      
      s.appendLeft(1, ">>>");
      expect(s.toString()).toBe("a>>>XXXc");
    });
  
    it('应该能在 overwrite 后的位置继续 appendRight', () => {
      const s = new MagicString("abc");
      s.overwrite(1, 2, "XXX");
      expect(s.toString()).toBe("aXXXc");
      
      s.appendRight(1, "<<<");
      expect(s.toString()).toBe("a<<<XXXc");
    });
  
    it('应该能在 overwrite 范围内的多个位置 append', () => {
      const s = new MagicString("abcdef");
      s.overwrite(2, 4, "XX");
      expect(s.toString()).toBe("abXXef");
      
      s.appendLeft(2, "[");
      s.appendRight(4, "]");
      expect(s.toString()).toBe("ab[XX]ef");
    });
  });

  describe('Phase 4: Source Map', () => {
    it('应该生成基础的 Source Map', () => {
      const s = new MagicString("abc");
      const map = s.generateMap({ source: 'source.js' });

      expect(map.version).toBe(3);
      expect(map.sources).toEqual(['source.js']);
      expect(map.names).toEqual([]);
      expect(typeof map.mappings).toBe('string');
      expect(map.mappings.length).toBeGreaterThan(0);
    });

    it('应该支持 includeContent 选项', () => {
      const s = new MagicString("abc");
      const map = s.generateMap({ source: 'source.js', includeContent: true });

      expect(map.sourcesContent).toEqual(["abc"]);
    });

    it('应该为 overwrite 操作生成正确的映射', () => {
      const s = new MagicString("var x = 1");
      s.overwrite(4, 5, "answer");
      expect(s.toString()).toBe("var answer = 1");

      const map = s.generateMap();
      expect(map.version).toBe(3);
      expect(map.mappings).toBeTruthy();
    });

    it('应该为 appendLeft 操作生成映射', () => {
      const s = new MagicString("hello");
      s.appendLeft(0, ">>> ");
      expect(s.toString()).toBe(">>> hello");

      const map = s.generateMap();
      expect(map.version).toBe(3);
      expect(map.mappings).toBeTruthy();
    });
  });

  describe('对比测试: 对比原版 magic-string', () => {
    it('对比测试: 简单字符串应生成相同的 mappings', () => {
      const source = 'abc';
      
      const sZig = new MagicString(source);
      const mapZig = sZig.generateMap({ source: 'source.js', includeContent: true });
      
      const sJS = new MagicStringJS(source);
      const mapJS = sJS.generateMap({ source: 'source.js', includeContent: true });
      
      expect(mapZig.version).toBe(mapJS.version);
      expect(mapZig.sources).toEqual(mapJS.sources);
      expect(mapZig.names).toEqual(mapJS.names);
      expect(mapZig.mappings).toBe(mapJS.mappings);
      expect(mapZig.sourcesContent).toEqual(mapJS.sourcesContent);
    });

    it('对比测试: appendLeft 应生成相同的 mappings', () => {
      const source = 'hello';
      
      const sZig = new MagicString(source);
      sZig.appendLeft(0, '>>> ');
      const resultZig = sZig.toString();
      const mapZig = sZig.generateMap({ source: 'source.js' });
      
      const sJS = new MagicStringJS(source);
      sJS.appendLeft(0, '>>> ');
      const resultJS = sJS.toString();
      const mapJS = sJS.generateMap({ source: 'source.js' });
      
      expect(resultZig).toBe(resultJS);
      expect(mapZig.mappings).toBe(mapJS.mappings);
    });

    it('对比测试: appendRight 应生成相同的 mappings', () => {
      const source = 'hello';
      
      const sZig = new MagicString(source);
      sZig.appendRight(5, ' <<<');
      const resultZig = sZig.toString();
      const mapZig = sZig.generateMap({ source: 'source.js' });
      
      const sJS = new MagicStringJS(source);
      sJS.appendRight(5, ' <<<');
      const resultJS = sJS.toString();
      const mapJS = sJS.generateMap({ source: 'source.js' });
      
      expect(resultZig).toBe(resultJS);
      expect(mapZig.mappings).toBe(mapJS.mappings);
    });

    it('对比测试: overwrite 应生成相同的 mappings', () => {
      const source = 'var x = 1';
      
      const sZig = new MagicString(source);
      sZig.overwrite(4, 5, 'answer');
      const resultZig = sZig.toString();
      const mapZig = sZig.generateMap({ source: 'source.js' });
      
      const sJS = new MagicStringJS(source);
      sJS.overwrite(4, 5, 'answer');
      const resultJS = sJS.toString();
      const mapJS = sJS.generateMap({ source: 'source.js' });
      
      expect(resultZig).toBe(resultJS);
      expect(mapZig.mappings).toBe(mapJS.mappings);
    });

    it('对比测试: 复杂操作组合应生成相同的 mappings', () => {
      const source = 'var x = 1';
      
      const sZig = new MagicString(source);
      sZig.appendLeft(0, '// Comment\n');
      sZig.overwrite(4, 5, 'answer');
      sZig.appendRight(9, ';');
      const resultZig = sZig.toString();
      const mapZig = sZig.generateMap({ source: 'source.js' });
      
      const sJS = new MagicStringJS(source);
      sJS.appendLeft(0, '// Comment\n');
      sJS.overwrite(4, 5, 'answer');
      sJS.appendRight(9, ';');
      const resultJS = sJS.toString();
      const mapJS = sJS.generateMap({ source: 'source.js' });
      
      expect(resultZig).toBe(resultJS);
      expect(mapZig.mappings).toBe(mapJS.mappings);
    });

    it('对比测试: 多次 overwrite 应生成相同的 mappings', () => {
      const source = 'var x = 1 + 2';
      
      const sZig = new MagicString(source);
      sZig.overwrite(4, 5, 'a');
      sZig.overwrite(8, 9, '10');
      sZig.overwrite(12, 13, '20');
      const resultZig = sZig.toString();
      const mapZig = sZig.generateMap({ source: 'source.js' });
      
      const sJS = new MagicStringJS(source);
      sJS.overwrite(4, 5, 'a');
      sJS.overwrite(8, 9, '10');
      sJS.overwrite(12, 13, '20');
      const resultJS = sJS.toString();
      const mapJS = sJS.generateMap({ source: 'source.js' });
      
      expect(resultZig).toBe(resultJS);
      expect(mapZig.mappings).toBe(mapJS.mappings);
    });
  });
});
