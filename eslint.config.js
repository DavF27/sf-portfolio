const { defineConfig } = require("eslint/config");
const eslintJs = require("@eslint/js");
const jestPlugin = require("eslint-plugin-jest");
const lwcConfig = require("@salesforce/eslint-config-lwc/recommended");
const globals = require("globals");

module.exports = defineConfig([
  {
    files: ["**/lwc/**/*.js"],
    extends: [lwcConfig]
  },
  {
    files: ["**/lwc/**/*.test.js"],
    extends: [lwcConfig],
    rules: {
      "@lwc/lwc/no-unexpected-wire-adapter-usages": "off"
    },
    languageOptions: {
      globals: { ...globals.node }
    }
  },
  {
    files: ["jest-mocks/**/*.js"],
    languageOptions: {
      sourceType: "module",
      ecmaVersion: "latest",
      globals: {
        ...globals.node,
        ...globals.es2021,
        ...jestPlugin.environments.globals.globals
      }
    },
    plugins: { eslintJs },
    extends: ["eslintJs/recommended"]
  },
  {
    files: ["scripts/**/*.js", "e2e/**/*.js", "*.config.js"],
    languageOptions: {
      sourceType: "commonjs",
      ecmaVersion: "latest",
      globals: { ...globals.node }
    },
    plugins: { eslintJs },
    extends: ["eslintJs/recommended"]
  }
]);
