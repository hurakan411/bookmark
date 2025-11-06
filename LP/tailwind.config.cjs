const defaultTheme = require("tailwindcss/defaultTheme");

/** @type {import("tailwindcss").Config} */
module.exports = {
  content: [
    "./src/**/*.{astro,html,js,jsx,ts,tsx,md,mdx,svelte,vue}"
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ["Inter", ...defaultTheme.fontFamily.sans],
        display: ["SF Pro Display", ...defaultTheme.fontFamily.sans]
      },
      colors: {
        primary: {
          50: "#f3f5ff",
          100: "#e5e9ff",
          200: "#c2c6ff",
          300: "#9ea3ff",
          400: "#6c74ff",
          500: "#454dff",
          600: "#2d34d5",
          700: "#1f249c",
          800: "#14176a",
          900: "#0a0d40"
        },
        accent: {
          100: "#ffeffa",
          200: "#ffcce9",
          300: "#ff99d3",
          400: "#ff66bc",
          500: "#ff2fa2"
        }
      },
      boxShadow: {
        glow: "0 25px 50px -12px rgba(108, 116, 255, 0.45)",
        card: "0 20px 45px -20px rgba(20, 23, 106, 0.55)"
      },
      backgroundImage: {
        "grid-light": "linear-gradient(rgba(69, 77, 255, 0.08) 1px, transparent 1px), linear-gradient(90deg, rgba(69, 77, 255, 0.08) 1px, transparent 1px)",
        "radial-primary": "radial-gradient(circle at top, rgba(108, 116, 255, 0.35), transparent 60%)"
      }
    }
  },
  plugins: []
};
