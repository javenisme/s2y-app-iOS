# S2Y Roadmap（M0–M3）

参考：`Docs/epic-health-assistant.md`

## M0（1–2 周）：基础能力
- 集成与稳定：Spezi + HealthKit、Firebase 生产连通性
- LLM 最小链路：Keychain 令牌、云端调用、错误兜底
- 本地加密与权限说明
- 产出：可运行 Demo、TestFlight 外测

## M1（3–4 周）：查询与可视化
- Epic A/A1：趋势与对比可视化基础
- Epic B/B1：Query Planner 雏形（通用问答 + 模板）
- Epic D/D1：每日问卷 + 通知闭环
- 验收：10+ 问法正确率 ≥ 85%，P95 ≤ 5s

## M2（3–4 周）：洞察与目标
- Epic B/B2：健康工具函数（窗口、聚合、阈值）
- Epic C/C1–C2：单/跨指标洞察与建议，目标引擎（周期）
- Epic D/D2：任务状态与复盘视图
- 验收：≥3 组联动洞察；提醒准时率 ≥ 99%

## M3（3–4 周）：对话增强与周报
- Epic B/B3：多轮对话与上下文记忆
- Epic C/C3：个性化目标与每周/月报
- Epic F：性能与体验优化（缓存、流式、可达性）
- 验收：多轮对话成功率 ≥ 80%；满意度 ≥ 80%

## 发布与度量
- TestFlight：每阶段至少 1 次外测；收集 Crash/满意度
- 指标：DAU、问答渗透率、目标完成率、P95、隐私合规事件
