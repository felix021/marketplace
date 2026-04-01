---
title: feishu-notify
description: 通过飞书机器人发送即时消息通知，适用于需要及时告知用户重要信息、任务完成状态（尤其是长时间执行的任务）、需要用户决策，以及用户明确要求需要通知的场景。
author: Felix021
version: 1.0.1
tools:
  - Bash
---

# feishu-notify

通过环境变量配置的 `FEISHU_WEBHOOK_URL` 发送消息通知，适用于需要及时告知用户重要信息、任务完成状态或需要用户决策的场景。

## 何时使用

- 需要立即通知用户关键信息或决策点
- 长时间运行的任务完成或失败时
- 发现需要用户关注的重要情况
- 用户要求"完成后告诉我"的场景

## 实现说明

### 飞书机器人配置

需预先配置以下环境变量：

| 变量名 | 说明 |
|--------|------|
| `FEISHU_WEBHOOK_URL` | 飞书自定义机器人的 Webhook 地址 |

### 支持的 Markdown 语法

飞书消息卡片使用 `tag: "lark_md"` 元素，支持以下语法：

| 语法 | 写法 | 效果 |
|------|------|------|
| 粗体 | `**文本**` | **文本** |
| 斜体 | `*文本*` | *文本* |
| 删除线 | `~~文本~~` | ~~文本~~ |
| 链接 | `[显示文本](URL)` | 可点击链接 |
| 无序列表 | `- 项目` | 列表项 |
| 有序列表 | `1. 项目` | 编号列表 |
| 代码块 | ` ```语言\n代码\n``` ` | 带语法高亮的代码块 |

**注意**：
- 行内代码（单个反引号）和引用块（`>`）**不支持**
- 代码块必须使用三个反引号包裹，且建议指定语言以获得语法高亮（如 ` ```javascript`）

## 规则

- **只使用 `lark_md` tag 格式**，绝对不要用 `div` + `lark_md` 组合
- **不要嵌入外部图片 URL**（webhook 不支持）
- 代码块使用标准 markdown 反引号语法，在 `lark_md` 内容中直接使用
- 发送前**始终验证**卡片 JSON 结构是否正确

## 执行步骤

当用户调用此 skill 时，按以下步骤执行：

1. **检查环境变量**：确认 `FEISHU_WEBHOOK_URL` 环境变量已设置，否则提示错误，跳过下面步骤
2. **构造请求体**：根据优先级选择卡片颜色，使用飞书 interactive 卡片格式（`"tag": "lark_md"`）
3. **验证 JSON**：确认构造的 JSON 结构合法，确保 `elements` 中使用 `lark_md` tag、无外部图片 URL
4. **发送请求**：使用 curl 发送 POST 请求到 webhook URL
5. **检查结果**：如果返回报错，则提示异常原因并给出简要建议

### 优先级颜色映射

| 优先级 | 卡片颜色 |
|--------|----------|
| normal | 蓝色 (blue) |
| high | 橙色 (orange) |
| urgent | 红色 (red) |

### 请求体模板

```json
{
  "msg_type": "interactive",
  "card": {
    "config": {
      "wide_screen_mode": true
    },
    "header": {
      "title": {
        "tag": "plain_text",
        "content": "<标题>"
      },
      "template": "<颜色>"
    },
    "elements": [
      {
        "tag": "lark_md",
        "content": "<消息内容>"
      },
      {
        "tag": "note",
        "elements": [
          {
            "tag": "plain_text",
            "content": "发送时间: <YYYY-MM-DD HH:MM:SS>"
          }
        ]
      }
    ]
  }
}
```

### curl 命令示例

```bash
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')

curl -X POST "${FEISHU_WEBHOOK_URL}" \
  -H "Content-Type: application/json" \
  -d '{
    "msg_type": "interactive",
    "card": {
      "config": {
        "wide_screen_mode": true
      },
      "header": {
        "title": {"tag": "plain_text", "content": "Claude 通知"},
        "template": "blue"
      },
      "elements": [
        {"tag": "lark_md", "content": "消息内容"},
        {
          "tag": "note",
          "elements": [
            {"tag": "plain_text", "content": "发送时间: '"${CURRENT_TIME}"'"}
          ]
        }
      ]
    }
  }'
```

## 错误处理

- 如 `FEISHU_WEBHOOK_URL` 未设置，提示用户
- 如发送失败，显示错误信息，并给出简要建议
- 发送成功后，简要确认已发送

