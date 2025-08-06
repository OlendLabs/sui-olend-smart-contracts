# Olend DeFi 借贷平台需求文档

## 介绍

Olend 是一个基于 Sui Network 的去中心化借贷平台，使用 Sui Move 智能合约语言开发。该平台提供统一流动性管理、高效清算机制和多样化的借贷产品，旨在为用户提供极高的资本效率和安全的借贷体验。

平台核心特点包括：
- 统一流动性金库，同一资产共用一个金库，提升资本效率
- 基于 Tick 的批量清算机制，实现低清算罚金（低至0.1%）和高借贷价值比（高达97%）
- 兼容 ERC-4626 标准的金库设计
- 支持动态和固定利率的多样化借贷产品
- 完善的风险管理和治理机制

## 需求

### 需求 1 - 统一流动性管理系统

**用户故事：** 作为平台用户，我希望能够将资产存入统一的流动性金库并获得相应的份额凭证，以便实现高效的资产管理和流动性共享。

#### 验收标准

##### Registry 管理需求
1. WHEN 平台初始化 THEN 系统 SHALL 创建一个全局的 Registry Share object 作为主对象
2. WHEN 需要为资产类型创建 Vault THEN Registry SHALL 支持每种资产类型最多创建一个 Vault<T> 实例
3. WHEN 记录资产的 Vault 映射 THEN Registry SHALL 维护资产类型到单个 Vault<T> 的直接映射关系
4. WHEN 查询特定资产的 Vault THEN Registry SHALL 返回该资产类型对应的唯一 Vault<T> 实例（如果存在且活跃）
5. WHEN 查询特定资产的默认 Vault THEN Registry SHALL 返回该资产类型的唯一 Vault<T> 实例（如果活跃）
6. WHEN 现有 Vault 出现问题 THEN Registry SHALL 支持将该 Vault 标记为非活跃状态
7. WHEN 需要替换问题 Vault THEN 系统 SHALL 要求先删除现有 Vault 才能创建新的 Vault<T>
8. WHEN 尝试为已有 Vault 的资产创建新 Vault THEN Registry SHALL 拒绝创建并返回错误
9. WHEN 系统升级 THEN Registry SHALL 通过 version 字段控制对所有 Vault 的访问权限
10. WHEN Registry 版本更新 THEN 系统 SHALL 禁止旧版本的方法调用并要求 Share object 升级

##### Vault<T> 核心功能需求
11. WHEN 用户存入某种资产 THEN 系统 SHALL 通过 Registry 查找该资产的唯一 Vault<T>
12. WHEN 用户存入资产 THEN 系统 SHALL 验证该 Vault 处于活跃状态并允许存入
13. WHEN 用户存入资产到 Vault<T> THEN 系统 SHALL 根据当前汇率计算并铸造相应数量的 YToken<T> 份额凭证
14. WHEN 用户赎回资产 THEN 系统 SHALL 根据 YToken<T> 份额和当前汇率计算并返回相应数量的底层资产
15. WHEN 计算份额汇率 THEN Vault<T> SHALL 使用公式：汇率 = 总资产价值 / 总份额数量
16. WHEN Vault<T> 中资产价值发生变化 THEN 系统 SHALL 自动更新汇率以反映利息累积
17. WHEN Vault<T> 被标记为非活跃 THEN 系统 SHALL 阻止新的资产存入但允许现有用户提取资产

##### ERC-4626 兼容性需求
11. WHEN 实现 Vault<T> THEN 系统 SHALL 遵循 ERC-4626 标准的接口设计
12. WHEN 用户调用 deposit 函数 THEN 系统 SHALL 接收资产并返回相应的份额数量
13. WHEN 用户调用 withdraw 函数 THEN 系统 SHALL 销毁份额并返回相应的资产数量
14. WHEN 查询 Vault 状态 THEN 系统 SHALL 提供 totalAssets、totalSupply、convertToShares、convertToAssets 等标准查询函数

