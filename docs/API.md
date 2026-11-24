# 番茄钟 AI 接口

番茄钟 App 运行时，会在本机 `http://127.0.0.1:47625` 开一个 JSON 接口（只监听回环地址，外部设备访问不到）。
AI（Claude Code、Codex 等）优先用命令行 **`pomo`**，它会自动读取端口和令牌。

## 给 AI 的用法速查

```bash
pomo health                 # 检查本机接口是否在线（无需令牌）
pomo status                 # 当前阶段 / 剩余时间 / 当前任务 / 今日统计与任务明细
pomo tasks                  # 今日待办（已排序，带序号和 id 前缀）
pomo add "整理实验数据" -e 2 -p P1 -d 11-25 -g 科研 --top3 --select   # 添加并设为当前任务
pomo done 3                 # 按序号（或 id 前缀）标记完成
pomo clear-done             # 清除所有已完成任务
pomo select 2 && pomo start # 选任务并开始专注
pomo pause | toggle | reset | skip
pomo phase focus|short|long
pomo interrupt internal|external [--undo]   # --undo 撤销误记的一次
pomo history [-d 7]         # 查看近 N 天（默认 7 天）的专注统计与任务明细
pomo reset-today            # 清零今日成果
pomo edit 2 -p P0 -d 明天 -g 论文   # 改优先级 / DDL / 标签；none 清空
pomo sync                   # 立即同步 Notion 任务
pomo log-today              # 立即同步今日番茄记录到 Notion
pomo --json tasks           # 任何命令加 --json 输出原始 JSON
```

- 任务引用：`pomo tasks` 里的**序号**（1 起，随排序变化）或 **id 前缀**（8 位，稳定，推荐 AI 使用）。
- 日期：`2026-11-25`、`11-25`、`今天`、`明天`、`后天`，或带时区的 ISO 时刻 `2026-11-25T18:00:00+08:00`。
- 优先级：`P0`（紧急）… `P3`（低）。
- `source: "notion"` 的任务来自 Notion，标题 / 优先级 / DDL 会在下次同步时被 Notion 覆盖；本地的预估和番茄数会保留。

## HTTP 接口

所有请求（`/v1/health` 除外）都要带 `Authorization: Bearer <token>`。
令牌和端口读取自配置文件 `api.json`：
- **macOS**：`~/Library/Application Support/Pomodoro/api.json`（权限 600）
- **Windows**：`%APPDATA%\Pomodoro\api.json`

