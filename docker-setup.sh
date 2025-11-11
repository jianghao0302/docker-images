#!/bin/sh

set -e  # 遇到错误立即退出，避免无效执行

PROGNAME="docker-setup.sh"

# 目录设置（使用绝对路径，避免相对路径问题）
ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPTS_DIR="${ROOT_DIR}/scripts"
TOOLS_DIR="${ROOT_DIR}/tools"
UBUNTU_DIR="${ROOT_DIR}/ubuntu"
FLIGHT_DIR="${ROOT_DIR}/flight"

# 通用函数：检查是否为root用户
check_root() 
{
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This operation requires root privileges. Use sudo."
        exit 1
    fi
}

# 创建Docker环境（安装、配置）
setup_docker_env() 
{
    check_root  # 安装需要root权限

    echo "===== Starting Docker environment setup ====="

    # 1 安装Docker及docker-compose
    echo "Step 1/4: Installing Docker and dependencies..."
    if ! command -v docker &> /dev/null; then
        # 更新 apt 源
        apt-get update -qq
        # 安装依赖
        apt-get install -qq -y ca-certificates curl gnupg lsb-release python3 python3-pip
        # 添加 Docker GPG 密钥
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        # 添加 Docker 源
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        # 安装 Docker
        apt-get update -qq
        apt-get install -qq -y docker-ce docker-ce-cli containerd.io docker-compose docker-compose-plugin
        echo "Docker installed successfully."
    else
        echo "Docker is already installed."
    fi

    # 2 配置用户组（避免每次使用 sudo）
    echo "Step 2/4: Configuring docker user group..."
    local current_user=$(logname)  # 获取登录用户（非root）
    if ! id -nG "$current_user" | grep -q "docker"; then
        usermod -aG docker "$current_user"
        echo "User '$current_user' added to docker group. Note: You need to log out and log back in for this to take effect."
    else
        echo "User '$current_user' is already in docker group."
    fi

    # 3 配置镜像加速（如果启用）
    echo "Step 3/4: Configuring image acceleration..."
    if [ "$IMAGE_ACCEL" = "true" ]; then
        # 创建 Docker 配置目录
        mkdir -p /etc/docker
        # 配置国内镜像加速（示例：阿里云，可替换为其他源）
        cat > /etc/docker/daemon.json << EOF
        {
            "registry-mirrors": ["https://registry.docker-cn.com", "https://mirror.aliyuncs.com"]
        }
EOF
        # 重启 Docker 生效
        systemctl daemon-reload
        systemctl restart docker
        echo "Image acceleration configured."
    else
        echo "Image acceleration is disabled (use -s true to enable)."
    fi

    # 4 创建必要的 Docker 网络和卷
    # echo "Step 4/4: Creating Docker networks and volumes..."
    # 创建共享网络（供ubuntu和flight容器使用）
    # if ! docker network inspect flight_network &> /dev/null; then
    #     docker network create flight_network
    #     echo "Network 'flight_network' created."
    # else
    #     echo "Network 'flight_network' already exists."
    # fi

    # 创建数据卷（用于持久化存储）
    # if ! docker volume inspect flight_data &> /dev/null; then
    #     docker volume create flight_data
    #     echo "Volume 'flight_data' created."
    # else
    #     echo "Volume 'flight_data' already exists."
    # fi

    echo "===== Docker environment setup completed ====="
}