##### 安全和风控需求
18. WHEN 触发紧急情况 THEN Vault<T> SHALL 支持暂停所有 deposit 和 withdraw 操作
19. WHEN Vault<T> 出现安全问题 THEN 管理员 SHALL 能够将该 Vault 设置为非活跃状态阻止资产进入但保持资产提取功能
20. WHEN Vault<T> 被设置为非活跃 THEN Registry SHALL 在查询时不返回该 Vault 并停止向其导流新资产
21. WHEN 需要替换问题 Vault THEN 系统 SHALL 要求先删除现有 Vault 才能创建新的 Vault<T>
22. WHEN 设置每日取出限额 THEN Vault<T> SHALL 记录每日已提取金额并在达到限额时阻止进一步提取
23. WHEN 新的一天开始 THEN 系统 SHALL 自动重置每日提取限额计数器
24. WHEN 系统升级 THEN 每个 Vault<T> SHALL 通过 version 字段控制访问权限并禁止旧版本方法调用

##### 模块间交互需求
25. WHEN lending 模块需要资产操作 THEN 系统 SHALL 通过 Registry 获取该资产的唯一 Vault 并仅通过 Vault<T> 的 deposit 函数进行资产存入
26. WHEN borrowing 模块需要借出资产 THEN 系统 SHALL 通过 Registry 获取该资产的唯一 Vault 并仅通过 Vault<T> 的 borrow 函数进行资产借出
27. WHEN borrowing 模块需要还款 THEN 系统 SHALL 仅通过对应资产的 Vault<T> 的 repay 函数进行资产归还
28. WHEN lending 模块需要提取资产 THEN 系统 SHALL 仅通过 Vault<T> 的 withdraw 函数进行资产提取（基于用户持有的 YToken 对应的 Vault）
29. WHEN 其他模块调用 Vault<T> 函数 THEN 系统 SHALL 验证调用者具有 package 级别的访问权限
30. WHEN 选择 Vault 进行操作 THEN 系统 SHALL 使用 Registry 中该资产类型对应的唯一 Vault

##### 数据一致性需求
31. WHEN 多个操作同时访问同一 Vault<T> THEN 系统 SHALL 确保操作的原子性和数据一致性
32. WHEN Vault<T> 状态发生变化 THEN Registry SHALL 保持对该 Vault 引用的有效性
33. WHEN 查询 Vault<T> 的总资产 THEN 系统 SHALL 实时计算包括借出资产在内的所有资产价值
34. WHEN 每种资产只有一个 Vault THEN 系统 SHALL 确保该 Vault 的数据完整性和状态一致性
35. WHEN 需要替换 Vault THEN 系统 SHALL 提供安全的 Vault 替换机制（需要先清空旧 Vault）

### 需求 2 - 账户管理系统

**用户故事：** 作为平台用户，我希望有一个统一的账户系统来管理我的所有头寸、等级和积分信息，并支持子账户管理和额度授权，为后续的借贷操作提供身份验证和权限控制。

#### 验收标准

##### AccountRegistry 全局管理需求
1. WHEN 平台初始化 THEN 系统 SHALL 创建一个全局的 AccountRegistry Share object 作为账户管理的主对象
2. WHEN 用户首次使用平台 THEN AccountRegistry SHALL 为用户创建唯一的 Account 对象和对应的 AccountCap 凭证
3. WHEN 创建新账户 THEN AccountRegistry SHALL 为每个 Account 分配唯一的账户ID并维护账户ID到Account对象的映射
4. WHEN 查询用户账户 THEN AccountRegistry SHALL 提供通过账户ID或AccountCap快速查找Account的机制
5. WHEN 系统需要验证账户存在性 THEN AccountRegistry SHALL 提供账户验证接口
6. WHEN 系统升级 THEN AccountRegistry SHALL 通过 version 字段控制访问权限并支持账户数据迁移

##### Account 核心功能需求
7. WHEN Account 被创建 THEN 系统 SHALL 初始化用户等级、积分和头寸ID列表等基础信息
8. WHEN 用户创建新的借贷头寸 THEN Account SHALL 将头寸ID添加到头寸ID列表中，但不存储头寸详情
9. WHEN 用户关闭头寸 THEN Account SHALL 从头寸ID列表中移除对应的头寸ID
10. WHEN 查询用户头寸 THEN Account SHALL 提供头寸ID列表，具体头寸详情由相应的借贷模块提供
11. WHEN 用户进行平台活动 THEN Account SHALL 更新用户等级和积分信息
12. WHEN 计算用户权益 THEN Account SHALL 基于等级和积分提供相应的平台权益和费率优惠

