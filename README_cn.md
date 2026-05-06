# Chain Fate Arena 中文说明

Chain Fate Arena 是一个面向 **SC6107 Option 4: On-Chain Verifiable Random Game Platform** 的链上可验证随机游戏平台。项目使用 Solidity + Foundry 编写智能合约，使用 Vite + React + ethers v6 编写前端，并提供本地 Mock VRF 与 Chainlink VRF v2.5 Adapter 两种随机数路径。

项目实现了两个共享资金池的游戏：

- **Oracle Dice**：玩家先提交隐藏种子的哈希承诺，合约请求 VRF 风格随机数，随机数返回后玩家揭示种子，合约把 VRF 随机数和玩家种子混合生成骰子结果，并自动结算。
- **Epoch Raffle**：管理员创建限时抽奖轮次，玩家购买票并提交隐藏种子承诺，轮次关闭后请求随机数，玩家在揭示期内揭示种子，揭示期结束后合约自动选出中奖票并发放奖池。

## 1. 项目结构

```text
p6107/
├── src/
│   ├── ChainFateArena.sol                    # 核心游戏平台合约
│   ├── ChainlinkVRFCoordinatorAdapter.sol    # Chainlink VRF v2.5 适配器
│   ├── interfaces/IRandomnessCoordinator.sol # 随机数协调器接口
│   └── mocks/                                # 本地演示和测试用 Mock 合约
├── test/                                     # Foundry 测试
├── script/                                   # 部署脚本
├── frontend/                                 # React 前端
├── docs/                                     # 架构、安全、Gas、部署、用户指南等文档
├── foundry.toml
├── package.json
└── README.md
```

## 2. 环境依赖

需要提前安装：

- Foundry，包括 `forge`、`anvil`、`cast`
- Node.js 和 npm
- MetaMask 浏览器钱包

项目还依赖：

- OpenZeppelin Contracts 5.x
- Chainlink Contracts
- React、Vite、ethers v6、lucide-react

如果你是第一次克隆项目，需要安装合约和前端依赖：

```bash
cd p6107
npm ci
npm --prefix frontend ci
```

如果 `lib/openzeppelin-contracts/contracts/` 为空，需要补齐 OpenZeppelin 依赖。可以使用 Foundry 安装：

```bash
forge install OpenZeppelin/openzeppelin-contracts --no-git --shallow
```

安装后建议确认这些路径存在：

```text
lib/openzeppelin-contracts/contracts/
node_modules/@chainlink/contracts/
frontend/node_modules/
```

## 3. 常用命令

在 `p6107` 目录下执行：

```bash
forge build
forge test
forge coverage --report summary
npm --prefix frontend run build
```

也可以使用项目根目录 `package.json` 中的脚本：

```bash
npm run build
npm run test
npm run coverage
npm run frontend:build
npm run frontend:dev
npm run deploy:local
```

## 4. 本地启动流程

### 4.1 启动 Anvil 本地区块链

打开第一个终端：

```bash
cd p6107
anvil
```

Anvil 默认 RPC 地址是：

```text
http://127.0.0.1:8545
```

把 MetaMask 添加或切换到本地网络：

- Network name: Anvil Local
- RPC URL: `http://127.0.0.1:8545`
- Chain ID: `31337`
- Currency symbol: `SepoliaETH`

可以导入 Anvil 输出的本地测试私钥用于演示。

### 4.2 部署本地演示合约

打开第二个终端：

