# 90-Second Narrated Demo Storyboard (`DEMO_SCRIPT.md`)

适用场景：**AI Agent / FDE 岗位简历置顶视频（90 秒中文版）** 与 **Upwork AI Integration 提案附件视频（60–75 秒英文版）**。
录制分辨率建议：`1440×900`（左屏浏览器三栏工作台，底部贴一个 6 行高度终端展示进程重启冒烟）。

---

## 一、 中文版解说词与操作分镜（约 85 秒，面向国内面试官与技术负责人）

### 0:00 – 0:15｜直击痛点开场（画面：停在三栏工作台首屏 `hitl-01` 挂起态）
- **动作**：鼠标滑过左栏 `hitl-01` 涂改报修单、中栏橙色 `ARITHMETIC_MISMATCH` 告警卡。
- **旁白**：
  > “企业落地的 Agent 读知识库容易，难的是安全写进业务库。比如这张手写涂改报修单，人工 80 加配件 120 实际是 200 元，但视觉模型误读成了 280。没有确定性护栏就会静默写错账。这是我用 Python `LangGraph` 加 `Flutter` 构建的受控 HITL 审批与评测飞轮工作台。”

### 0:15 – 0:45｜演示实时后端 `interrupt` -> 防呆拦截 -> `Command(resume)`（画面：右上角切到 `实时后端 (FastAPI)`）
- **动作**：
  1. 点右上角切换连接本地 `:8095` `FastAPI`；
  2. 点左栏 `投递状态机` 跑 `hitl-01` -> 中栏实时刷出 `human_review_gate` 挂起在 SQLite Checkpoint；
  3. 先故意不改 `280.00` 直接点 `Approve` -> 弹出 `422` 拦截提示（证明未污染 Checkpoint）；
  4. 点击 `一键填入核实修正值`（总计变为 `200.00`，黄色横幅提示“检测到 1 处字段修正”），再点 `Approve & Command(resume)`。
- **旁白**：
  > “切到实时 `FastAPI` 后端投递单据，确定性门禁在毫秒级拦下算术冲突，调用 `interrupt()` 把状态持久化进 SQLite。如果审批人没改错字直接点通过，前置校验会返回 422 且不污染 Checkpoint。填入核实后的 200 元点恢复，状态机从断点唤醒，生成唯一工单并自动捕获一条回归评测样本。”

### 0:45 – 1:08｜演示跨会话幂等防重与 Prompt 注入拦截（画面：左栏点 `clean-01` -> `trap-02` -> `trap-01`）
- **动作**：依次点 `clean-01`（自动落库）、`trap-02`（右栏显示 `IDEMPOTENT_REUSED = true`），打开右上角 `工单账本` 展示 `幂等重放拦截次数: 1`。
- **旁白**：
  > “面对移动端弱网超时重发，同一物理单据再次投递会命中 `Idempotency-Key` 账本直接复用原工单，实现零重复建单；而夹带 Prompt 注入企图套现的对抗单据会被防注入规则硬性挂起驳回。”

### 1:08 – 1:25｜Trace-to-Eval 回归飞轮收尾（画面：点右上角 `回归集 JSONL (1)` + 终端跑过 `e2e_smoke.sh` 绿字）
- **动作**：点开 `回归集 JSONL` 抽屉展示导出的 `raw_extraction vs expected_truth` JSONL，切一下终端展示 `./scripts/e2e_smoke.sh` 杀掉 `uvicorn` 重启恢复 `6/6 PASS`。
- **旁白**：
  > “每一次人工改字审批都会自动导出标准 JSONL 回归样本，配合 CLI 评测门禁拦截任何静默错写，并且经过真实杀进程重启验证。整套前端同时编译支持 Web、macOS 和 Android。”

---

## 二、 Upwork 60-Second Proof-of-Concept Loom Script (English, for Overseas Clients)

- **0:00 – 0:12 (Hook — Show the 3-pane UI)**:
  > "Hi [Client Name] — saw your post about automating document intake into your operations system without risking bad LLM writes. I built a working architecture for this exact workflow and wanted to show you how it handles edge cases in 60 seconds."
- **0:12 – 0:38 (Live Guardrail + Pause + Resume)**:
  > "Here's a messy repair invoice where the vision model misread an altered total as 280 instead of 200. Instead of writing bad data to your database, deterministic math and injection guards catch the discrepancy and pause the LangGraph state machine in persistent storage. Your team sees the exact flagged field, fixes 280 to 200, and clicks Approve — resuming execution with an idempotency key so network retries never create duplicate tickets."
- **0:38 – 0:58 (Flywheel + CTA)**:
  > "Better yet, every human edit automatically exports a regression test case so accuracy improves over time with zero silent failures. Happy to wire this pattern into your API or CRM — let me know which document type you'd like to test first."
