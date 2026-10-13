#!/usr/bin/env bash
# 在 init 容器中执行：准备持久化目录，仅首次创建 CLIProxyAPI 的 config.yaml。
# provider、客户端 API Key 和其他运行设置由 Web 页面写入配置文件。
set -euo pipefail
umask 077

# /data 对应项目的 DATA_ROOT；配置目录同时挂载为业务容器的 /config。
mkdir -p /data/cpa-manager-plus /data/cli-proxy-api/{config,auths}
chmod 700 /data /data/cpa-manager-plus /data/cli-proxy-api/config /data/cli-proxy-api/auths

config_file=/data/cli-proxy-api/config/config.yaml
# 重复 up/start/restart 会再次执行 init，但不覆盖已有配置或 Web 页面修改。
# 空文件、目录或失效链接属于异常情况，明确报错而不是悄悄重置配置。
if [ -e "$config_file" ] || [ -L "$config_file" ]; then
  if [ ! -f "$config_file" ] || [ ! -s "$config_file" ]; then
    printf '已有 config.yaml 不是有效的非空文件，请检查配置路径。\n' >&2
    exit 1
  fi
  chmod 600 "$config_file"
  printf '已有 config.yaml，保留 Web 页面配置。\n'
  exit 0
fi

# 先写同目录临时文件，再用硬链接原子创建目标，避免半写文件和并发覆盖。
config_tmp=$(mktemp /data/cli-proxy-api/config/.config.XXXXXX)
trap 'rm -f -- "$config_tmp"' EXIT
cp -- /bootstrap/config.template.yaml "$config_tmp"
chmod 600 "$config_tmp"
ln -- "$config_tmp" "$config_file"
printf '首次运行，已创建默认 config.yaml，请在 Web 页面配置客户端 Key 和 provider。\n'
