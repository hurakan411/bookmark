import { defineConfig } from "astro/config";
import tailwind from "@astrojs/tailwind";

export default defineConfig({
  integrations: [
    tailwind({
      applyBaseStyles: false
    })
  ],
  // 画像最適化
  image: {
    service: {
      entrypoint: 'astro/assets/services/sharp'
    }
  },
  // ビルド最適化
  vite: {
    build: {
      cssMinify: true,
      minify: 'terser'
    }
  }
});
