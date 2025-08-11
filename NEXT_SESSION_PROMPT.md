# 下一个会话任务：实现多资产抵押支持（任务5.4）

## 任务概述

请继续实现Olend DeFi借贷平台的任务5.4：**实现多资产抵押支持**。

## 当前状态

- ✅ 任务5.3"实现高抵押率管理"已完成
- 🎯 下一个任务：5.4"实现多资产抵押支持"

## 任务5.4具体要求

根据 `.kiro/specs/olend-defi-platform/tasks.md` 中的定义：

```markdown
- [ ] 5.4 实现多资产抵押支持
  - 支持多种 YToken 作为抵押物
  - 实现加权平均方法计算综合抵押率
  - 实现多资产价格波动的实时监控
  - 实现抵押组合的动态调整功能
  - _需求: 5.35, 5.36, 5.37, 5.38_
```

## 相关需求（来自requirements.md）

**需求5.35**: 用户提供多种 YToken 作为抵押时，系统应支持多资产组合抵押并计算总抵押价值
**需求5.36**: 计算多资产抵押率时，系统应使用加权平均方法计算综合抵押率
**需求5.37**: 多资产价格波动时，系统应分别监控每种抵押资产的价格变化对总抵押率的影响
**需求5.38**: 用户调整抵押组合时，系统应支持增加、减少或替换特定类型的抵押资产

## 当前实现状态分析

### 现有单资产抵押实现
当前 `sources/borrowing_pool.move` 中的实现：

1. **BorrowPosition结构体**：目前只支持单一抵押资产
   ```move
   public struct BorrowPosition has key, store {
       collateral_amount: u64,        // 单一抵押数量
       collateral_type: TypeName,     // 单一抵押类型
       collateral_holder_id: ID,      // 单一抵押持有者ID
       collateral_vault_id: ID,       // 单一抵押库ID
       // ...
   }
   ```

2. **CollateralHolder结构体**：目前只能持有单一类型的抵押物
   ```move
   public struct CollateralHolder<phantom C> has key, store {
       collateral: balance::Balance<YToken<C>>,  // 单一类型抵押物
       // ...
   }
   ```

3. **借款函数**：目前只接受单一抵押物
   ```move
   public fun borrow<T, C>(
       collateral: Coin<YToken<C>>,  // 单一抵押物
       // ...
   )
   ```

## 需要实现的功能

### 1. 多资产抵押数据结构

需要扩展或重新设计以下结构：

#### 1.1 多资产抵押持有者
```move
// 新的多资产抵押持有者结构
public struct MultiCollateralHolder has key, store {
    id: UID,
    position_id: ID,
    // 存储多种类型的抵押物 - 需要设计合适的数据结构
    collaterals: Table<TypeName, CollateralInfo>,
}

public struct CollateralInfo has store {
    amount: u64,
    vault_id: ID,
    // 其他必要信息
}
```

#### 1.2 扩展BorrowPosition
```move
// 扩展现有BorrowPosition以支持多资产
public struct BorrowPosition has key, store {
    // ... 现有字段 ...
    // 替换单一抵押字段为多资产支持
    multi_collateral_holder_id: option::Option<ID>,
    collateral_types: vector<TypeName>,
    total_collateral_value_usd: u64,  // 总抵押价值（USD）
}
```

### 2. 多资产抵押率计算

#### 2.1 加权平均抵押率计算
```move
public fun calculate_multi_asset_ltv<T>(
    pool: &BorrowingPool<T>,
    position: &BorrowPosition,
    multi_collateral_holder: &MultiCollateralHolder,
    vaults: &vector<&Vault<_>>,  // 多个vault引用
    oracle: &PriceOracle,
    clock: &Clock,
): u64
```

#### 2.2 单个资产对总抵押率的贡献计算
```move
public fun calculate_asset_contribution<T, C>(
    asset_amount: u64,
    asset_price: u64,
    total_collateral_value: u64,
): u64
```

### 3. 多资产借款功能

