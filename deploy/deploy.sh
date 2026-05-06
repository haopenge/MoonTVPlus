#!/bin/bash

# 脚本所在目录
cd "$(dirname "$0")" || exit

# 如果没有传入参数，则使用当前时间作为默认 tag
if [ -z "$1" ]; then
  TAG=2026-03-02-18-13-32
  echo "未提供 tag，使用默认 tag: $TAG"
else
  TAG=$1
  echo "使用提供的 tag: $TAG"
fi

# 将 TAG 导出为环境变量，以便 docker-compose 使用
export tag=$TAG

echo "----------------------------------------"
echo "正在拉取最新镜像..."
docker-compose pull

echo "----------------------------------------"
echo "正在重新创建服务..."
docker-compose up -d --remove-orphans

echo "----------------------------------------"
echo "部署完成！"

