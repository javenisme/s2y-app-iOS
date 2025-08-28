#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "[ERROR] GitHub CLI (gh) is not installed. Install via: brew install gh" >&2
  exit 1
fi

# Detect owner/repo from git remote
REMOTE_URL=$(git remote get-url origin)
if [[ -z "${REMOTE_URL:-}" ]]; then
  echo "[ERROR] No git remote 'origin' found." >&2
  exit 1
fi

# Normalize to owner/repo
if [[ "$REMOTE_URL" =~ github.com[:/](.+)/(.+)\.git$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
else
  echo "[ERROR] Unsupported remote URL: $REMOTE_URL" >&2
  exit 1
fi

echo "Using repository: $OWNER/$REPO"

echo "Ensuring authentication (requires prior: gh auth login -s repo -w)"
if ! gh auth status >/dev/null 2>&1; then
  echo "[ERROR] gh is not authenticated. Run: gh auth login -s repo -w" >&2
  exit 1
fi

# Create milestones M0..M3 if not exist
create_milestone() {
  local title="$1"; shift
  local description="$1"; shift
  if ! gh api repos/$OWNER/$REPO/milestones --paginate | jq -e ".[] | select(.title == \"$title\")" >/dev/null 2>&1; then
    gh api repos/$OWNER/$REPO/milestones -f title="$title" -f state=open -f description="$description" >/dev/null
    echo "Created milestone: $title"
  else
    echo "Milestone exists: $title"
  fi
}

create_milestone "M0" "基础能力：HealthKit/Firebase/LLM 最小链路、外测" 
create_milestone "M1" "查询与可视化：趋势/对比、Planner 雏形、问卷闭环优化"
create_milestone "M2" "洞察与目标：工具函数、跨指标洞察、复盘视图"
create_milestone "M3" "对话增强与周报：多轮对话、个性化目标、性能体验"

# Create labels
create_label() {
  local name="$1"; shift
  local color="$1"; shift
  local desc="$1"; shift
  if ! gh label list --repo "$OWNER/$REPO" --json name | jq -e ".[] | select(.name == \"$name\")" >/dev/null 2>&1; then
    gh label create "$name" --repo "$OWNER/$REPO" --color "$color" --description "$desc" >/dev/null
    echo "Created label: $name"
  else
    echo "Label exists: $name"
  fi
}

create_label "epic:A" "0e8a16" "HealthKit 数据接入与可视化"
create_label "epic:B" "5319e7" "LLM Orchestrator + Query Planner"
create_label "epic:C" "e99695" "Insight & Goals"
create_label "epic:D" "fbca04" "Scheduler & Questionnaire 闭环"
create_label "epic:E" "d93f0b" "隐私、安全与合规"
create_label "epic:F" "006b75" "性能与体验"
create_label "priority:P0" "b60205" "最高优先级"
create_label "priority:P1" "e99695" "高优先级"
create_label "priority:P2" "c2e0c6" "中优先级"
create_label "type:feat" "0052cc" "Feature"
create_label "type:task" "5319e7" "Task"
create_label "type:bug" "d73a4a" "Bug"

# Helper to resolve milestone number by title
ms_number() {
  local title="$1"
  gh api repos/$OWNER/$REPO/milestones --paginate | jq ".[] | select(.title == \"$title\") | .number" -r
}

MS_M0="M0"
MS_M1="M1"
MS_M2="M2"
MS_M3="M3"

# Create initial M0 issues (idempotent by title check)
create_issue() {
  local title="$1"; shift
  local body="$1"; shift
  local labels="$1"; shift
  local milestone_number="$1"; shift

  if gh issue list --repo "$OWNER/$REPO" --search "$title in:title" --json title | jq -e ".[] | select(.title == \"$title\")" >/dev/null 2>&1; then
    echo "Issue exists: $title"
  else
    gh issue create \
      --repo "$OWNER/$REPO" \
      --title "$title" \
      --body "$body" \
      --label $labels \
      --milestone "$milestone_number" >/dev/null
    echo "Created issue: $title"
  fi
}

create_issue \
  "M0: Firebase 生产连通性（Bundle/Plist 对齐 + Firestore 初始化）" \
  "- 确认 Bundle ID=us.s2y.s2y-ios 与 GoogleService-Info.plist 对齐\n- 开启 Auth Email/Password；创建 Firestore 数据库\n- 运行基本写入/读取验收" \
  "type:task,priority:P0,epic:D" "$MS_M0"

create_issue \
  "M0: HealthKit 基础采集与缓存（步数/心率）" \
  "- 指标字典初稿：单位/窗口\n- 授权流程与失败回退\n- 本地缓存结构与缺失值处理初步" \
  "type:feat,priority:P0,epic:A" "$MS_M0"

create_issue \
  "M0: LLM 最小链路稳健化（Provider/错误兜底/Keychain）" \
  "- Provider 抽象雏形（Cloudflare/OpenAI）\n- 错误提示与重试\n- Keychain 令牌保存与空值策略" \
  "type:feat,priority:P0,epic:B" "$MS_M0"

create_issue \
  "M0: 每日问卷闭环（任务/提醒/提交）" \
  "- 调度创建每日任务与提醒\n- 问卷展示与提交写入\n- 交互与失败回退" \
  "type:feat,priority:P0,epic:D" "$MS_M0"

create_issue \
  "M0: TestFlight 外测（staging）" \
  "- App Store Connect API Key 注入\n- Fastlane deploy(staging)\n- 外测分发与回收反馈" \
  "type:task,priority:P0,epic:F" "$MS_M0"

# M1 issues
create_issue \
  "M1: 趋势/对比组件（7/30 天趋势、区间对比、解释注释）" \
  "- 趋势图与区间对比\n- 解释性注释与缺失值展示\n- 组件复用与主题适配" \
  "type:feat,priority:P1,epic:A" "$MS_M1"

create_issue \
  "M1: Planner 雏形（常见问法模板与参数化）" \
  "- 常见问法模板库\n- 参数提取与校验\n- 结果渲染回 Chat" \
  "type:feat,priority:P1,epic:B" "$MS_M1"

create_issue \
  "M1: 问卷体验优化（失败回退/重试/历史查看）" \
  "- 失败回退与重试\n- 历史记录查看\n- 可达性与动效细节" \
  "type:feat,priority:P1,epic:D" "$MS_M1"

# M2 issues
create_issue \
  "M2: 工具函数（聚合/窗口/阈值；Schema 校验）" \
  "- 聚合/窗口/阈值工具函数\n- Schema 与边界校验\n- 单元测试覆盖" \
  "type:feat,priority:P1,epic:B" "$MS_M2"

create_issue \
  "M2: 洞察与建议（单/跨指标；目标引擎-周期）" \
  "- 单/跨指标洞察与建议\n- 目标引擎（周期）\n- 评估指标与样例集" \
  "type:feat,priority:P1,epic:C" "$MS_M2"

create_issue \
  "M2: 复盘视图（周视图与变更解读）" \
  "- 周视图汇总\n- 关键变更解读\n- 与任务/提醒的串联" \
  "type:feat,priority:P1,epic:D" "$MS_M2"

# M3 issues
create_issue \
  "M3: 多轮对话（上下文记忆与澄清策略）" \
  "- 上下文记忆\n- 澄清与追问策略\n- 失败回退" \
  "type:feat,priority:P2,epic:B" "$MS_M3"

create_issue \
  "M3: 个性化目标 + 周报/月报" \
  "- 个性化目标\n- 周报/月报汇总\n- 订阅与导出" \
  "type:feat,priority:P2,epic:C" "$MS_M3"

create_issue \
  "M3: 性能与体验（缓存、流式、可达性）" \
  "- 缓存策略\n- 流式响应与占位渲染\n- 可达性优化" \
  "type:task,priority:P2,epic:F" "$MS_M3"

echo "All done."
