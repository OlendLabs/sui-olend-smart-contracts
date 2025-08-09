# Olend DeFi 借贷平台开发 - Phase 2 会话 Prompt

## 项目背景

你正在开发 Olend DeFi 借贷平台，这是一个基于 Sui Network 的去中心化借贷平台，使用 Sui Move 智能合约语言开发。

**当前状态**: Phase 1 核心基础设施已完成，现在开始 Phase 2 - DeFi 核心功能开发

## Phase 1 已完成的核心模块

### ✅ 完整实现的模块：
- **Vault 系统** (`sources/vault.move`)：ERC-4626 兼容，Shared Object 架构，手续费系统，每日限额
- **Account 系统** (`sources/account.move`)：用户管理，积分等级系统，安全积分扣减
- **YToken 系统** (`sources/ytoken.move`)：安全的份额凭证，防外部铸币
- **Registry 系统** (`sources/liquidity.move`)：统一 Vault 管理，单资产单 Vault 策略
- **基础设施**：错误处理、常量管理、工具函数
- **测试框架**：131 个测试，100% 通过率，90%+ 覆盖率

### 🎯 核心技术特点：
- **统一流动性管理**：每种资产一个 Vault<T> 作为 Shared Object
- **高安全性**：Package 级权限控制，多级紧急机制
- **手续费系统**：0-100% 可配置的存款/提取费用
- **完整账户系统**：积分、等级、头寸跟踪
- **ERC-4626 兼容**：标准化的 Vault 接口

## Phase 2 开发目标

### 🚧 当前任务：预言机集成系统

根据 `.kiro/specs/olend-defi-platform/tasks.md` 中的任务 2.1-2.7，需要实现：

#### 优先任务列表：
1. **任务 2.1**：创建 PriceOracle 核心模块
2. **任务 2.2**：集成 Sui 上的 Pyth Network
3. **任务 2.3**：实现价格数据管理
4. **任务 2.4**：实现多资产价格支持
5. **任务 2.5**：实现价格精度和格式处理
6. **任务 2.6**：实现安全和容错机制
7. **任务 2.7**：编写预言机系统测试

### 📋 后续计划：
- **阶段二**：借贷池管理系统 (LendingPool)
- **阶段三**：借款池管理系统 (BorrowingPool)
- **阶段四**：清算系统和治理系统

## 重要架构原则

### Vault 作为 Shared Object 的设计：
```move
// Vault 是 Shared Object，通过参数传入
public fun deposit<T>(
    pool: &mut LendingPool<T>,
    vault: &mut Vault<T>,  // Vault 作为参数传入
    account_cap: &AccountCap,
    asset: Coin<T>,
    ctx: &mut TxContext
): YToken<T>
```

### Package 权限控制：
- Vault 的资产操作方法都是 `public(package)` 权限
- 只有平台内的其他模块可以调用这些方法
- 用户必须通过 Pool 的业务逻辑进行操作

### 预言机集成要求：
- 使用 Pyth Network 作为主要价格源
- 支持多资产价格（BTC、ETH、SUI、USDC、USDT）
- 8位小数精度的统一价格格式
- 价格数据时效性和置信度验证
- 多层安全机制和异常处理

## 当前代码状态

### 文件结构：
```
sources/
├── account.move          # ✅ 已完成 - 账户管理系统
├── constants.move        # ✅ 已完成 - 常量定义
├── errors.move          # ✅ 已完成 - 错误码定义
├── liquidity.move       # ✅ 已完成 - Registry 管理
├── utils.move           # ✅ 已完成 - 工具函数
├── vault.move           # ✅ 已完成 - Vault 系统
├── ytoken.move          # ✅ 已完成 - 份额凭证
├── oracle.move          # ❌ 需要创建 - 预言机集成
├── lending_pool.move    # ❌ 需要创建 - 借贷池管理
├── borrowing_pool.move  # ❌ 需要创建 - 借款池管理
└── governance.move      # ❌ 需要创建 - 治理系统

tests/
├── test_account.move    # ✅ 已完成
├── test_registry.move   # ✅ 已完成
├── test_vault.move      # ✅ 已完成
├── test_oracle.move     # ❌ 需要创建
└── ... (其他测试文件)
```

### 测试状态：
- **当前测试数**：131 个
- **通过率**：100%
- **覆盖率**：90%+
- **测试命令**：`sui move test`

## 开发指导原则

1. **渐进式开发**：基于现有代码进行扩展，不要重写已有功能
2. **保持测试覆盖**：每个新功能都要有对应的测试用例
3. **遵循现有代码风格**：保持与现有代码的一致性
4. **安全优先**：所有资金操作都要有严格的权限控制
5. **性能考虑**：优化批量操作和数据查询性能

## 关键依赖信息

### Move.toml 当前配置：
```toml
[package]
name = "olend"
version = "1.0.0"
edition = "2024.beta"

[dependencies]

[addresses]
olend = "0x0"
sui = "0x2"
```

### 需要添加的依赖：
- Pyth Network 预言机依赖（用于价格数据）
- 可能需要的外部 DEX 集成依赖

## 执行指导

### 开始前：
1. 仔细阅读 `.kiro/specs/olend-defi-platform/requirements.md` 了解详细需求
2. 查看 `.kiro/specs/olend-defi-platform/design.md` 了解技术设计
3. 检查 `.kiro/specs/olend-defi-platform/tasks.md` 确认当前任务
4. 查看 `PROJECT_STATUS.md` 了解项目当前状态

### 执行任务时：
1. 使用 `taskStatus` 工具更新任务状态
2. 先将任务状态设为 `in_progress`，完成后设为 `completed`
3. 每次只专注于一个任务，不要同时处理多个任务
4. 运行 `sui move test` 确保不破坏现有功能

### 代码开发：
1. 保持与现有代码风格的一致性
2. 添加充分的注释和文档
3. 确保所有 public 函数都有对应的测试用例
4. 遵循 Package 权限控制原则

## 成功标准

- 所有任务按计划完成
- 测试覆盖率保持在 90% 以上
- 代码通过安全审查
- 与现有系统无缝集成
- 性能满足高并发要求

## 重要提醒

1. **不要修改现有的核心模块**（vault.move, account.move 等），除非有明确的 bug 修复需求
2. **保持现有测试通过**：任何修改都不应该破坏现有的 131 个测试
3. **遵循 Shared Object 模式**：新的模块应该与 Vault 的 Shared Object 架构兼容
4. **使用现有的错误码和常量**：在 errors.move 和 constants.move 中添加新的定义

## 开始任务

请从任务 2.1 开始：**创建 PriceOracle 核心模块**

记住要使用 `taskStatus` 工具更新任务进度，并确保每个步骤都有充分的测试覆盖！

---

**项目状态**: Phase 1 完成 ✅ | Phase 2 开始 🚧  
**当前任务**: 2.1 创建 PriceOracle 核心模块  
**测试状态**: 131/131 通过 ✅  
**准备就绪**: 开始预言机集成开发 🚀