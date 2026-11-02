#!/bin/bash
# Go2 + SCAN-Planner 三层探索启动脚本
#
# 用法:
#   ./launch_exploration.sh                              # 默认 world = test.sdf
#   WORLD=/home/t1an/ros2_ws/mine_tunnel_world/worlds/NewMine.sdf ./launch_exploration.sh
#   ./launch_exploration.sh headless:=true               # 额外参数透传给 launch
#
# 这个脚本存在的意义：ros2 launch 必须同时 source /opt/ros/humble 和工作区
# 的 install/setup.bash，否则会报 "Package 'scan_planner' not found"。

WS=/home/t1an/ros2_ws/scan_planner_dyn_ws
WORLD=${WORLD:-/home/t1an/ros2_ws/mine_tunnel_world/worlds/NewMine.sdf}
SCAN_ROS_DOMAIN_ID=${SCAN_ROS_DOMAIN_ID:-42}
export ROS_DOMAIN_ID=$SCAN_ROS_DOMAIN_ID
IGN_PARTITION=${IGN_PARTITION:-scan_planner_${ROS_DOMAIN_ID}}
export IGN_PARTITION

if [ ! -f "$WORLD" ]; then
  echo "错误: world 文件不存在: $WORLD" >&2
  exit 1
fi

# 传感器和力驱动都靠 world 级的系统插件；缺一个就会静默失效
if ! grep -q "systems::Sensors" "$WORLD"; then
  echo "警告: $WORLD 没有 Sensors 系统插件 -> Gazebo 不会发布雷达/相机数据" >&2
fi
if ! grep -q "ApplyLinkWrench" "$WORLD"; then
  echo "警告: $WORLD 没有 ApplyLinkWrench 系统插件 -> 机器人收不到速度指令" >&2
fi

cd "$WS"
source /opt/ros/humble/setup.bash
source install/setup.bash

LOCOMOTION_MODE=planning_kinematic
for arg in "$@"; do
  case "$arg" in
    locomotion_mode:=*) LOCOMOTION_MODE=${arg#locomotion_mode:=} ;;
  esac
done

if [ "$LOCOMOTION_MODE" = "rl_effort" ]; then
  EXECUTION_BACKEND=gazebo_joint_effort_controller
  ONNX_STATUS=enabled_effort_policy
else
  EXECUTION_BACKEND=gazebo_velocity_control
  ONNX_STATUS=disabled
fi

echo "MODE=gazebo"
echo "ROS_DOMAIN_ID=$ROS_DOMAIN_ID"
echo "IGN_PARTITION=$IGN_PARTITION"
echo "WORLD_FILE=$WORLD"
echo "INIT_POSE=(0.0, 0.0, 0.45)"
echo "CLOUD_FRAME=go2/base/exploration_lidar"
echo "GLOBAL_TRUTH_CLOUD=disabled"
echo "LOCOMOTION_MODE=$LOCOMOTION_MODE"
echo "EXECUTION_BACKEND=$EXECUTION_BACKEND"
echo "ONNX=$ONNX_STATUS"

exec ros2 launch scan_planner newmine_exploration.launch.py \
  world_file:="$WORLD" \
  use_gazebo_physics:=true \
  use_sim_time:=true \
  use_pcd_map:=false \
  use_sdf_map:=false \
  sdf_recenter:=false \
  publish_sdf_global_cloud:=false \
  "$@"
