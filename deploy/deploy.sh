#!/bin/bash

# 脚本所在目录
cd "$(dirname "$0")" || exit

# 创建 log 目录
mkdir -p log

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

# 日志文件路径
LOG_FILE="log/deploy-$(date +"%Y-%m-%d-%H-%M-%S").log"

echo "----------------------------------------"
echo "正在拉取最新镜像..."
docker-compose pull 2>&1 | tee -a "$LOG_FILE"

echo "----------------------------------------"
echo "正在重新创建服务..."
docker-compose up -d --remove-orphans 2>&1 | tee -a "$LOG_FILE"

echo "----------------------------------------"
echo "正在查看服务状态..."
docker-compose ps 2>&1 | tee -a "$LOG_FILE"

echo "----------------------------------------"
echo "正在查看服务日志..."
docker-compose logs --tail=50 2>&1 | tee -a "$LOG_FILE"

echo "----------------------------------------"
echo "部署完成！"
echo "日志已保存到: $LOG_FILE"

