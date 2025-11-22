import standard from 'eslint-config-standard'
import globals from 'globals'

// eslint-config-standard may export a function or array
const standardConfig = typeof standard === 'function' ? standard() : standard
const standardArray = Array.isArray(standardConfig) ? standardConfig : [standardConfig]

export default [
  // Ignore patterns (matching .gitignore)
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
  // Base configuration for all files
  ...standardArray,
  {
    languageOptions: {
      globals: {
        ...globals.node
      }
    },
    rules: {
      'one-var': 'off',
      'prefer-const': 'off',
      'no-extra-parens': 'off',
      'no-unused-expressions': 'warn',
      'import/no-extraneous-dependencies': 'error',
      'n/no-callback-literal': 'off', // eslint-plugin-n replaces eslint-plugin-node
      'promise/param-names': 'off',
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
      ]
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