##### AccountCap 权限控制需求
13. WHEN AccountCap 被创建 THEN 系统 SHALL 将其设计为不可转让的 Owned object 确保账户安全
14. WHEN 用户进行任何账户相关操作 THEN 系统 SHALL 通过 AccountCap 验证用户身份和权限
15. WHEN 验证账户权限 THEN 系统 SHALL 确保 AccountCap 与对应的 Account 匹配
16. WHEN AccountCap 丢失或损坏 THEN 系统 SHALL 提供安全的账户恢复机制（如果技术上可行）

##### 子账户管理需求
17. WHEN 用户需要创建子账户 THEN Account SHALL 支持创建多个子账户（SubAccount）
18. WHEN 创建子账户 THEN 系统 SHALL 为子账户分配唯一ID并建立与主账户的关联关系
19. WHEN 子账户被创建 THEN 系统 SHALL 为子账户创建对应的 SubAccountCap 权限凭证
20. WHEN 管理子账户 THEN 主账户 SHALL 能够查看和管理所有子账户的状态和权限
21. WHEN 子账户操作 THEN 系统 SHALL 通过 SubAccountCap 验证子账户的操作权限
22. WHEN 子账户创建头寸 THEN 子账户的头寸ID SHALL 同时记录在子账户和主账户的头寸列表中

##### 额度授权管理需求
23. WHEN 主账户对子账户进行额度授权 THEN 系统 SHALL 记录每个子账户在不同资产上的授权额度
24. WHEN 设置子账户额度 THEN 主账户 SHALL 能够为子账户设置借贷额度、交易额度等不同类型的额度限制
25. WHEN 子账户进行操作 THEN 系统 SHALL 验证操作金额不超过主账户设置的授权额度
26. WHEN 子账户额度不足 THEN 系统 SHALL 阻止子账户的超额操作并提供明确的错误信息
27. WHEN 主账户修改子账户额度 THEN 系统 SHALL 立即生效并影响子账户后续操作
28. WHEN 查询子账户额度 THEN 系统 SHALL 提供已使用额度和剩余额度的实时信息

##### 权限层级管理需求
29. WHEN 定义账户权限 THEN 系统 SHALL 建立主账户 > 子账户的权限层级关系
30. WHEN 子账户尝试创建子账户 THEN 系统 SHALL 根据权限设置决定是否允许（可配置的层级深度）
31. WHEN 权限冲突 THEN 系统 SHALL 以主账户的权限设置为准
32. WHEN 主账户被暂停 THEN 系统 SHALL 同时暂停所有关联的子账户

##### 数据一致性和安全需求
33. WHEN 多个子账户同时操作 THEN 系统 SHALL 确保额度检查和扣减的原子性
34. WHEN 账户数据更新 THEN 系统 SHALL 确保主账户和子账户数据的一致性
35. WHEN 借贷模块需要用户验证 THEN 账户系统 SHALL 提供统一的身份验证和权限控制接口
36. WHEN 账户系统与其他模块交互 THEN 系统 SHALL 确保账户数据的隐私性和安全性

### 需求 3 - 预言机集成系统

**用户故事：** 作为系统，我需要准确的价格数据来计算抵押率、清算条件和资产价值，以确保平台的安全运行。

#### 验收标准

1. WHEN 系统需要资产价格 THEN 系统 SHALL 通过 Pyth 预言机获取实时价格数据
2. WHEN 价格数据更新 THEN 系统 SHALL 自动重新计算所有相关的抵押率和头寸状态
3. WHEN 预言机数据异常 THEN 系统 SHALL 有备用机制确保平台安全运行

### 需求 4 - 借贷池管理系统

**用户故事：** 作为借贷用户，我希望能够在多个借贷池中存入资产赚取利息，并根据不同的利率模式和期限选择最适合的借贷产品。

#### 验收标准

1. WHEN 用户存入资产到 LendingPool<T> THEN 系统 SHALL 通过账户系统验证用户身份并铸造相应的 YToken<T> 份额凭证
2. WHEN 用户提取资产 THEN 系统 SHALL 根据线性时间计算的资产价值确定提取数量
3. WHEN 发生任何资产相关操作 THEN 系统 SHALL 自动计算并累积利息到资产价值中
4. WHEN 用户尝试提取抵押中的资产 THEN 系统 SHALL 验证提取后抵押率不会进入危险状态
5. WHEN 平台需要支持同一资产的多个池子 THEN 系统 SHALL 允许创建多个 LendingPool<T> 实例

