import MagicString from 'magic-string';

const BENCH_ITERATIONS = 10000;

console.log(`运行基准测试 (迭代次数: ${BENCH_ITERATIONS})`);
console.log('========================================');

// 基准测试 1: 初始化和 toString
function benchmarkInitToString() {
  const source = 'Hello, World! This is a test string for benchmarking.';
  const start = performance.now();

  for (let i = 0; i < BENCH_ITERATIONS; i++) {
    const ms = new MagicString(source);
    ms.toString();
  }

  const elapsed = performance.now() - start;
  console.log(`基准测试 1 - 初始化和 toString: ${elapsed.toFixed(2)} ms (${(elapsed * 1000 / BENCH_ITERATIONS).toFixed(2)} μs/次)`);
}

// 基准测试 2: appendLeft 操作
function benchmarkAppendLeft() {
  const source = 'world';
  const start = performance.now();

  for (let i = 0; i < BENCH_ITERATIONS; i++) {
    const ms = new MagicString(source);
    ms.appendLeft(0, 'Hello ');
    ms.appendLeft(0, '>>> ');
    ms.toString();
  }

  const elapsed = performance.now() - start;
  console.log(`基准测试 2 - appendLeft 操作: ${elapsed.toFixed(2)} ms (${(elapsed * 1000 / BENCH_ITERATIONS).toFixed(2)} μs/次)`);
}

// 基准测试 3: appendRight 操作
function benchmarkAppendRight() {
  const source = 'Hello';
  const start = performance.now();

  for (let i = 0; i < BENCH_ITERATIONS; i++) {
    const ms = new MagicString(source);
    ms.appendRight(5, ' world');
    ms.appendRight(5, ' <<<');
    ms.toString();
  }

  const elapsed = performance.now() - start;
  console.log(`基准测试 3 - appendRight 操作: ${elapsed.toFixed(2)} ms (${(elapsed * 1000 / BENCH_ITERATIONS).toFixed(2)} μs/次)`);
}

// 基准测试 4: overwrite 操作
function benchmarkOverwrite() {
  const source = 'var x = 1 + 2';
  const start = performance.now();

  for (let i = 0; i < BENCH_ITERATIONS; i++) {
    const ms = new MagicString(source);
    ms.overwrite(4, 5, 'a');
    ms.overwrite(8, 9, '10');
    ms.overwrite(12, 13, '20');
    ms.toString();
  }

  const elapsed = performance.now() - start;
  console.log(`基准测试 4 - overwrite 操作: ${elapsed.toFixed(2)} ms (${(elapsed * 1000 / BENCH_ITERATIONS).toFixed(2)} μs/次)`);
}

// 基准测试 5: 复杂组合操作
function benchmarkComplex() {
  const source = 'var x = 1';
  const start = performance.now();

  for (let i = 0; i < BENCH_ITERATIONS; i++) {
    const ms = new MagicString(source);
    ms.appendLeft(0, '// Comment\n');
    ms.overwrite(4, 5, 'answer');
    ms.appendRight(9, ';');
    ms.toString();
  }

  const elapsed = performance.now() - start;
  console.log(`基准测试 5 - 复杂组合操作: ${elapsed.toFixed(2)} ms (${(elapsed * 1000 / BENCH_ITERATIONS).toFixed(2)} μs/次)`);
}

// 基准测试 6: Source Map 生成
function benchmarkSourceMap() {
  const source = 'var x = 1';
  const start = performance.now();

  for (let i = 0; i < BENCH_ITERATIONS; i++) {
    const ms = new MagicString(source);
    ms.appendLeft(0, '// Comment\n');
    ms.overwrite(4, 5, 'answer');
    ms.appendRight(9, ';');
    ms.generateMap({});
  }

  const elapsed = performance.now() - start;
  console.log(`基准测试 6 - Source Map 生成: ${elapsed.toFixed(2)} ms (${(elapsed * 1000 / BENCH_ITERATIONS).toFixed(2)} μs/次)`);
}

// 运行所有基准测试
benchmarkInitToString();
benchmarkAppendLeft();
benchmarkAppendRight();
benchmarkOverwrite();
benchmarkComplex();
benchmarkSourceMap();
