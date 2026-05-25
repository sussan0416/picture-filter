import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: process.env.APP_ID!,
  appName: 'Picture Filter',
  webDir: 'www',
  server: {
    hostname: 'localhost',
    androidScheme: 'https',
  },
};

export default config;
