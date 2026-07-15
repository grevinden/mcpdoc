#!/bin/sh
set -e

CONFIG_YAML="/app/config.yaml"

# Всегда добавляем --yaml config.yaml, если его нет в аргументах
HAS_YAML=false
HAS_TRANSPORT=false
for arg in "$@"; do
    case "$arg" in
        --yaml=*|--yaml|-y) HAS_YAML=true ;;
        --transport=*) HAS_TRANSPORT=true ;;
    esac
done

# Если --yaml не передан — добавляем из CMD
if [ "$HAS_YAML" = false ] && [ -f "$CONFIG_YAML" ]; then
    set -- "--yaml" "$CONFIG_YAML" "$@"
fi

# Если --transport не передан — автовыбор
if [ "$HAS_TRANSPORT" = false ]; then
    if [ -p /dev/stdin ]; then
        set -- "$@" "--transport=stdio"
    else
        set -- "$@" "--transport=sse"
    fi
fi

exec mcpdoc "$@"
