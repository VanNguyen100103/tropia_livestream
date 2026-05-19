'use strict';

module.exports = {
  testEnvironment: 'node',
  testMatch: ['**/tests/**/*.test.js'],
  collectCoverageFrom: [
    'src/services/**/*.js',
    'src/controllers/**/*.js',
    'src/middleware/auth.js',
  ],
  coverageReporters: ['text', 'lcov'],
  setupFiles: ['./tests/setup.js'],
  // Không timeout quá ngắn cho integration test
  testTimeout: 15000,
};
