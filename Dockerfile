# ---- 第 1 阶段：安装依赖 ----
FROM alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/node:20.16 AS deps

USER root
# 配置国内 npm 镜像源并全局安装 pnpm
RUN npm config set registry https://registry.npmmirror.com || npm config set registry https://registry.npmmirror.com
RUN npm config set strict-ssl false
RUN npm install -g pnpm
ENV PATH=/usr/local/bin:$PATH
RUN pnpm config set registry https://registry.npmmirror.com || pnpm config set registry https://registry.npmmirror.com
RUN pnpm config set strict-ssl false
WORKDIR /app
RUN chown node:node /app
USER node

# 仅复制依赖清单，提高构建缓存利用率
COPY package.json pnpm-lock.yaml ./

# 安装所有依赖（含 devDependencies，后续会裁剪）
RUN pnpm install --frozen-lockfile

# ---- 第 2 阶段：构建项目 ----
FROM alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/node:20.16 AS builder
USER root
RUN npm config set registry https://registry.npmmirror.com || npm config set registry https://registry.npmmirror.com
RUN npm config set strict-ssl false
RUN npm install -g pnpm
ENV PATH=/usr/local/bin:$PATH
RUN pnpm config set registry https://registry.npmmirror.com
WORKDIR /app
RUN chown node:node /app
USER node

# 复制依赖
COPY --from=deps /app/node_modules ./node_modules
# 复制全部源代码（排除 node_modules）
COPY --chown=node:node . .

# 在构建阶段也显式设置 DOCKER_ENV，
ENV DOCKER_ENV=true

# 生成生产构建
RUN pnpm run build

# 设置 pnpm 镜像源并提取生产依赖
RUN (pnpm config set registry https://registry.npmmirror.com || pnpm config set registry https://registry.npmmirror.com) && pnpm config set strict-ssl false && pnpm deploy --filter=. --prod --legacy /tmp/prod-deps

# ---- 第 3 阶段：生成运行时镜像 ----
FROM alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/node:20.16 AS runner

USER root
# 配置国内 npm 镜像源并安装 pnpm（修复阿里云效构建问题）
RUN npm config set registry https://registry.npmmirror.com || npm config set registry https://registry.npmmirror.com
RUN npm config set strict-ssl false
RUN npm install -g pnpm
ENV PATH=/usr/local/bin:$PATH

# 创建非 root 用户（阿里云 Linux 使用 groupadd/useradd）
RUN groupadd -g 1001 nodejs && useradd -u 1001 -g nodejs -s /bin/bash -m nextjs

WORKDIR /app
ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000
ENV DOCKER_ENV=true

# 从构建器中复制 standalone 输出
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
# 从构建器中复制 scripts 目录
COPY --from=builder --chown=nextjs:nodejs /app/scripts ./scripts
# 从构建器中复制 start.js
COPY --from=builder --chown=nextjs:nodejs /app/start.js ./start.js
# 从构建器中复制自定义 server.js（包含 Socket.IO 支持）
COPY --from=builder --chown=nextjs:nodejs /app/server.js ./server.js
# 从构建器中复制 public 和 .next/static 目录
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# 从构建器中复制生产依赖（包含 Socket.IO）
COPY --from=builder --chown=nextjs:nodejs /tmp/prod-deps/node_modules ./node_modules

# 切换到非特权用户
USER nextjs

EXPOSE 3000

# 使用自定义启动脚本，先预加载配置再启动服务器
CMD ["node", "start.js"]