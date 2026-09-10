import js from "@eslint/js";
import tseslint from "typescript-eslint";
import eslintConfigPrettier from "eslint-config-prettier";
import globals from "globals";

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["extension/**/*.ts"],
    languageOptions: {
      globals: {
        ...globals.node,
      },
    },
  },
  // disables any ESLint rules that conflict with Prettier (must be last)
  eslintConfigPrettier,
);
