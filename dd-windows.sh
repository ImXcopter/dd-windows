#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

function CopyRight() {
  clear
  echo "============================================================"
  echo "DD Windows 一键安装脚本"
  echo "============================================================"
  echo -e "\n"
}

function isValidIp() {
  local ip=$1
  local ret=1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    ip=(${ip//\./ })
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    ret=$?
  fi
  return $ret
}

function ipCheck() {
  isLegal=0
  for add in $MAINIP $GATEWAYIP $NETMASK; do
    isValidIp $add
    if [ $? -eq 1 ]; then
      isLegal=1
    fi
  done
  return $isLegal
}

function GetIp() {
  MAINIP=$(ip route get 1 | awk -F 'src ' '{print $2}' | awk '{print $1}')
  GATEWAYIP=$(ip route | grep default | awk '{print $3}')
  SUBNET=$(ip -o -f inet addr show | awk '/scope global/{sub(/[^.]+\//,"0/",$4);print $4}' | head -1 | awk -F '/' '{print $2}')
  value=$(( 0xffffffff ^ ((1 << (32 - $SUBNET)) - 1) ))
  NETMASK="$(( (value >> 24) & 0xff )).$(( (value >> 16) & 0xff )).$(( (value >> 8) & 0xff )).$(( value & 0xff ))"
}

function UpdateIp() {
  read -r -p "请输入 IP: " MAINIP
  read -r -p "请输入网关: " GATEWAYIP
  read -r -p "请输入子网掩码: " NETMASK
}

function SetNetwork() {
  isAuto='0'
  if [[ -f '/etc/network/interfaces' ]];then
    [[ ! -z "$(sed -n '/iface.*inet static/p' /etc/network/interfaces)" ]] && isAuto='1'
    [[ -d /etc/network/interfaces.d ]] && {
      cfgNum="$(find /etc/network/interfaces.d -name '*.cfg' |wc -l)" || cfgNum='0'
      [[ "$cfgNum" -ne '0' ]] && {
        for netConfig in `ls -1 /etc/network/interfaces.d/*.cfg`
        do 
          [[ ! -z "$(cat $netConfig | sed -n '/iface.*inet static/p')" ]] && isAuto='1'
        done
      }
    }
  fi
  
  if [[ -d '/etc/sysconfig/network-scripts' ]];then
    cfgNum="$(find /etc/network/interfaces.d -name '*.cfg' |wc -l)" || cfgNum='0'
    [[ "$cfgNum" -ne '0' ]] && {
      for netConfig in `ls -1 /etc/sysconfig/network-scripts/ifcfg-* | grep -v 'lo$' | grep -v ':[0-9]\{1,\}'`
      do 
        [[ ! -z "$(cat $netConfig | sed -n '/BOOTPROTO.*[sS][tT][aA][tT][iI][cC]/p')" ]] && isAuto='1'
      done
    }
  fi
}

function NetMode() {
  CopyRight
  if [ "$isAuto" == '0' ]; then
    read -r -p "是否使用 DHCP 自动配置网络？[Y/n]:" input
    case $input in
      [yY][eE][sS]|[yY]) NETSTR='' ;;
      [nN][oO]|[nN]) isAuto='1' ;;
      *) clear; echo "用户已取消！"; exit 1;;
    esac
  fi

  if [ "$isAuto" == '1' ]; then
    GetIp
    ipCheck
    if [ $? -ne 0 ]; then
      echo -e "自动检测 IP 时出错，请手动输入。\n"
      UpdateIp
    else
      CopyRight
      echo "IP：$MAINIP"
      echo "网关：$GATEWAYIP"
      echo "子网掩码：$NETMASK"
      echo -e "\n"
      read -r -p "确认以上网络配置？[Y/n]:" input
      case $input in
        [yY][eE][sS]|[yY]) ;;
        [nN][oO]|[nN])
          echo -e "\n"
          UpdateIp
          ipCheck
          [[ $? -ne 0 ]] && {
            clear
            echo -e "输入错误！\n"
            exit 1
          }
        ;;
        *) clear; echo "用户已取消！"; exit 1;;
      esac
    fi
    NETSTR="--ip-addr ${MAINIP} --ip-gate ${GATEWAYIP} --ip-mask ${NETMASK}"
  fi
}

function NormalizeImagePrefix() {
  IMAGE_PREFIX="${IMAGE_PREFIX:-}"
  case "$IMAGE_PREFIX" in
    http://*|https://*) ;;
    *) return 1 ;;
  esac

  case "$IMAGE_PREFIX" in
    *[[:space:]]*|*[\?\#]*) return 1 ;;
  esac

  local rest="${IMAGE_PREFIX#http://}"
  local host
  if [ "$rest" = "$IMAGE_PREFIX" ]; then
    rest="${IMAGE_PREFIX#https://}"
  fi
  host="${rest%%/*}"
  [[ -n "$host" ]] || return 2

  IMAGE_PREFIX="${IMAGE_PREFIX%/}/"
}

