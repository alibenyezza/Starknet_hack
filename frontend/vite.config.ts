import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3000,
    proxy: {
      '/rpc': {
        target: 'https://api.cartridge.gg',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/rpc/, '/x/starknet/sepolia'),
      },
      '/coingecko': {
        target: 'https://api.coingecko.com',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/coingecko/, ''),
      },
    },
  },
})