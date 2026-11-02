# dyn 工作区迁移到 3588 (Jazzy/Harmonic) — 结果记录

## 构建
- 源：scan_planner_dyn_ws/src/SCAN-Planner（分支 dyn-20261028-211234）
- 补丁与主 ws 相同：cv_bridge .h->.hpp、ignition->gz、gz-sim8 插件名、go2_sim.launch.py 的 gz CLI/GZ_SIM_*、
  exploration_planner COLCON_IGNORE
- Release 构建：13 包，6m55s

## 实测（PC 仿真 domain 61 <-> 3588 CPU6/7）
1) dyn planner + controller + Nav2（0.1m, ray 4.0, max_interp_gap 0.12）
   - GO2 移动 2.014 m 到达目标，cmd 100Hz，z 稳定
   - raycast 41-54 ms，cpu6+7 = 73%/200%
2) dyn 全栈：planner(task_mode) + controller + global_representation + frontier_explorer
   - explorer 需要 -p cloud_frame_id:=go2/base/exploration_lidar，否则 wrong_frame 丢云
   - 整合 31 帧后 known_cells=1762；机器人被驱动约 4 m
   - cpu6+7 峰值 158%/200%（planner 59 + explorer 52 + global_rep 36 + controller 9）
   - 随后摔倒：tilt_cos=0.433 (~64°), body_world_z=0.239 vs leg_extension=0.161
     -> supervisor [BODY_POSE_FAULT] BODY_POSE_INVALID_MAP_RESTART_REQUIRED，DAMPING_ONLY
     -> planner locomotionReady()=false，地图冻结，LOCAL_SAFETY_HOLD
   - 该状态无法自恢复，必须重启 run（丢弃无效姿态建的地图）

## 2 核结论
- 平均算力够（104-158%/200%），但 raycast 尾延迟在竞争下到 90ms（预算 100ms），余量很薄
- 更大的痛点是安全契约：一次摔倒/姿态失效即锁死全栈
- 建议：限速 0.4-0.5、开启刹车/handoff 参数；planner 独占 cpu6，Python 节点绑 cpu7；
  真机/长跑前先用非拆分 dyn 全栈验证策略与地形

## 修正版：dyn 策略/世界 + 分侧全栈（2026-10-28）
PC: dyn go2_sim(resources/newmine) + mid360_ray_bridge + go2_locomotion_supervisor(go2_rl_lab, .pt)
3588: dyn planner(task_mode) + controller + global_representation + frontier_explorer，绑 cpu6/7，0.1m

关键修正（缺一个就跑不起来）：
1. 必须用 dyn 的 go2_rl_lab_policy.pt + dyn 世界；主 ws 的 legacy ONNX + 主世界会摔
2. explorer: cloud_frame_id=go2/base/exploration_lidar
3. explorer: lidar_extrinsic_x=0.187 z=0.0803 pitch=0.22689
4. explorer: obstacle_min_z=-0.25, obstacle_max_z=0.25, body_slice_min_z=-0.125（来自 planner.yaml 的 low/high_return_z）
5. 分侧时间对齐：pose_history_seconds=1.5（默认 0.5），max_interpolation_gap=0.15，max_nearest_pose_age=0.12
   否则 WiFi 下 planner 大量 TOO_NEW/TOO_OLD 丢云，map_age 涨到 100s

结果：
- GO2 自主移动 3.223 m，z [0.276,0.373]，无摔倒
- explorer known_cells 2708->2993, revision 111, wrong_frame=0
- cpu6+7 = 79%/200%（explorer 36%, global_rep 21%, planner 15.5%, controller 6.2%）
- planner raycast 57.8ms，一次 106.1ms（超 100ms 预算）

2 核瓶颈：平均算力够，痛点是 raycast 尾延迟（竞争下 106ms）+ 跨机 odom/点云时间错位。

## 更新版 dyn (7d48e6f) + 有线链路 实测 2026-10-29
- 有线：PC enp7s0 192.168.1.50 <-> 3588 end0 192.168.1.122，1000Mb/s full；传输 86.6MB/s
- 但 FastDDS 默认双网卡：end0 与 wlx 各 ~7MB/s（数据重复发送），需 interfaceWhiteList 绑有线
- 更新版 CPU（cpu6/7 全绑，2 核）：192%/200% —— 饱和
  - python3(explorer) 82.1%，python3(global) 53.3%，scan_planner 42.5%，controller 14.0%
  - planner raycast 103-147ms（被 Python 抢核）
- 按线程：explorer 主线程 57.5%，global 主线程 50%，4 个 DDS 线程各 ~4.5%，ThreadPool worker 空闲
  - py-spy dump: 主线程停在 _wait_for_ready_callbacks/add_to_wait_set
  - 结论：CPU 主要花在 rclpy executor 唤醒/等待（/clock 500Hz + explorer 14 个订阅/3 个 timer）
    和双网卡 DDS 收包，不是 wavefront/建图算法
- 运行约 6m 后摔倒：z=0.087，state=2，BODY_POSE_INVALID_MAP_RESTART_REQUIRED；
  explorer 被 perception_pose_valid=false 门控（integrated=100 后不再入图）
  PC 全栈（多核）不摔，2 核饱和下的时序退化是主要嫌疑

## 下一步（按收益）
1. FastDDS interfaceWhiteList 只走 192.168.1.x（两端），去掉 WiFi 重复流量和 DDS 线程开销
2. /clock 降频到 50-100Hz（PC 侧 relay 或 3588 侧 remap /clock:=/clock50），减少 executor 唤醒
3. 降 explorer/global 的 timer/发布频率，减少 14 个订阅带来的 wait-set 重建
4. 仍超 2 核则把 Python 节点放 A55（cpu0-3），A76 只留 planner/controller
5. 最后才考虑 C++：record_terrain 仍是逐点 Python 循环；wavefront 已重写为 dirty-tile
