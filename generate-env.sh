#!/usr/bin/env bash
# 本机执行：仅创建项目的 .env，内容为部署管理凭据和两个镜像版本；不生成运行配置，也不调用 Docker。
# 命令失败、使用未定义变量或管道中任一命令失败时，立即停止。
set -euo pipefail

# 无论从哪个目录执行，都将 .env 写到本脚本所在的项目目录。
# 清空 CDPATH，避免用户的 shell 配置改变 cd 的结果或额外输出。
cd -- "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# 新文件默认只有当前用户可读写，防止生成密钥时短暂暴露权限。
umask 077

# 服务启动由用户单独执行 docker compose，本脚本不接收启动参数。
if [ "$#" -ne 0 ]; then
  printf '用法：./generate-env.sh（仅生成 .env，不接受 Compose 参数）。\n' >&2
  exit 1
fi

# 已有密钥可能关联数据库中的加密数据，不能通过重复执行重新生成。
# 即使 .env 是指向不存在文件的符号链接，也保留用户的路径设置。
if [ -e .env ] || [ -L .env ]; then
  printf '.env 已存在，保留原有配置。\n'
  exit 0
fi

# 先在同一目录写临时文件；成功或失败退出时都清理这个临时路径。
env_tmp=$(mktemp .env.XXXXXX)
trap 'rm -f -- "$env_tmp"' EXIT
# 从系统随机源读取 32 字节，转成 64 个十六进制字符。
random_hex() { od -An -N32 -tx1 /dev/urandom | tr -d ' \n'; }
# 不同用途使用独立随机值。数据加密密钥按 Manager 要求使用 Base64。
admin_key=$(random_hex)
management_key=$(random_hex)
data_key=$(head -c 32 /dev/urandom | base64 | tr -d '\n')
# 镜像版本随 .env 一并保存，升级时在此处（或生成后的 .env 中）明确修改。
cli_proxy_image='eceasy/cli-proxy-api:v8.0.48'
cpa_manager_image='seakee/cpa-manager-plus:1.14.10'
# .env 保存部署管理凭据和两个镜像版本；provider 和客户端 API Key 在 Web 页面配置。
{
  printf '# Manager 初始管理员登录密钥；修改变量不会重置已有管理员凭据。\n'
  printf 'CPA_MANAGER_ADMIN_KEY=cpamp_%s\n' "$admin_key"
  printf '# CLIProxyAPI 管理密钥，同时供其 MANAGEMENT_PASSWORD 和 Manager 使用。\n'
  printf 'CPA_MANAGEMENT_KEY=%s\n' "$management_key"
  printf '# Manager 数据加密密钥，32 字节 Base64 编码；已有数据时不要更换。\n'
  printf 'CPA_MANAGER_DATA_KEY=%s\n' "$data_key"
  printf '\n'
  printf '# CLIProxyAPI 和 init 使用的镜像版本；Compose 没有兜底版本，升级时改这里。\n'
  printf 'CLI_PROXY_IMAGE=%s\n' "$cli_proxy_image"
  printf '# CPA Manager Plus 使用的镜像版本；Compose 没有兜底版本，升级时改这里。\n'
  printf 'CPA_MANAGER_IMAGE=%s\n' "$cpa_manager_image"
} > "$env_tmp"
chmod 600 "$env_tmp"
# 用硬链接原子创建 .env：如果另一进程已经创建该文件，ln 会失败而不覆盖。
# 退出时 trap 只删除临时路径，.env 仍保留同一文件内容和 600 权限。
ln -- "$env_tmp" .env
printf '已生成 .env；密钥和镜像版本保存在该文件中，请勿提交。\n'