### 需求 5 - 借款池管理系统

**用户故事：** 作为借款用户，我希望能够使用我的存款凭证作为抵押物借出其他资产，并在不同的利率模式和借款期限中进行选择。

#### 验收标准

1. WHEN 用户提供 YToken 抵押物借款 THEN 系统 SHALL 通过账户系统验证身份、预言机计价并创建或更新借款头寸
2. WHEN 借款池采用动态利率 THEN 系统 SHALL 根据资金利用率动态调整借款利率
3. WHEN 借款池采用固定利率 THEN 系统 SHALL 在有借款发生后锁定利率不可修改
4. WHEN 用户选择不定期借款 THEN 系统 SHALL 允许借款持续存在直到触发清算条件
5. WHEN 用户选择定期借款 THEN 系统 SHALL 设置明确的到期时间限制
6. WHEN 用户还款 THEN 系统 SHALL 先计算利息再处理还款并支持部分还款
7. WHEN 设置抵押率 THEN 系统 SHALL 根据资产波动性设置不同的最高抵押率（如 BTC 可达90%以上）
8. WHEN 需要清算 THEN 系统 SHALL 将相同抵押率的头寸组织在一起进行批量清算

**用户故事：** 作为平台用户，我希望有一个统一的账户系统来管理我的所有头寸、等级和积分信息。

#### 验收标准

1. WHEN 用户首次使用平台 THEN 系统 SHALL 创建 Account 对象和对应的 AccountCap 凭证
2. WHEN 用户进行操作 THEN 系统 SHALL 通过 AccountCap 验证用户身份和权限
3. WHEN 用户积累活动 THEN 系统 SHALL 更新用户等级和积分信息
4. WHEN 查询用户信息 THEN AccountRegistry SHALL 提供所有用户头寸和账户详情的统一视图
5. WHEN 涉及安全考虑 THEN AccountCap SHALL 设计为不可转让的 Owned object

### 需求 6 - 高效清算系统

**用户故事：** 作为平台，我需要一个高效的清算机制来管理风险头寸，确保平台的偿付能力和稳定性。

#### 验收标准

1. WHEN 头寸达到清算条件 THEN 系统 SHALL 基于 Tick 机制在同一价格范围内批量清算多个头寸
2. WHEN 执行清算 THEN 系统 SHALL 实现低清算罚金（低至0.1%）和高借贷价值比（高达97%）
3. WHEN 进行阶梯式清算 THEN 系统 SHALL 每次清算10%或调整至安全抵押率区域
4. WHEN 清算抵押资产 THEN 系统 SHALL 将 YToken 对应资产与借款资产配对到外部 DEX（如 DEEPBook、Cetus、Bluefin）
5. WHEN 清算完成 THEN 系统 SHALL 更新相关头寸状态并分配清算奖励
6. WHEN 清算操作执行 THEN 系统 SHALL 通过账户系统记录和更新用户头寸状态

### 需求 7 - 多角色权限管理系统

**用户故事：** 作为不同角色的参与者，我希望根据我的角色获得相应的权限和收益分配。

#### 验收标准

1. WHEN 开发团队部署和维护平台 THEN 系统 SHALL 分配10%的平台收益作为研发团队运营费用
2. WHEN 平台运营者设置参数 THEN 系统 SHALL 允许其配置平台策略和创建必要的初始对象
3. WHEN 出借人使用平台 THEN 系统 SHALL 主要通过 lending 模块的 deposit 和 withdraw 函数提供服务
4. WHEN 借款人使用平台 THEN 系统 SHALL 主要通过 borrowing 模块的 borrow 和 repay 函数提供服务
5. WHEN 平台出现风险或损失 THEN 系统 SHALL 使用10%的风险基金进行损失补偿

### 需求 8 - 测试和质量保证系统

**用户故事：** 作为开发团队，我需要确保所有模块都经过充分测试，包括正常流程和边界情况的处理。

#### 验收标准

1. WHEN 开发任何 public 函数 THEN 开发者 SHALL 编写对应的正常流程测试用例
2. WHEN 开发任何 public 函数 THEN 开发者 SHALL 编写边界情况和失败场景的测试用例
3. WHEN 运行测试套件 THEN 所有测试 SHALL 通过并覆盖主要功能路径
4. WHEN 部署前 THEN 系统 SHALL 通过完整的集成测试验证各模块间的交互