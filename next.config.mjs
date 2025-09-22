/** @type {import('next').NextConfig} */
// In Docker, the backend is reachable from the frontend container via the service name
const backendBase = process.env.NEXT_PUBLIC_API_BASE_URL || "http://backend:8000"

const nextConfig = {
  eslint: {
    ignoreDuringBuilds: true,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
  },
  output: "standalone",
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: `${backendBase}/api/:path*`,
      },
    ]
  },
}

export default nextConfig
