import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: ['**/node_modules/**', 'apps/mobile/**', '**/.wrangler/**'],
  },
  ...tseslint.configs.recommended,
);