function SetImageFileNames() {
  IMAGE_FILE17="cxthhhhh.com_Windows_Server_2022_DataCenter_CN_v2.12.vhd.gz"
  IMAGE_FILE18="cxthhhhh.com_Windows_Server_2022_DataCenter_CN_v2.12_UEFI.vhd.gz"
  IMAGE_FILE24="Teddysun.com_Windows10_LTSC_CN.xz"
  IMAGE_FILE25="Teddysun.com_Windows10_LTSC_CN_UEFI.xz"
  IMAGE_FILE30="nat.ee_Windows 10_Enterprise_LTSC_2021_x64_CN.vhd.gz"
  IMAGE_FILE31="nat.ee_Windows 10_Enterprise_LTSC_2021_x64_CN_aliyun.vhd.gz"
  IMAGE_FILE32="nat.ee_Windows 10_Enterprise_LTSC_2021_x64_CN_UEFI.vhd.gz"
  IMAGE_FILE40="nat.ee_Windows_Server_2022_DataCenter_x64_CN.vhd.gz"
  IMAGE_FILE41="nat.ee_Windows_Server_2022_DataCenter_x64_CN_UEFI.vhd.gz"
}

function UrlEncodeImageFileName() {
  local name="$1"
  printf '%s' "${name// /%20}"
}

function BuildImageUrls() {
  SYSMIRROR17="${IMAGE_PREFIX}$(UrlEncodeImageFileName "${IMAGE_FILE17}")"
  SYSMIRROR18="${IMAGE_PREFIX}$(UrlEncodeImageFileName "${IMAGE_FILE18}")"
  SYSMIRROR24="${IMAGE_PREFIX}$(UrlEncodeImageFileName "${IMAGE_FILE24}")"
  SYSMIRROR25="${IMAGE_PREFIX}$(UrlEncodeImageFileName "${IMAGE_FILE25}")"
  SYSMIRROR30="${IMAGE_PREFIX}$(UrlEncodeImageFileName "${IMAGE_FILE30}")"
  SYSMIRROR31="${IMAGE_PREFIX}$(UrlEncodeImageFileName "${IMAGE_FILE31}")"
  SYSMIRROR32="${IMAGE_PREFIX}$(UrlEncodeImageFileName "${IMAGE_FILE32}")"
  SYSMIRROR40="${IMAGE_PREFIX}$(UrlEncodeImageFileName "${IMAGE_FILE40}")"
  SYSMIRROR41="${IMAGE_PREFIX}$(UrlEncodeImageFileName "${IMAGE_FILE41}")"
}

function ValidateImageUrl() {
  local url="$1"

  case "$url" in
    http://*|https://*) ;;
    *)
      echo "镜像 URL 必须以 http:// 或 https:// 开头：$url" >&2
      return 1
    ;;
  esac

  if ! wget --no-check-certificate --spider -q "$url"; then
    echo "所选镜像文件不存在或无法访问：$url" >&2
    return 1
  fi
}

function PromptImagePrefix() {
  local image_file="$1"
  local input

  while true
  do
    echo "请输入镜像目录前缀（将自动拼接：${image_file}，例如 https://your-domain.example/folder_name/）"
    read -r -p "> " input
    IMAGE_PREFIX="$input"
    if NormalizeImagePrefix; then
      printf '%s\n' "$IMAGE_PREFIX"
      return 0
    else
      echo "前缀必须以 http:// 或 https:// 开头，且不能包含空格、?、#。可以填写域名根路径，例如：https://your-domain.example/" >&2
    fi
  done
}

function PrepareImageUrl() {
  local image_file="$1"

  IMAGE_PREFIX="${IMAGE_PREFIX:-}"
  if [[ -z "$IMAGE_PREFIX" ]]; then
    IMAGE_PREFIX="$(PromptImagePrefix "$image_file")"
  elif ! NormalizeImagePrefix; then
    echo "IMAGE_PREFIX 必须以 http:// 或 https:// 开头，且不能包含空格、?、#。可以填写域名根路径，例如：https://your-domain.example/" >&2
    exit 1
  fi

  SELECTED_IMAGE_URL="${IMAGE_PREFIX}$(UrlEncodeImageFileName "$image_file")"
  ValidateImageUrl "$SELECTED_IMAGE_URL" || exit 1
}

