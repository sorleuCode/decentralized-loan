import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  // server: {
  //   proxy: {
  //     '/rpc': {
  //       target: 'https://devnet.dplabs-internal.com',
  //       changeOrigin: true,
  //       secure: false,
  //       rewrite: (path) => path.replace(/^\/rpc/, ''),
  //     },
  //   },
  // },
})
