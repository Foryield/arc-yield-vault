/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Static export: the page is fully client-side, with no server rendering.
  // It produces an `out/` folder deployable as a static site (Render).
  output: "export",
  images: { unoptimized: true },
};

export default nextConfig;
