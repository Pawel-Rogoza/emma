import {defineConfig} from 'vite';
import {fileURLToPath} from 'node:url';
export default defineConfig({build:{rollupOptions:{input:{home:fileURLToPath(new URL('./index.html',import.meta.url)),model:fileURLToPath(new URL('./model.html',import.meta.url))}}}});
