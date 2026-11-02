# 420 — RK3588 Go2 + MID360 + SCAN-Planner dyn stack

这是板端 `ATK-DLRK3588`（Ubuntu 24.04 / ROS 2 Jazzy）与 PC 端 Gazebo/RL 仿真栈的当前代码快照，包含 SCAN-Planner 的 dyn 分支、Go2 RL、MID360 ray bridge、Frontier Explorer，以及 Commit 1 的测量仪表。板端源码来自 `scan_dyn_ws/src/SCAN-Planner`，原目录没有 `.git`，因此这里是一次快照提交，不包含上游提交历史。

## 目录

```text
src/SCAN-Planner/             板端 ROS 2 源码（planner、plan_env、Explorer、controller、simulator assets）
launch_exploration.sh         PC 端启动包装（Humble）
PORTING_DYN_ZH.md             迁移、联调记录与关键参数
parkour_moe_full_model.onnx   RL 模型
bench/                        板端 FastDDS / Nav2 / 辅助脚本
```

`src/SCAN-Planner` 里另有 `run_newmine_rl.py`、`models/go2_rl_lab_policy.pt`、`map.pcd`、`src/simulator/Utils/go2_description` 和 `quadruped_exploration_planner`。

## 两侧分工

| 侧 | 内容 |
|---|---|
| 板端 | `scan_planner_node`（C++，`plan_env`/`scan_replan`）、`frontier_explorer.py`（Python）、`closed_loop_controller`；ROS 2 Jazzy；2×A76；Global 当前关闭 |
| PC | Gazebo Fortress + `go2_description` + `go2_locomotion_supervisor`（`go2_rl_lab_policy.pt`）+ `mid360_ray_bridge`；ROS 2 Humble |
| 链路 | 千兆有线；FastDDS `interfaceWhiteList` 只走 `192.168.1.x`（`bench/fastdds_board.xml`）；PC 侧 XML 不在此仓库，需按本机网卡补 |

## 构建

```bash
# 板端（Jazzy）
cd /userdata/ros_ws/scan_dyn_ws
source /opt/ros/jazzy/setup.bash
colcon build --symlink-install --parallel-workers 2 \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DUSE_GPU=OFF
source install/setup.bash

# PC（Humble）
cd ~/ros2_ws/scan_planner_dyn_ws
source /opt/ros/humble/setup.bash
colcon build --symlink-install --parallel-workers 2 \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DUSE_GPU=OFF
source install/setup.bash
```

更完整的环境、`rosdep` 和资源说明见 `src/SCAN-Planner/README.md`。

## 运行

```bash
# PC：NewMine + RL + MID360 bridge（路径按本机修改）
cd ~/ros2_ws/scan_planner_dyn_ws/src/SCAN-Planner
./run_newmine_rl.py --duration 0 --gui --show-rviz --global-mode off --domain 68
# 或根目录（Humble）
./launch_exploration.sh headless:=true
```

板端三节点（`scan_planner_node`、`frontier_explorer.py`、`closed_loop_controller`）的完整参数以 `PORTING_DYN_ZH.md` 为准。关键项包括：

- Explorer：`cloud_frame_id=go2/base/exploration_lidar`、`use_ray_cloud=true`、`resolution=0.2`
- 外参：`lidar_extrinsic_x=0.187`、`z=0.0803`、`pitch=0.22689280275926285`
- Z 带：`obstacle_min_z=-0.25`、`obstacle_max_z=0.25`、`body_slice_min_z=-0.125`
- 时间对齐：`pose_history_seconds=1.5`、`max_interpolation_gap=0.15`、`max_nearest_pose_age=0.12`
- 板端统一 `use_sim_time=true`；真实机器人/实机 bag 应改为系统时间并去掉 `/clock` 订阅

## Commit 1 测量

- Local：`src/SCAN-Planner/src/planner/plan_env/include/plan_env/fusion_metrics.h` + `grid_map.cpp`；CSV 含 wall/cpu/runnable、prelock/lock、raycast、fusion_other、snapshot_build/publish、visualization、callback_total、points，以及 `raycast_sliding/terrain_maint/point_loop` 三个子阶段。
- Explorer：`src/SCAN-Planner/src/planner/plan_manage/scripts/explorer_core/work_metrics.py` + `frontier_explorer.py`；CSV 含 work_class/phase、wall/cpu/runnable、count/input_size，覆盖 decode/project/terrain/integrate/publish 和 plan/cycle/metrics/overlay/branch。
- 本快照对应的一次 90 s 运行（仿真，Explorer 4 Hz，Local 9.26/s）：
  - Local `raycast_process` p50 26.4 ms wall / 15.1 ms CPU；点循环 17.5 ms；点循环后的 terrain 投影更新 7.9 ms；runnable p95 40.1 ms。
  - Explorer `project` p50 64.7/24.1 ms；`integrate` 24.8/6.9 ms；`explorer_plan` p95 191 ms。
  - 进程 CPU：Explorer 91%、Planner 65%；500 Hz `/clock` + 4/6 线程 executor 是最大单项（最小 `/clock` 探针 109% 核）。
- **口径 caveat**：500 Hz `/clock` 是 Gazebo bridge 的产物，真实 GO2/MID360 没有 `/clock`。不要把当前 91%/65% 直接当作真实算力预算；先做 `/clock` 500→100 Hz 的同节点 A/B，再评估 L2/L3。详见 `PORTING_DYN_ZH.md`。

## 已知问题 / 下一步

1. 500 Hz `/clock` + `MultiThreadedExecutor` 的唤醒/回调开销；先做 500↔100 Hz A/B，真实机器人 `use_sim_time=false`。
2. Explorer 与 Local 重复做原始点云投影（L2）：Explorer `project` 约 9.6% 核 + raw cloud DDS/decode；Local raycast 约 14% 核。
3. 每次 cloud 全量构建安全快照（5–6 ms）和 4 Hz 整图/可视化发布；做 revision/content 门控。
4. `explorer_plan` 长尾（p95 191 ms，10 次候选路线/选择）会堵 executor；事件化 + 可中断。
5. Local 点循环/点循环后 terrain 投影的 L1；不要通过降分辨率、量程或 ground evidence 换 CPU。
6. Global 保持关闭；E4 净价值验证前不加回。

## 文档

- `PORTING_DYN_ZH.md`：板端/PC 分工、关键修正、历史测量与“下一步按收益”清单
- `src/SCAN-Planner/README.md`：上游 dyn 分支的构建与新 mine 启动说明
- `src/SCAN-Planner/RL_POLICY_INTEGRATION_SUMMARY.md`：Go2 RL 接入摘要
- `bench/`：`fastdds_board.xml`、`nav2_global_only.yaml`、`fake_loco.py`、`lidar_tf.py`

## 未包含

`build/`、`install/`、`log/`；测试 CSV/日志；`.claude/`；`tools/code_audit/audit_data.json`；`symlink_install_manifest.txt`；板端 `/userdata/tare_test` 的原始数据；PC 侧 FastDDS XML；ROS bag；本机 `.git` 历史。`bench/fastdds_board.xml` 含板端 IP，`launch_exploration.sh` 含 PC 路径，按本机修改后使用。

`map.pcd`（48 MB）、模型和网格已包含；仓库总量约 124 MB。
