---
title: dnspod
description: 管理 DNSPod（腾讯云 DNS）域名解析记录，支持查询、创建、修改、删除和启停解析记录。当用户需要管理 DNS 记录、操作域名解析、查看解析列表时触发。
author: Felix021
version: 1.0.0
tools:
  - Bash
---

# dnspod

通过腾讯云 DNSPod API 管理域名解析记录。使用 `DNSPOD_ID`（SecretId）和 `DNSPOD_KEY`（SecretKey）环境变量进行认证。

## 何时使用

- 用户要求查看、添加、修改或删除 DNS 解析记录
- 用户提到域名解析、DNS 记录、DNSPod 等关键词
- 需要启用或禁用某条 DNS 记录

## 环境变量

| 变量名 | 说明 |
|--------|------|
| `DNSPOD_ID` | 腾讯云 SecretId（以 `AKID` 开头） |
| `DNSPOD_KEY` | 腾讯云 SecretKey |

## 执行步骤

1. **检查环境变量**：确认 `DNSPOD_ID` 和 `DNSPOD_KEY` 已设置，否则提示用户配置
2. **解析用户意图**：根据用户需求确定操作类型
3. **构造参数**：提取域名、子域名、记录类型、记录值等参数

   **域名拆分规则**：用户给出的 FQDN（如 `sg.x.felix021.cn`）需要拆分为 `<domain>` 和 `<sub_domain>`。通过 `list-domains` 获取用户拥有的域名列表，然后匹配最长的后缀来确定 domain，剩余部分为 sub_domain。
   - 例：用户域名包含 `test.com` → `x.y.test.com` 拆为 domain=`test.com`, sub_domain=`x.y`
   - 例：`www.test.com` 拆为 domain=`test.com`, sub_domain=`www`
   - 例：`test.com` 拆为 domain=`test.com`, sub_domain=`@`
4. **执行命令**：调用 Python 脚本 `scripts/dnspod.py`（相对于本 skill 所在目录）
5. **展示结果**：格式化输出返回信息，如有错误则说明原因

## 支持的操作

### 列出域名

```bash
python3 <skill_dir>/scripts/dnspod.py list-domains
```

### 查询解析记录

```bash
# 查看域名下所有记录
python3 <skill_dir>/scripts/dnspod.py list-records <domain>

# 筛选子域名
python3 <skill_dir>/scripts/dnspod.py list-records <domain> <sub_domain>

# 筛选记录类型（A/CNAME/MX/TXT/NS/AAAA/SRV 等）
python3 <skill_dir>/scripts/dnspod.py list-records <domain> <sub_domain> A
```

### 创建解析记录

```bash
python3 <skill_dir>/scripts/dnspod.py create-record <domain> <sub_domain> <type> <value> [line] [ttl]

# 示例：添加 A 记录
python3 <skill_dir>/scripts/dnspod.py create-record example.com www A 1.2.3.4

# 示例：添加 CNAME 记录
python3 <skill_dir>/scripts/dnspod.py create-record example.com blog CNAME cdn.example.com

# 示例：指定解析线路和 TTL
python3 <skill_dir>/scripts/dnspod.py create-record example.com api A 5.6.7.8 默认 300
```

### 修改解析记录

```bash
python3 <skill_dir>/scripts/dnspod.py modify-record <domain> <record_id> <sub_domain> <type> <value> [line] [ttl]

# 示例：更新 A 记录 IP
python3 <skill_dir>/scripts/dnspod.py modify-record example.com 12345 www A 9.8.7.6
```

> 注意：修改记录需要先通过 `list-records` 获取 `record_id`。

### 删除解析记录

```bash
python3 <skill_dir>/scripts/dnspod.py delete-record <domain> <record_id>
```

> **警告**：删除操作不可恢复，执行前必须向用户确认。

### 启用/禁用解析记录

```bash
python3 <skill_dir>/scripts/dnspod.py toggle-record <domain> <record_id> enable
python3 <skill_dir>/scripts/dnspod.py toggle-record <domain> <record_id> disable
```

### 查看帮助

```bash
python3 <skill_dir>/scripts/dnspod.py help
```

> 也可通过 `/dnspod help` 调用，展示所有支持的命令、参数和示例。

## 规则

- **删除前确认**：执行 `delete-record` 前必须向用户确认
- **修改前查询**：执行 `modify-record` 前先 `list-records` 确认当前记录值
- **使用 @ 表示根域名**：当子域名与主域名相同时，使用 `@` 作为 SubDomain
- **记录类型大写**：记录类型统一使用大写（A, CNAME, MX, TXT, AAAA, NS, SRV 等）
- **解析线路默认值**：未指定解析线路时默认使用 `默认`
- **每次回复末尾附带用法示例**：每次执行完操作后，在回复末尾追加一个"用法示例"区块，列出常用操作命令，帮助用户了解后续可用操作

## 错误处理

- 环境变量未设置时，提示用户设置 `DNSPOD_ID` 和 `DNSPOD_KEY`
- API 返回错误时，解析 `Response.Error` 并展示给用户
- 参数缺失时，展示对应命令的用法说明
