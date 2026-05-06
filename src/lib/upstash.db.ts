/* eslint-disable no-console, @typescript-eslint/no-explicit-any, @typescript-eslint/no-non-null-assertion */

// 检查是否在 Edge Runtime 环境中
const isEdgeRuntime =
  typeof process === 'undefined' || typeof process.cwd !== 'function';

// 根据环境选择不同的 Upstash Redis 导入方式
let Redis: any;
if (isEdgeRuntime) {
  // Edge Runtime 环境中，使用 Cloudflare 兼容版本
  Redis = require('@upstash/redis/cloudflare').Redis;
} else {
  // 普通 Node.js 环境中，使用标准版本
  Redis = require('@upstash/redis').Redis;
}

import { UpstashRedisAdapter } from './redis-adapter';
import { BaseRedisStorage } from './redis-base.db';

// 添加Upstash Redis操作重试包装器
async function withRetry<T>(
  operation: () => Promise<T>,
  maxRetries = 3
): Promise<T> {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await operation();
    } catch (err: any) {
      const isLastAttempt = i === maxRetries - 1;
      const isConnectionError =
        err.message?.includes('Connection') ||
        err.message?.includes('ECONNREFUSED') ||
        err.message?.includes('ENOTFOUND') ||
        err.code === 'ECONNRESET' ||
        err.code === 'EPIPE' ||
        err.name === 'UpstashError';

      if (isConnectionError && !isLastAttempt) {
        console.log(
          `Upstash Redis operation failed, retrying... (${i + 1}/${maxRetries})`
        );
        console.error('Error:', err.message);

        // 等待一段时间后重试
        await new Promise((resolve) => setTimeout(resolve, 1000 * (i + 1)));
        continue;
      }

      throw err;
    }
  }

  throw new Error('Max retries exceeded');
}

export class UpstashRedisStorage extends BaseRedisStorage {
  constructor() {
    const client = getUpstashRedisClient();
    const adapter = new UpstashRedisAdapter(client);
    super(adapter, withRetry);
  }
}

// 单例 Upstash Redis 客户端
function getUpstashRedisClient(): any {
  const globalKey = Symbol.for('__MOONTV_UPSTASH_REDIS_CLIENT__');
  let client: any | undefined = (global as any)[globalKey];

  if (!client) {
    const upstashUrl = process.env.UPSTASH_URL;
    const upstashToken = process.env.UPSTASH_TOKEN;

    if (!upstashUrl || !upstashToken) {
      throw new Error(
        'UPSTASH_URL and UPSTASH_TOKEN env variables must be set'
      );
    }

    // 创建 Upstash Redis 客户端
    client = new Redis({
      url: upstashUrl,
      token: upstashToken,
      // 可选配置
      retry: {
        retries: 3,
        backoff: (retryCount: number) =>
          Math.min(1000 * Math.pow(2, retryCount), 30000),
      },
    });

    console.log('Upstash Redis client created successfully');

    (global as any)[globalKey] = client;
  }

  return client;
}
