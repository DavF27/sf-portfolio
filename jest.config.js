const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"],
  testPathIgnorePatterns: [
    "<rootDir>/node_modules/",
    "<rootDir>/e2e/",
    "<rootDir>/scripts/"
  ],
  moduleNameMapper: {
    "^lightning/empApi$": "<rootDir>/jest-mocks/lightning/empApi"
  },
  coverageThreshold: {
    global: { branches: 75, functions: 85, lines: 85, statements: 85 }
  }
};