`pomo` 命令行会自动按平台定位上述文件（也可用环境变量 `POMODORO_DATA_DIR` / `POMODORO_PORT` 覆盖）。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/v1/health` | 存活检查，不需要令牌 |
| GET | `/v1/status` | 阶段、剩余秒数、`endsAt`、当前任务、今日统计（含 `taskPomodoros` 明细） |
| GET | `/v1/tasks` | `{tasks: [...]}`，已按 Top 3 → 优先级 → DDL 排序 |
| POST | `/v1/tasks` | 添加：`{title, estimate?, priority?, due?, top3?, tag?, note?, select?}` |
| POST | `/v1/tasks/clear-finished` | 清除所有已完成任务，返回 `{ok, tasks}` |
| GET / PATCH / DELETE | `/v1/tasks/{ref}` | 查看 / 修改（同上字段 + `finished`）/ 删除 |
| POST | `/v1/tasks/{ref}/select` | 设为当前任务 |
| POST | `/v1/tasks/{ref}/complete` | 标记完成（开启回写时同步到 Notion） |
| POST | `/v1/timer/start` `pause` `toggle` `reset` `skip` | 计时控制，返回最新状态 |
| POST | `/v1/timer/phase` | `{phase: "focus" \| "short" \| "long"}` |
| POST | `/v1/interruptions` | `{kind: "internal" \| "external", undo?: true}`，仅专注阶段；`undo` 撤销本番茄内误记的一次 |
| GET | `/v1/stats/history?days=7` | 近 N 天（1–60，默认 7）专注统计趋势与汇总 `{days, summary}` |
| POST | `/v1/stats/reset` | 清零今日成果（番茄数、专注时长、打断、作废、本组进度） |
| POST | `/v1/notion/sync` | 立即同步 Notion 任务，返回 `{ok, count, tasks}` |
| POST | `/v1/notion/log-today` | 立即将今日（及未补传的历史跨天）番茄统计同步写入 Notion 每日记录库 |

`{ref}` = 序号或 id 前缀。错误返回 `{"error": "..."}` 和对应状态码（400 / 401 / 404 / 409）。

```bash
TOKEN=$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/Library/Application Support/Pomodoro/api.json")))["token"])')
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:47625/v1/status
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"title":"读论文","estimate":2,"priority":"P2","due":"明天"}' http://127.0.0.1:47625/v1/tasks
```

## Notion 同步

- **通用数据库适配**：在设置 →「同步与接口」里填入 Integration 令牌，并直接粘贴任意 Notion 任务数据库的**页面链接或 ID**（同时兼容 Notion 新版 `data_sources` 与传统 `databases` 接口）。
- **自动字段识别**：同步前会自动读取数据库结构并按类型和常见中英文列名匹配字段，仅针对实际存在的字段拼接查询筛选与排序条件：
  - **标题**：任意 `title` 类型字段（如 `Name`、`Task Name`、`任务`）
  - **状态**：优先 `status` 类型，其次 `select`（`Status`/`状态`），再其次 `checkbox`（`Done`/`已完成`）
  - **截止日期（DDL）**：`Due Date` / `Due` / `DDL` / `截止日期` 等 `date` 字段
  - **计划日期**：`Scheduled Date` / `Do Date` / `计划日期` 等 `date` 字段
  - **优先级**：`Priority` / `优先级`（支持 `P0–P3` 或 `Urgent`/`High`/`Medium`/`Low`、`高`/`中`/`低`）
  - **置顶 / Top 3**：`Top 3` / `Focus` / `Important` / `重点` / `置顶` 等 `checkbox` 字段
  - **标签**：`Course` / `Category` / `Project` / `Tag` / `项目` / `分类` / `标签`（`select` 或 `multi_select`）
- **筛选范围**：未完成任务中，满足「计划日期 = 今天」或「截止日期 ≤ 今天 + N 天（含已逾期，N 默认 7，可在设置调整 1–30 天）」或「置顶勾选」的任务；若数据库不含这些日期/置顶列，则拉取全部未完成任务。
- **分类排除（`excludedCategories`）**：支持在设置 →「同步与接口」填写逗号分隔的排除分类（默认 `Event`），命中的条目不会拉入「今日待办」，仍可保留在 Notion 日历视图中。
- **同步时机**：App 启动时、之后每 30 分钟、点「今日待办」旁的 Notion 按钮，或 `pomo sync`。
- **回写（默认关闭）**：在设置 →「同步与接口」里打开后，番茄钟里勾选完成会自动把 Notion 中识别到的状态改为完成态（或勾选完成复选框）。
- **每日记录同步（`Pomodoro Log`）**：可在设置 →「同步与接口」配置每日记录数据库链接或 ID。每完成一个番茄钟会实时按当天日期幂等写入/更新对应记录；跨天启动或日期切换时会自动将未上传的昨日成果放入待传队列（`pendingDailyLogs`），联网或触发同步时自动补传，也可随时运行 `pomo log-today` 手动同步。推荐列名：`Day`（Title）、`Date`（Date）、`Pomodoros`、`Focus Minutes`、`Internal Interruptions`、`External Interruptions`、`Voided`（Number）与 `Tasks`（Rich text）。
- **配置文件**：macOS 为 `~/Library/Application Support/Pomodoro/notion.json`（权限 600），Windows 为 `%APPDATA%\Pomodoro\notion.json`。
