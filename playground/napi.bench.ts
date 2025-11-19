import { bench, describe } from 'vitest';
import { MagicString } from '../index';
import { createRequire } from 'module';

const require = createRequire(import.meta.url);
const MagicStringJS = require('magic-string');

describe('MagicString Performance', () => {
  const source = 'a'.repeat(100000); // 100KB

  describe('toString', () => {
    const sZig = new MagicString(source);
    const sJS = new MagicStringJS(source);
    
    bench('Zig: toString', () => {
      sZig.appendLeft(0, 'start');
      sZig.appendRight(100000, 'end');
      sZig.toString();
    });
    
    bench('JS: toString', () => {
      sJS.appendLeft(0, 'start');
      sJS.appendRight(100000, 'end');
      sJS.toString();
    });
  });
});