#### 3.1 多资产借款函数
```move
public fun borrow_with_multi_collateral<T>(
    pool: &mut BorrowingPool<T>,
    borrow_vault: &mut Vault<T>,
    account: &mut Account,
    account_cap: &AccountCap,
    collaterals: vector<CollateralInput>,  // 多种抵押物输入
    borrow_amount: u64,
    oracle: &PriceOracle,
    clock: &Clock,
    ctx: &mut TxContext
): (Coin<T>, BorrowPosition)

public struct CollateralInput {
    coin: Coin<YToken<_>>,  // 需要处理泛型
    vault_ref: &Vault<_>,
}
```

### 4. 抵押组合管理

#### 4.1 添加抵押物
```move
public fun add_collateral<T, C>(
    pool: &mut BorrowingPool<T>,
    position: &mut BorrowPosition,
    multi_collateral_holder: &mut MultiCollateralHolder,
    additional_collateral: Coin<YToken<C>>,
    collateral_vault: &Vault<C>,
    oracle: &PriceOracle,
    clock: &Clock,
)
```

#### 4.2 减少抵押物
```move
public fun reduce_collateral<T, C>(
    pool: &mut BorrowingPool<T>,
    position: &mut BorrowPosition,
    multi_collateral_holder: &mut MultiCollateralHolder,
    asset_type: TypeName,
    reduce_amount: u64,
    collateral_vault: &Vault<C>,
    oracle: &PriceOracle,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<YToken<C>>
```

### 5. 实时监控和风险管理

#### 5.1 多资产价格监控
```move
public fun monitor_multi_asset_risk<T>(
    pool: &BorrowingPool<T>,
    position: &BorrowPosition,
    multi_collateral_holder: &MultiCollateralHolder,
    vaults: &vector<&Vault<_>>,
    oracle: &PriceOracle,
    clock: &Clock,
)
```

#### 5.2 单个资产价格变化影响分析
```move
public fun analyze_asset_price_impact<T, C>(
    position: &BorrowPosition,
    asset_type: TypeName,
    old_price: u64,
    new_price: u64,
    total_collateral_value: u64,
): (u64, u64)  // (new_ltv, impact_percentage)
```

## 技术挑战和解决方案

### 1. 泛型类型处理
- **挑战**: Move语言中处理多种泛型类型的复杂性
- **解决方案**: 使用TypeName作为键，结合动态类型检查

### 2. 数据结构设计
- **挑战**: 如何高效存储和管理多种类型的抵押物
- **解决方案**: 使用Table<TypeName, CollateralInfo>结构

### 3. 计算复杂性
- **挑战**: 多资产抵押率计算的复杂性和精度
- **解决方案**: 分步计算，使用高精度数学运算

## 测试要求

需要创建全面的测试套件：

1. **多资产抵押基础功能测试**
2. **加权平均抵押率计算测试**
3. **抵押组合动态调整测试**
4. **多资产价格波动监控测试**
5. **边界条件和异常情况测试**

## 实现步骤建议

1. **第一步**: 设计和实现多资产数据结构
2. **第二步**: 实现多资产抵押率计算逻辑
3. **第三步**: 扩展借款功能支持多资产
4. **第四步**: 实现抵押组合管理功能
5. **第五步**: 实现实时监控和风险管理
6. **第六步**: 编写全面的测试套件
7. **第七步**: 集成测试和优化

## 注意事项

1. **向后兼容性**: 确保新的多资产功能不破坏现有的单资产功能
2. **性能优化**: 多资产计算可能比较复杂，需要注意性能
3. **安全性**: 多资产抵押增加了攻击面，需要额外的安全检查
4. **用户体验**: 多资产操作应该对用户友好且直观

## 开始实现

请从任务5.4开始实现，按照上述分析和建议进行开发。记住要：

1. 先更新任务状态为"in_progress"
2. 逐步实现各个功能模块
3. 为每个功能编写相应的测试
4. 确保代码质量和安全性
5. 完成后更新任务状态为"completed"

祝你实现顺利！