```bash
cd p6107
forge script script/DeployChainFateArena.s.sol:DeployChainFateArena \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

该脚本会部署并初始化：

- `MockVRFCoordinator`：本地 VRF 风格随机数协调器
- `ChainFateArena`：核心游戏平台合约
- `MockERC20`：演示用 FATE Token
- 1 个 SepoliaETH 抽奖轮次
- 1 个 FATE 抽奖轮次
- SepoliaETH 和 FATE 初始庄家资金池

说明：`SepoliaETH` 在合约层仍然使用 EVM 原生币地址 `address(0)`，与 ETH 结算路径相同；这里改名是为了强调它只用于 Sepolia/Anvil 等测试环境，不代表主网真实 ETH。

部署完成后，把输出中的合约地址填入 `frontend/config.js`：

```js
window.CHAIN_FATE_CONFIG = {
  arenaAddress: "0x...",
  coordinatorAddress: "0x...",
  fateTokenAddress: "0x...",
  defaultRoundIds: [1, 2]
};
```

当前文件中已有一组常见 Anvil 默认地址，但只在部署顺序完全相同时有效；重新部署后应以终端输出为准。

### 4.3 启动前端

```bash
cd p6107
npm --prefix frontend run dev
```

前端默认地址：

```text
http://127.0.0.1:8014/
```

打开页面后：

1. 点击 `Connect` 连接 MetaMask。
2. 如果使用 FATE Token，先点击 `Approve FATE` 授权合约消费代币。
3. 使用页面中的 Dice、Raffle、Mock VRF、Reveal Center 完成本地演示。

## 5. 本地演示玩法

### 5.1 Oracle Dice

Dice 的完整流程是：

1. 选择 `SepoliaETH` 或 `FATE`。
2. 输入下注金额 `Wager`。
3. 输入揭示保证金 `Reveal Bond`。
4. 输入 `Roll Under`，合法范围是 2 到 95。
5. 点击 `Commit Dice Bet`。
6. 前端生成随机 seed，把 `keccak256(player, seed)` 作为承诺提交到合约，并把 seed 暂存在浏览器 localStorage。
7. 在 Mock VRF 面板输入请求 id，点击 `Fulfill` 让本地协调器回调随机数。
8. 在 `Reveal Center` 点击对应记录的 `Reveal`。
9. 合约验证 seed、生成骰子点数，并自动赔付或把输掉的下注计入 treasury。

Dice 结算规则：

- 赢：玩家收到 `quoted payout + reveal bond`。
- 输：玩家拿回 `reveal bond`，下注进入庄家 treasury。
- 不揭示：过期后任何人可调用 `slashExpiredDice`，下注和保证金会被罚没。

### 5.2 Epoch Raffle

Raffle 的完整流程是：

1. 管理员部署脚本或 `createRaffleRound` 创建限时轮次。
2. 玩家输入 `Round Id`、票数和揭示保证金。
3. 点击 `Buy Tickets` 购买抽奖票并提交 seed commitment。
4. 轮次关闭后，点击 `Draw` 请求随机数。
5. 在 Mock VRF 面板 Fulfill 对应请求。
6. 玩家在 `Reveal Center` 揭示自己的 seed 并取回保证金。
7. 揭示期结束后点击 `Finalize`。
8. 合约把 VRF 随机数、所有已揭示 seed 的聚合值和轮次信息混合，计算中奖票，自动把奖池扣除 house edge 后支付给 winner。

Raffle 结算规则：

- 中奖者获得 `pot - house fee`。
- 未揭示 seed 的玩家失去 reveal bond。
- house fee 和罚没保证金进入 treasury。
- 中奖结果、中奖票号、VRF word、proof hash 都保存在链上状态中，前端会展示 proof hash。

## 6. 主要合约功能

### 6.1 `ChainFateArena.sol`

核心职责：

- 配置 SepoliaETH/native test ETH 或 ERC-20 下注参数：是否启用、house edge、最小下注、最大下注。
- 管理庄家资金池、已实现 treasury、Dice 预留赔付、揭示保证金、Raffle 奖池。
- 处理 Dice 的 commit、retry、reveal、settle、slash。
- 处理 Raffle 的 create、buy tickets、draw、retry、reveal、finalize。
- 通过 `rawFulfillRandomness` 接收随机数协调器回调。
- 使用 `availableBankroll` 计算可用资金，避免把已预留赔付和奖池误提走。
- 提供 `getDiceBet`、`getRaffleRound`、`getRaffleEntry` 等前端查询接口。

关键安全设计：

- `onlyCoordinator` 限制随机数回调来源。
- commit-reveal 防止玩家在随机数出来后选择 seed。
- reveal deadline 和 reveal bond 让不揭示行为有经济惩罚。
- retry 机制处理随机数请求卡住的情况。
- stale callback 保护：旧 request id 的迟到回调会被忽略。
- `ReentrancyGuard` 保护涉及转账的路径。
- `Pausable` 支持紧急暂停新游戏动作。
- `Ownable` 保护配置、提款、创建轮次等管理动作。

### 6.2 `MockVRFCoordinator.sol`

本地开发和演示使用：

- `requestRandomness` 创建请求 id。
- `fulfillRequest` 自动生成 random word 和 proof hash。
- `fulfillRequestWithWord` 允许演示时指定 random word，便于复现结果。
- 回调消费者合约的 `rawFulfillRandomness`。

注意：Mock 只适合本地演示和测试，不应作为真实部署随机数来源。

### 6.3 `ChainlinkVRFCoordinatorAdapter.sol`

测试网或正式 EVM 网络使用：

- 继承 Chainlink `VRFConsumerBaseV2Plus`。
- 使用 `VRFV2PlusClient` 发起 VRF v2.5 subscription 请求。
- 通过 Chainlink 验证后的 `fulfillRandomWords` 接收随机数。
- 把一个 verified random word 转发给 `ChainFateArena`。
- 使用 allowlist 控制哪些 consumer 可以通过 adapter 消耗 VRF subscription。

### 6.4 `MockERC20.sol`

演示用 ERC-20 Token：

- 名称 `Fate Chip`
- 符号 `FATE`
- 18 decimals
- 支持 mint，用于本地演示 ERC-20 下注流程

## 7. 前端功能

前端位于 `frontend/`，使用 React + Vite + ethers v6。

界面包含：

- 钱包连接：连接 MetaMask，展示当前钱包地址。
- FATE 授权：一键 approve FATE 给游戏合约。
- 协议状态：展示 SepoliaETH/FATE 可用资金、treasury、reserved liabilities。
- Oracle Dice 面板：提交 Dice 下注。
- Epoch Raffle 面板：购买抽奖票。
- Round Desk：触发 draw、finalize、retry。
- Mock VRF 面板：本地环境手动 fulfill request。
- Reveal Center：展示浏览器保存的待揭示 seed，一键 reveal。
- Raffle Board：展示轮次 id、票数、奖池、request id、ready/finalized 状态和 proof hash。
- Transaction Log：展示前端交易提交、确认和失败原因。

一个重要细节：前端会把玩家生成的 reveal seed 保存到浏览器 localStorage，方便课堂 demo。但真实部署时用户必须备份 seed，因为丢失 seed 会导致无法揭示，进而损失 reveal bond。

## 8. Chainlink VRF 测试网部署

如果部署到 Sepolia 或其他支持 Chainlink VRF 的 EVM 测试网，建议使用 adapter 脚本：

```bash
cd p6107
PRIVATE_KEY=0x... \
VRF_SUBSCRIPTION_ID=123 \
SEPOLIA_RPC_URL=https://... \
forge script script/DeployChainlinkVRFChainFateArena.s.sol:DeployChainlinkVRFChainFateArena \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --verify
```

部署前需要：

1. 创建 Chainlink VRF v2.5 subscription。
2. 给 subscription 充值 LINK 或 native token。
3. 确认 `VRF_SUBSCRIPTION_ID`。
4. 部署 adapter 和 arena。
5. 在 Chainlink VRF subscription 管理页面把 adapter 地址加入 consumer。
6. 给 arena 注入 SepoliaETH 或 FATE 作为 bankroll。
7. 把部署地址更新到 `frontend/config.js`。

可选环境变量：

```bash
VRF_COORDINATOR=0x...
VRF_KEY_HASH=0x...
VRF_CALLBACK_GAS_LIMIT=500000
VRF_REQUEST_CONFIRMATIONS=3
VRF_NATIVE_PAYMENT=0
INITIAL_ETH_BANKROLL=100000000000000000
INITIAL_FATE_BANKROLL=10000000000000000000000
```

真实 VRF 部署时，不使用前端 Mock VRF fulfill 面板；Chainlink 会在请求被 subscription 接受并完成确认后异步回调。

## 9. 测试、安全与 Gas 文档

项目已有文档：

- `docs/architecture.md`：系统架构和组件交互。
- `docs/deployment-guide.md`：部署指南。
- `docs/user-guide.md`：用户操作说明。
- `docs/security-analysis.md`：威胁模型和安全控制。
- `docs/gas-optimization.md`：Gas 优化思路和主操作 gas 数据。
- `docs/test-report.md`：构建、测试、覆盖率、前端构建、Slither 结果。
- `docs/slither-report.md`：静态分析记录。
- `docs/option-4-compliance.md`：Option 4 对照清单。

`docs/test-report.md` 记录过一组历史结果；我本次在补齐依赖后也重新运行了核心验证命令。当前实测结果包括：

- Foundry build 成功。
- `forge test`：14 个测试通过，0 失败。
- 核心游戏合约行覆盖率 88.28%。
- Chainlink adapter 行覆盖率 87.88%。
- 包含部署脚本和外部 Chainlink base contracts 后的总行覆盖率 74.58%。
- `npm --prefix frontend run build`：前端生产构建成功。
- Slither 静态分析已运行，剩余设计性问题记录在文档中。

## 10. 对 SC6107 Option 4 要求的满足情况

结论：从代码、文档和本次实测结果看，项目的核心功能设计满足 Option 4，并且覆盖了大多数通用技术要求。需要注意的是，课程要求的 80% line coverage 如果按核心业务合约计算已经满足；如果把部署脚本和外部 Chainlink base contracts 一起计入，总覆盖率会低于 80%。

### 10.1 Option 4 核心功能对照

| 要求 | 项目实现 | 结论 |
| --- | --- | --- |
| 集成 Chainlink VRF 或类似 oracle | 本地 `MockVRFCoordinator` + `ChainlinkVRFCoordinatorAdapter`，adapter 使用 Chainlink VRF v2.5 | 满足 |
| 实现随机数 callback pattern | `rawFulfillRandomness` 由 coordinator 调用，Dice/Raffle 按 request id 存储结果 | 满足 |
| 处理 VRF 失败和 retry | `retryDiceRandomness`、`retryRaffleRandomness` 支持超时后重新请求 | 满足 |
| 向用户展示 randomness proof | Dice/Raffle 保存 `proofHash`，前端 Raffle Board 展示 proof hash | 基本满足 |
| 至少 2 种游戏 | 实现 Oracle Dice 和 Epoch Raffle | 满足 |
| SepoliaETH 和 ERC-20 下注 | SepoliaETH 使用 native token 路径 `address(0)`，ERC-20 使用 FATE token | 满足 |
| Pooled prize 与 house edge | Raffle pot 扣 house fee，Dice 按 house edge 报价赔付 | 满足 |
| 自动 payout | Dice reveal 和 Raffle finalize 都会自动转账 | 满足 |
| 最小/最大下注限制 | `TokenConfig` 中配置 `minBet`、`maxBet` | 满足 |
| 用户动作承诺机制 | 使用 `commitmentFor(player, seed)` | 满足 |
| Time-locked reveals | Dice/Raffle 都有 reveal deadline | 满足 |
| Slashing | 过期不揭示会罚没 reveal bond，Dice 还会罚没 wager | 满足 |
| Transparent outcome verification | 保存 VRF word、proof hash、seed reveal 后可复算结果 | 基本满足 |

### 10.2 通用技术要求对照

| 要求 | 项目状态 | 结论 |
| --- | --- | --- |
| Ethereum/EVM 平台 | Solidity 0.8.26 + Foundry + EVM 部署脚本 | 满足 |
| Solidity 0.8.x | `pragma solidity ^0.8.26` | 满足 |
| Foundry/Hardhat 框架 | Foundry 项目，含 `foundry.toml`、`forge` 测试和脚本 | 满足 |
| OpenZeppelin Contracts 5.x | 使用 `Ownable`、`Pausable`、`ReentrancyGuard`、`ERC20`、`SafeERC20` | 满足 |
| 单元测试/集成测试/fuzz/invariant | 测试覆盖 Dice、Raffle、ERC-20、pause、retry、fuzz、solvency invariant、adapter | 基本满足 |
| 80% line coverage | 本次实测核心合约 88.28%，adapter 87.88%；全项目含脚本和外部 base contracts 为 74.58% | 核心合约满足；全量统计低于 80% |
| Slither 或类似静态分析 | `docs/security-analysis.md` 和 `docs/slither-report.md` 记录 Slither 结果 | 满足 |
| Reentrancy 防护 | 资金转移路径使用 `nonReentrant` 和 SafeERC20 | 满足 |
| 整数溢出防护 | Solidity 0.8.x 默认检查，关键金额有范围校验 | 满足 |
| 前端 | React + Vite | 满足 |
| Web3 库 | ethers v6 | 满足 |
| MetaMask | `ethers.BrowserProvider(window.ethereum)` 连接 MetaMask | 满足 |
| README、架构、安全、Gas、部署、用户指南 | 项目已有英文文档，本文件补充中文 README | 满足 |
| NatSpec | 核心 public/external 函数有 `@notice`，但不是每个参数都有完整 `@param/@return` | 基本满足，但可进一步完善 |

### 10.3 需要注意的不足

1. Fresh clone 后必须先安装 npm 依赖和 OpenZeppelin 合约库，否则 `forge test` 会找不到 OpenZeppelin/Chainlink，前端构建也会找不到 Vite 或合约 artifact。
2. 课程要求最低 80% line coverage。核心合约和 adapter 已超过 80%，但如果把部署脚本和外部 Chainlink base contracts 一起算，本次总覆盖率是 74.58%。提交时建议在报告里明确说明核心业务合约覆盖率，并尽量让最终评测命令排除脚本和依赖。
3. NatSpec 已有 `@notice`，但如果严格按“all public functions”理解，建议进一步补全 `@param` 和 `@return`，尤其是对外接口、部署脚本和 mock 中的 public/external 函数。
4. Mock VRF proof hash 适合课堂演示；正式测试网展示公平性时应使用 Chainlink VRF adapter，并在 README 或演示中说明 proof 来自 Chainlink 验证路径。
5. Raffle `finalizeRaffle` 会线性遍历 entries。当前适合课程规模和小轮次演示，生产化应增加每轮参与人数上限或改用更高效的数据结构。

## 11. 建议提交前检查清单

```bash
cd p6107
npm ci
npm --prefix frontend ci
forge build
forge test -vv
forge coverage --report summary
npm --prefix frontend run build
```

如果安装了 Slither：

```bash
slither . --exclude-dependencies
```

最终提交时建议附上：

- GitHub 仓库链接。
- 前端 demo 截图或视频。
- 本地或测试网部署地址。
- 测试覆盖率报告。
- Slither 报告。
- Option 4 compliance 清单。
