# Olend DeFi 借贷平台开发 - 阶段二会话 Prompt

## 项目背景
Olend 是一个基于 Sui Network 的去中心化借贷平台，使用 Sui Move 智能合约语言开发。这是一个支持10亿美元以上资金规模的企业级DeFi平台，严谨和安全是第一原则。

## 当前开发状态 ✅

### 已完成的核心模块（100%测试通过）：
- **Vault 系统** (`sources/vault.move`) - 统一流动性管理，ERC-4626兼容，Shared Object架构
- **Account 系统** (`sources/account.move`) - 用户账户管理，积分等级系统，权限控制
- **Registry 系统** (`sources/liquidity.move`) - 全局资产管理，每种资产一个Vault
- **YToken 系统** (`sources/ytoken.move`) - 份额凭证实现
- **Oracle 系统** (`sources/oracle.move`) - 价格预言机核心功能，支持缓存和验证
- **Pyth 集成** (`sources/pyth_adapter.move`) - 与 Pyth Network 的完整集成

### 系统质量指标：
- ✅ **测试通过率**: 100% (143/143 测试全部通过)
- ✅ **架构完整性**: Shared Object 设计，Package 权限控制
- ✅ **安全性**: 多层安全机制，严格的错误处理
- ✅ **依赖管理**: Pyth 和 Wormhole 依赖已正确配置

## 下一阶段任务目标 🎯

根据 `.kiro/specs/olend-defi-platform/tasks.md` 实施计划，现在需要开始**阶段二：借贷核心功能**的开发：

### 优先任务列表：
1. **任务 4.1-4.7** - 借贷池管理系统实现
2. **任务 5.1-5.7** - 借款池管理系统实现

## 核心架构原则 🏗️

### Vault 作为 Shared Object 的设计模式：
```move
// 正确的使用模式
public fun deposit<T>(
    pool: &mut LendingPool<T>,
    vault: &mut Vault<T>,      // Vault 作为参数传入
    account_cap: &AccountCap,
    asset: Coin<T>,
    ctx: &mut TxContext
): YToken<T> {
    // 1. 验证用户权限
    // 2. 调用 vault::deposit() (package权限)
    // 3. 更新 pool 的统计数据
    // 4. 更新用户积分
    // 5. 返回 YToken
}
```

### 关键设计原则：
- **统一流动性**：每种资产只有一个 Vault<T> 作为 Shared Object
- **业务分离**：Pool 只记录业务逻辑，真实资产在 Vault<T> 中
- **权限控制**：Vault 的资产操作方法都是 `public(package)` 权限
- **用户激励**：完整的积分和等级系统集成

## 待实现的核心功能 📋

### 4. 借贷池管理系统 (LendingPool)
- **核心功能**：存款赚取利息，支持动态和固定利率模型
- **关键特性**：
  - 与统一 Vault<T> 系统集成
  - 用户积分和等级系统深度集成
  - 利率模型：动态利率 = 基础利率 + 利用率 × 利率斜率
  - 收益分配：70%返还用户，10%开发团队，10%保险基金，10%国库
  - 多池策略支持（同一资产可有多个不同策略的池子）

### 5. 借款池管理系统 (BorrowingPool)
- **核心功能**：高抵押率借款（高达97%），多资产抵押支持
- **关键特性**：
  - 与 Oracle 系统集成进行实时价格计算
  - 支持 YToken 作为抵押物
  - 多阈值管理：初始抵押率、警告抵押率、清算抵押率
  - 借款期限管理：不定期和定期借款
  - 为后续 Tick 清算机制预留接口

## 技术要求 🔧

### 开发标准：
1. **严格测试**：每个 public 函数都必须有对应的测试用例
2. **安全优先**：所有资金操作都要有严格的权限控制和错误处理
3. **性能优化**：支持高并发操作，优化批量处理
4. **代码质量**：遵循现有代码风格，添加充分的注释

### 集成要求：
- **与 Vault 集成**：通过 Registry 获取 Vault 引用，使用 package 权限调用
- **与 Account 集成**：通过 AccountCap 验证身份，更新积分和等级
- **与 Oracle 集成**：获取实时价格进行抵押率计算和风险评估
- **事件发射**：记录所有重要操作用于监控和审计

## 文件结构 📁

### 需要创建的文件：
```
sources/
├── lending_pool.move       # 借贷池管理系统
├── borrowing_pool.move     # 借款池管理系统

tests/
├── test_lending_pool.move      # 借贷池测试
├── test_borrowing_pool.move    # 借款池测试
├── test_integration.move       # 集成测试（可选）
```

### 现有文件（可参考）：
- `sources/vault.move` - Vault 系统实现参考
- `sources/account.move` - Account 系统集成参考
- `sources/oracle.move` - Oracle 系统集成参考
- `tests/test_vault.move` - 测试模式参考

## 成功标准 ✅

### 功能完整性：
- [ ] LendingPool 支持存取资产，利率计算，收益分配
- [ ] BorrowingPool 支持高抵押率借款，多资产抵押，风险管理
- [ ] 完整的用户积分和等级系统集成
- [ ] 与现有系统无缝集成

### 质量标准：
- [ ] 所有测试通过（目标：保持100%通过率）
- [ ] 代码覆盖率 ≥ 90%
- [ ] 无安全漏洞
- [ ] 性能满足高并发要求

## 开发指导 💡

### 开始建议：
1. **先阅读现有代码**：理解 Vault、Account、Oracle 的实现模式
2. **从 LendingPool 开始**：相对简单，为 BorrowingPool 奠定基础
3. **渐进式开发**：先实现核心功能，再添加高级特性
4. **持续测试**：每完成一个功能就编写测试

### 关键注意事项：
- **资金安全**：所有资金操作必须是原子性的
- **权限验证**：严格验证用户身份和操作权限
- **错误处理**：提供清晰的错误信息和恢复机制
- **事件记录**：记录所有重要操作用于审计

## 项目愿景 🚀

通过这个阶段的开发，Olend 将具备完整的借贷功能，成为一个功能完整、安全可靠的 DeFi 借贷平台，为用户提供：
- 高资本效率的统一流动性
- 高达97%的借贷价值比
- 70%的收益返还给用户
- 完整的用户激励系统

---

**开始开发时，请确认你理解了项目背景和当前任务，然后从任务 4.1 开始实施。记住要使用 `taskStatus` 工具更新任务进度！**