function Start() {
  if [ "$isAuto" == '0' ]; then
    echo "使用 DHCP 自动配置网络。"
  else
    echo "IP：$MAINIP"
    echo "网关：$GATEWAYIP"
    echo "子网掩码：$NETMASK"
  fi

  if [ -f "/tmp/InstallNET.sh" ]; then
    rm -f /tmp/InstallNET.sh
  fi

  wget --no-check-certificate -qO /tmp/InstallNET.sh 'https://raw.githubusercontent.com/fcurrk/reinstall/master/InstallNET.sh' && chmod a+x /tmp/InstallNET.sh

  SetImageFileNames

  DMIRROR=''

  echo -e "\n请选择要安装的系统:"
  echo "   1) Windows Server 2022 [X64-Legacy-cxthhhhh]"
  echo "   2) Windows Server 2022 [X64-UEFI-cxthhhhh]"
  echo "   3) Windows 10 LTSC [X64-Legacy-teddysun]"
  echo "   4) Windows 10 LTSC [X64-UEFI-teddysun]"
  echo "   5) Windows 10 LTSC Lite [X64-Legacy-nat.ee]"
  echo "   6) Windows 10 LTSC Lite [X64-Legacy-aliyun-nat.ee]"
  echo "   7) Windows 10 LTSC Lite [X64-UEFI-nat.ee]"
  echo "   8) Windows Server 2022 Lite [X64-Legacy-nat.ee]"
  echo "   9) Windows Server 2022 Lite [X64-UEFI-nat.ee]"
  echo "  99) 自定义镜像"
  echo "   0) 退出"
  echo -ne "\n请输入编号: "
  read N
  case $N in
    1) PrepareImageUrl "${IMAGE_FILE17}"; SYSMIRROR17="${SELECTED_IMAGE_URL}"; echo -e "\n默认密码：cxthhhhh.com\n"; read -s -n1 -p "按任意键继续..." ; bash /tmp/InstallNET.sh $NETSTR -dd "$SYSMIRROR17" $DMIRROR ;;
    2) PrepareImageUrl "${IMAGE_FILE18}"; SYSMIRROR18="${SELECTED_IMAGE_URL}"; echo -e "\n默认密码：cxthhhhh.com\n"; read -s -n1 -p "按任意键继续..." ; bash /tmp/InstallNET.sh $NETSTR -dd "$SYSMIRROR18" $DMIRROR ;;
    3) PrepareImageUrl "${IMAGE_FILE24}"; SYSMIRROR24="${SELECTED_IMAGE_URL}"; echo -e "\n默认密码：Teddysun.com\n"; read -s -n1 -p "按任意键继续..." ; bash /tmp/InstallNET.sh $NETSTR -dd "$SYSMIRROR24" $DMIRROR ;;
    4) PrepareImageUrl "${IMAGE_FILE25}"; SYSMIRROR25="${SELECTED_IMAGE_URL}"; echo -e "\n默认密码：Teddysun.com\n"; read -s -n1 -p "按任意键继续..." ; bash /tmp/InstallNET.sh $NETSTR -dd "$SYSMIRROR25" $DMIRROR ;;
    5) PrepareImageUrl "${IMAGE_FILE30}"; SYSMIRROR30="${SELECTED_IMAGE_URL}"; echo -e "\n默认密码：nat.ee\n"; read -s -n1 -p "按任意键继续..." ; bash /tmp/InstallNET.sh $NETSTR -dd "$SYSMIRROR30" $DMIRROR ;;
    6) PrepareImageUrl "${IMAGE_FILE31}"; SYSMIRROR31="${SELECTED_IMAGE_URL}"; echo -e "\n默认密码：nat.ee\n"; read -s -n1 -p "按任意键继续..." ; bash /tmp/InstallNET.sh $NETSTR -dd "$SYSMIRROR31" $DMIRROR ;;
    7) PrepareImageUrl "${IMAGE_FILE32}"; SYSMIRROR32="${SELECTED_IMAGE_URL}"; echo -e "\n默认密码：nat.ee\n"; read -s -n1 -p "按任意键继续..." ; bash /tmp/InstallNET.sh $NETSTR -dd "$SYSMIRROR32" $DMIRROR ;;
    8) PrepareImageUrl "${IMAGE_FILE40}"; SYSMIRROR40="${SELECTED_IMAGE_URL}"; echo -e "\n默认密码：nat.ee\n"; read -s -n1 -p "按任意键继续..." ; bash /tmp/InstallNET.sh $NETSTR -dd "$SYSMIRROR40" $DMIRROR ;;
    9) PrepareImageUrl "${IMAGE_FILE41}"; SYSMIRROR41="${SELECTED_IMAGE_URL}"; echo -e "\n默认密码：nat.ee\n"; read -s -n1 -p "按任意键继续..." ; bash /tmp/InstallNET.sh $NETSTR -dd "$SYSMIRROR41" $DMIRROR ;;
    99)
      echo -e "\n"
      echo "请输入自定义镜像完整 URL:"
      read -r -p "> " imgURL
      ValidateImageUrl "$imgURL" || exit 1
      echo -e "\n"
      read -r -p "确认开始重装吗？[Y/n]: " input
      case $input in
        [yY][eE][sS]|[yY]) bash /tmp/InstallNET.sh $NETSTR -dd "$imgURL" $DMIRROR ;;
        *) clear; echo "用户已取消！"; exit 1;;
      esac
      ;;
    0) exit 0;;
    *) echo "输入错误！"; exit 1;;
  esac
}

SetNetwork
NetMode
Start
