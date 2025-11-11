#!/bin/sh

set -e  # 遇到错误立即退出，避免无效执行

PROGNAME="docker-setup.sh"

# 目录设置（使用绝对路径，避免相对路径问题）
ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPTS_DIR="${ROOT_DIR}/scripts"
TOOLS_DIR="${ROOT_DIR}/tools"
UBUNTU_DIR="${ROOT_DIR}/ubuntu"
FLIGHT_DIR="${ROOT_DIR}/flight"

start_docker_image()
{
    local compose_file="$1"
    local env_file="$2"
    local image_type_name="$3"

    echo "Starting docker image: $image_type_name"

    # 检查compose文件是否存在
    if [ ! -f "$compose_file" ]; then
        echo "Error: Compose file '$compose_file' not found."
        exit 1
    fi

    # 根据类型执行启动命令
    case "$image_type_name" in
        "ubuntu")
            docker-compose -f "$compose_file" up -d
            ;;
        "flight")
            # 检查env文件是否存在（flight依赖env文件）
            if [ ! -f "$env_file" ]; then
                echo "Error: Env file '$env_file' not found."
                exit 1
            fi
            docker-compose --env-file "$env_file" -f "$compose_file" up -d
            ;;
    esac
}

# 停止 Docker 镜像
stop_docker_image()
{    
    local compose_file="$1"
    local env_file="$2"
    local image_type_name="$3"

    echo "Stopping docker image: $image_type_name"

    # 检查 compose 文件是否存在
    if [ ! -f "$compose_file" ]; then
        echo "Error: Compose file '$compose_file' not found."
        exit 1
    fi

    case "$image_type_name" in
        "ubuntu")
            docker-compose -f "$compose_file" down
            ;;
        "flight")
            # 停止时也检查 env 文件（保持一致性）
            if [ ! -f "$env_file" ]; then
                echo "Error: Env file '$env_file' not found."
                exit 1
            fi
            docker-compose --env-file "$env_file" -f "$compose_file" down
            ;;
    esac
}

usage() {

    echo "Usage: sudo ./$PROGNAME -t <image-type> -c <start|stop> [OPTIONS]

    功能: 启动或停止指定类型的Docker镜像

    必填参数：
    -t <image-type>   镜像类型, 支持:ubuntu、flight
    -c <start|stop>   操作命令: start(启动)、stop(停止)

    可选参数：
    -e <env-file>     环境变量文件路径(flight 类型必填, ubuntu 可选)
    -v <version>      Ubuntu 版本, 支持: 1804、2004、2204(默认使用通用配置)
    -h                显示帮助信息

    示例：
    启动 ubuntu 20.04 镜像：
        sudo ./$PROGNAME -t ubuntu -v 2004 -c start
    停止 flight 镜像(指定 env 文件): 
        sudo ./$PROGNAME -t flight -e ./flight.env -c stop
    "
}

# parse the parameters
OLD_OPTIND=$OPTIND
while getopts "c:e:t:v:h" setup_flag
do
    case $setup_flag in
        c) COMMAND="$OPTARG" ;;
        # 要配置的环境变量文件
        e) ENV_FILE="$OPTARG" ;;
        # 要配置进 docker 组的用户名
        t) IMAGE_TYPE_NAME="$OPTARG" ;;
        # 要配置的镜像版本
        v) IMAGE_TYPE_VERSION="$OPTARG" ;;
        ?) usage; exit 0 ;;
        h) usage; exit 1 ;;
    esac
done
OPTIND=$OLD_OPTIND

# 检查必填参数
if [ -z "$IMAGE_TYPE_NAME" ] || [ -z "$COMMAND" ]; then
    echo "Error: Missing required parameters (-t and -c are required)."
    usage
    exit 1
fi

# 检查命令是否为start/stop
if [ "$COMMAND" != "start" ] && [ "$COMMAND" != "stop" ]; then
    echo "Error: Invalid command '$COMMAND'. Must be 'start' or 'stop'."
    usage
    exit 1
fi

# 检查镜像类型是否合法
if [ "$IMAGE_TYPE_NAME" != "ubuntu" ] && [ "$IMAGE_TYPE_NAME" != "flight" ]; then
    echo "Error: Invalid image type '$IMAGE_TYPE_NAME'. Supported: ubuntu, flight."
    usage
    exit 1
fi

# # 确定Docker Compose文件和环境文件路径
unset DOCKER_COMPOSE_FILE
unset DOCKER_ENV_FILE

case "$IMAGE_TYPE_NAME" in
    "ubuntu")
        # 选择 Ubuntu 版本对应的 compose 文件
        case "$IMAGE_TYPE_VERSION" in
            "1804")
                DOCKER_COMPOSE_FILE="${UBUNTU_DIR}/docker-compose-ubuntu1804.yml"
                ;;
            "2004")
                DOCKER_COMPOSE_FILE="${UBUNTU_DIR}/docker-compose-ubuntu2004.yml"
                ;;
            "2204")
                DOCKER_COMPOSE_FILE="${UBUNTU_DIR}/docker-compose-ubuntu2204.yml"
                ;;
            *)
                # 未指定版本或不支持的版本，使用通用配置
                DOCKER_COMPOSE_FILE="${UBUNTU_DIR}/docker-compose-ubuntu.yml"
                ;;
        esac
        # Ubuntu 可选 env 文件（若指定则使用，否则忽略）
        DOCKER_ENV_FILE="${ENV_FILE:-}"
        ;;
    "flight")
        # Flight 必须指定 env 文件（若未指定则报错）
        if [ -z "$ENV_FILE" ]; then
            echo "Error: -e <env-file> is required for 'flight' image type."
            usage
            exit 1
        fi
        DOCKER_ENV_FILE="${FLIGHT_DIR}/${ENV_FILE}"
        DOCKER_COMPOSE_FILE="${FLIGHT_DIR}/docker-compose-flight.yml"
        ;;
esac

case "$COMMAND" in
    "start")
        start_docker_image "${DOCKER_COMPOSE_FILE} ${DOCKER_ENV_FILE} ${IMAGE_TYPE_NAME}" 
        ;;
    "stop")
        stop_docker_image "${DOCKER_COMPOSE_FILE} ${DOCKER_ENV_FILE} ${IMAGE_TYPE_NAME}"
        ;;
esac

echo "Operation '$COMMAND' for '$IMAGE_TYPE_NAME' completed."
