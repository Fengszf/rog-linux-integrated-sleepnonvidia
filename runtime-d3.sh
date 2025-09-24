#!/bin/bash
# NVIDIA Runtime D3

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
}

# 配置NVIDIA Runtime D3动态电源管理（核心：启用精细D3）
configure_nvidia_runtime_d3() {
    log_info "配置NVIDIA Runtime D3动态电源管理..."
    
    # 写入最小必需的 NVIDIA 模块参数
    cat > /etc/modprobe.d/nvidia-runtime-d3.conf << 'EOF'
# 启用精细的动态电源管理
options nvidia NVreg_DynamicPowerManagement=0x02
# DRM 模式设置（常见所需）
options nvidia-drm modeset=1
EOF
    
    log_success "NVIDIA Runtime D3配置已创建"
}

# 创建正确的udev规则
create_runtime_pm_udev_rules() {
    log_info "创建Runtime PM udev规则..."
    
    cat > /etc/udev/rules.d/80-nvidia-runtime-pm.rules << 'EOF'
# NVIDIA Runtime Power Management udev规则
# 启用NVIDIA设备的运行时电源管理

# 启用NVIDIA VGA/3D控制器设备的运行时电源管理
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", TEST=="power/control", ATTR{power/control}="auto"

# 禁用NVIDIA VGA/3D控制器设备的运行时电源管理（当设备被解绑时）
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", TEST=="power/control", ATTR{power/control}="on"

# 强制启用Runtime D3状态
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", RUN+="/bin/bash -c 'echo auto > /sys/bus/pci/devices/%k/power/control'"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", RUN+="/bin/bash -c 'echo auto > /sys/bus/pci/devices/%k/power/control'"
EOF
    
    # 重新加载udev规则
    udevadm control --reload-rules
    udevadm trigger
    
    log_success "Runtime PM udev规则已创建并加载"
}

# 重新生成initramfs
regenerate_initramfs() {
    log_info "重新生成initramfs..."
    
    if command -v mkinitcpio &> /dev/null; then
        if [[ -f "/etc/mkinitcpio.d/linux-g14.preset" ]]; then
            mkinitcpio -p linux-g14
            log_success "已为 linux-g14 重新生成 initramfs"
        else
            log_warning "未找到 /etc/mkinitcpio.d/linux-g14.preset，尝试直接生成镜像"
            if [[ -e "/boot/vmlinuz-linux-g14" ]]; then
                mkinitcpio -k /boot/vmlinuz-linux-g14 -g /boot/initramfs-linux-g14.img
                log_success "已直接为 linux-g14 生成 initramfs"
            else
                log_error "缺少 linux-g14 preset 且未找到 /boot/vmlinuz-linux-g14，无法生成 initramfs"
            fi
        fi
    else
        log_warning "mkinitcpio未找到，跳过initramfs重新生成"
    fi
}

# 主函数
main() {
    echo "========================================"
    echo "NVIDIA Runtime D3 动态电源管理修复"
    echo "========================================"
    echo ""
    
    check_root
    configure_nvidia_runtime_d3
    create_runtime_pm_udev_rules
    regenerate_initramfs
}

main "$@"
