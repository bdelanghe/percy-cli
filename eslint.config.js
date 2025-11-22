import js from '@eslint/js'
import pluginImport from 'eslint-plugin-import'
import tseslint from '@typescript-eslint/eslint-plugin'
import tsparser from '@typescript-eslint/parser'
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

  // Root-level rules and language options for JavaScript source files
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

  // TypeScript source files
  {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: {
      parser: tsparser,
      parserOptions: {
        ecmaVersion: 2020,
        sourceType: 'module',
        project: './tsconfig.base.json'
      },
      globals: {
        ...globals.node
      }
    },
    plugins: {
      '@typescript-eslint': tseslint,
      import: pluginImport
    },
    rules: {
      // TypeScript-specific rules
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/explicit-function-return-type': 'off',
      '@typescript-eslint/explicit-module-boundary-types': 'off',
      '@typescript-eslint/no-explicit-any': 'warn',
      // Core ESLint rules (matching previous standard-style preferences)
      'one-var': 'off',
      'prefer-const': 'off',
      'no-extra-parens': 'off',
      'no-unused-expressions': 'warn',
      semi: 'off',
      '@typescript-eslint/semi': ['error', 'always'],
      'multiline-ternary': 'off',
      'yield-star-spacing': 'off',
      '@typescript-eslint/yield-star-spacing': ['error', 'after'],
      'generator-star-spacing': 'off',
      '@typescript-eslint/generator-star-spacing': [
        'error',
        {
          before: false,
          after: false,
          named: 'after',
          method: 'before'
        }
      ],
      'space-before-function-paren': 'off',
      '@typescript-eslint/space-before-function-paren': [
        'error',
        {
          anonymous: 'never',
          asyncArrow: 'always',
          named: 'never'
        }
      ],
      // Import plugin rules
      'import/no-extraneous-dependencies': 'error'
    }
  },

  // Test directory overrides - disable import/no-extraneous-dependencies
  {
    files: ['**/test/**/*.js', '**/test/**/*.mjs', '**/test/**/*.ts'],
    rules: {
      'import/no-extraneous-dependencies': 'off'
    }
  },

  // Additional test overrides for packages that had jasmine env (legacy, but keeping for compatibility)
  {
    files: [
      'packages/core/test/**/*.js',
      'packages/core/test/**/*.ts',
      'packages/client/test/**/*.js',
      'packages/client/test/**/*.ts',
      'packages/dom/test/**/*.js',
      'packages/dom/test/**/*.ts'
    ],
    rules: {
      'no-return-assign': 'off',
      'no-sequences': 'off',
      '@typescript-eslint/no-return-assign': 'off',
      '@typescript-eslint/no-sequences': 'off'
    }
  }
]

