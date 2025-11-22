import js from '@eslint/js'
import pluginImport from 'eslint-plugin-import'
import globals from 'globals'

export default [
  // Global ignore patterns (matching .gitignore)
  {
    ignores: [
      '**/node_modules/**',
      '**/dist/**',
      '**/build/**',
      '**/coverage/**',
      '**/.nyc_output/**',
      '**/.local-chromium/**',
      '**/.DS_Store',
      '**/.releases/**',
      '**/.secrets/**',
      '**/result/**',
      '**/packs/**',
      'packages/logger/test/client.js',
      'packages/sdk-utils/test/client.js'
    ]
  },

  // ESLint recommended rules
  js.configs.recommended,

  // Root-level rules and language options for all source files
  {
    files: ['**/*.js', '**/*.mjs'],
    languageOptions: {
      globals: {
        ...globals.node
      }
    },
    plugins: {
      import: pluginImport
    },
    rules: {
      // Core ESLint rules (matching previous standard-style preferences)
      'one-var': 'off',
      'prefer-const': 'off',
      'no-extra-parens': 'off',
      'no-unused-expressions': 'warn',
      semi: ['error', 'always'],
      'multiline-ternary': 'off',
      'yield-star-spacing': ['error', 'after'],
      'generator-star-spacing': [
        'error',
        {
          before: false,
          after: false,
          named: 'after',
          method: 'before'
        }
      ],
      'space-before-function-paren': [
        'error',
        {
          anonymous: 'never',
          asyncArrow: 'always',
          named: 'never'
        }
      ],
      // Import plugin rules (only one we actually use)
      'import/no-extraneous-dependencies': 'error'
    }
  },

  // Test directory overrides - disable import/no-extraneous-dependencies
  {
    files: ['**/test/**/*.js', '**/test/**/*.mjs'],
    rules: {
      'import/no-extraneous-dependencies': 'off'
    }
  },

  // Additional test overrides for packages that had jasmine env (legacy, but keeping for compatibility)
  {
    files: [
      'packages/core/test/**/*.js',
      'packages/client/test/**/*.js',
      'packages/dom/test/**/*.js'
    ],
    rules: {
      'no-return-assign': 'off',
      'no-sequences': 'off'
    }
  }
]