# 4. 移除Docker环境（清理容器、网络、卷）
cleanup_docker_env() 
{
    check_root  # 清理需要root权限

    echo "===== Starting Docker environment cleanup ====="

    # 1 停止并删除所有相关容器（基于 compose 文件）
    echo "Step 1/3: Stopping and removing containers..."
    # 停止 ubuntu 相关容器
    if [ -f "${UBUNTU_DIR}/docker-compose-ubuntu.yml" ]; then
        docker-compose -f "${UBUNTU_DIR}/docker-compose-ubuntu.yml" down --remove-orphans
    fi
    # 停止 flight 相关容器
    if [ -f "${FLIGHT_DIR}/docker-compose-flight.yml" ]; then
        docker-compose -f "${FLIGHT_DIR}/docker-compose-flight.yml" down --remove-orphans
    fi

    # 2 删除创建的网络和卷
    # echo "Step 2/3: Removing networks and volumes..."
    # if docker network inspect flight_network &> /dev/null; then
    #     docker network rm flight_network
    #     echo "Network 'flight_network' removed."
    # fi
    # if docker volume inspect flight_data &> /dev/null; then
    #     docker volume rm flight_data
    #     echo "Volume 'flight_data' removed."
    # fi

    # 3 清理残留配置（可选：保留Docker软件，仅清理自定义配置）
    echo "Step 3/3: Cleaning up residual configs..."
    if [ -f "/etc/docker/daemon.json" ]; then
        # 备份后删除镜像加速配置
        mv /etc/docker/daemon.json /etc/docker/daemon.json.bak
        systemctl daemon-reload
        systemctl restart docker
        echo "Residual configs backed up to /etc/docker/daemon.json.bak."
    fi

    echo "===== Docker environment cleanup completed ====="
}

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

usage() 
{
    echo "Usage: sudo ./$PROGNAME -t <image-type> -c <start|stop> [OPTIONS]

    功能: 启动或停止指定类型的Docker镜像

    必填参数：
    -t <image-type>   镜像类型, 支持:ubuntu、flight
    -c <start|stop>   操作命令：
                      start   - 启动指定类型的镜像
                      stop    - 停止指定类型的镜像
                      setup   - 创建Docker环境(安装Docker、配置用户组、网络等)
                      cleanup - 清理Docker环境(删除容器、网络、卷等)

    可选参数：
    -e <env-file>     环境变量文件路径(flight 类型必填, ubuntu 可选)
    -v <version>      Ubuntu 版本, 支持: 1804、2004、2204 (默认使用通用配置)
    -s <true|false>   是否启用镜像加速(setup 时有效): 默认 false
    -h                显示帮助信息

    示例：
    1. 创建 Docker 环境(启用镜像加速): 
        sudo ./$PROGNAME -c setup -s true
    2. 启动ubuntu 20.04 镜像：
        sudo ./$PROGNAME -t ubuntu -v 2004 -c start
    3. 停止 flight 镜像(指定 env 文件): 
        sudo ./$PROGNAME -t flight -e ./flight.env -c stop
    4. 清理 Docker 环境:
        sudo ./$PROGNAME -c cleanup
    "
}

# parse the parameters
OLD_OPTIND=$OPTIND
# 支持的选项：c(命令)、e(env文件)、t(镜像类型)、v(版本)、s(镜像加速)、h(帮助)
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
        s) IMAGE_ACCEL="$OPTARG" ;;  # 新增：控制镜像加速
        ?) usage; exit 0 ;;
        h) usage; exit 1 ;;
    esac
done
OPTIND=$OLD_OPTIND

# 检查命令是否有效
if [ -z "$COMMAND" ] || ! echo "start stop setup cleanup" | grep -q "$COMMAND"; then
    echo "Error: Invalid or missing command (-c must be start|stop|setup|cleanup)."
    usage
    exit 1
fi

# 处理环境创建（setup）和清理（cleanup），无需镜像类型参数
if [ "$COMMAND" = "setup" ] || [ "$COMMAND" = "cleanup" ]; then
    # 若用户误传了镜像类型参数，忽略并提示
    if [ -n "$IMAGE_TYPE_NAME" ]; then
        echo "Warning: -t is not required for '$COMMAND' command and will be ignored."
    fi
    # 执行环境操作
    if [ "$COMMAND" = "setup" ]; then
        setup_docker_env
    else
        cleanup_docker_env
    fi
    exit 0
fi

# 处理启动/停止（需要镜像类型参数）
if [ -z "$IMAGE_TYPE_NAME" ]; then
    echo "Error: -t <image-type> is required for 'start' or 'stop' command."
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
