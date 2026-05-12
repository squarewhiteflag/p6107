# Chain Fate Arena 环境配置指南

本文档提供 **Chain Fate Arena**（SC6107 Option 4：链上可验证随机游戏平台）从零开始的环境配置与启动流程。适用于 macOS / Linux 系统。

---

## 目录

1. [前置依赖](#1-前置依赖)
2. [克隆项目](#2-克隆项目)
3. [安装依赖](#3-安装依赖)
4. [编译合约](#4-编译合约)
5. [运行测试](#5-运行测试)
6. [本地开发环境启动](#6-本地开发环境启动)
7. [MetaMask 钱包配置](#7-metamask-钱包配置)
8. [部署合约到本地链](#8-部署合约到本地链)
9. [启动前端](#9-启动前端)
10. [本地演示流程](#10-本地演示流程)
11. [Chainlink VRF 测试网部署（可选）](#11-chainlink-vrf-测试网部署可选)
12. [常见问题排查](#12-常见问题排查)
13. [验证清单](#13-验证清单)

---

## 1. 前置依赖

在开始之前，请确保以下工具已经安装。

### 1.1 安装 Foundry

Foundry 是 Solidity 智能合约开发框架，包含 `forge`（编译/测试）、`anvil`（本地链）和 `cast`（链上交互）。

```bash
# 使用官方安装脚本（推荐）
curl -L https://foundry.paradigm.xyz | bash

# 安装完成后，重新加载 shell 配置
source ~/.bashrc   # 或 source ~/.zshrc

# 安装/更新 foundryup，然后安装 forge、anvil、cast
foundryup
```

验证安装：

```bash
forge --version
anvil --version
cast --version
```

> **版本要求**：本项目使用 Solidity 0.8.26，建议 Foundry 版本不低于 2024 年 6 月发布版。

### 1.2 安装 Node.js 与 npm

前端使用 Vite + React，需要 Node.js 运行时。

**方式一：使用 nvm（推荐）**

```bash
# 安装 nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

# 重新加载 shell
source ~/.bashrc   # 或 source ~/.zshrc

# 安装 Node.js LTS 版本
nvm install --lts
nvm use --lts
```

**方式二：直接安装**

从 [nodejs.org](https://nodejs.org/) 下载 macOS 安装包并安装。

验证安装：

```bash
node --version   # 应 >= 18.x
npm --version    # 应 >= 9.x
```

### 1.3 安装 MetaMask 浏览器扩展

1. 访问 [metamask.io](https://metamask.io/) 下载浏览器扩展。
2. 完成初始化设置（创建新钱包或导入已有钱包）。
3. **重要**：确保 MetaMask 扩展已在浏览器中启用。

### 1.4 可选工具

| 工具 | 用途 | 安装方式 |
|------|------|----------|
| Slither | Solidity 静态分析 | `pip3 install slither-analyzer` |
| jq | JSON 命令行处理 | `brew install jq` |
| Git | 版本控制 | `brew install git`（macOS 通常已自带） |

---

## 2. 克隆项目

```bash
# 克隆仓库
git clone <你的仓库地址> p6107
cd p6107
```

> 如果仓库使用了 Git 子模块（`.gitmodules`），需要同时初始化子模块：
>
> ```bash
> git submodule update --init --recursive
> ```

---

## 3. 安装依赖

### 3.1 安装 Node.js 依赖（项目根目录）

```bash
cd p6107
npm install
```

这会在根目录安装 `@chainlink/contracts` 等依赖到 `node_modules/`。

### 3.2 安装 Foundry 合约库

项目依赖 OpenZeppelin Contracts 5.x 和 forge-std。这些库通过 Foundry 的 `lib/` 目录管理。

```bash
cd p6107

# 安装 forge-std（测试标准库）
forge install foundry-rs/forge-std --no-git --shallow

# 安装 OpenZeppelin Contracts
forge install OpenZeppelin/openzeppelin-contracts --no-git --shallow
```

安装完成后，确认以下目录存在且非空：

```bash
ls lib/forge-std/src/               # 应有 Vm.sol、Test.sol 等
ls lib/openzeppelin-contracts/contracts/   # 应有 token/、access/、utils/ 等
```

### 3.3 安装前端依赖

```bash
cd p6107
npm --prefix frontend install
```

确认前端依赖安装成功：

```bash
ls frontend/node_modules/   # 应有 react、vite、ethers 等
```

### 3.4 依赖完整性检查

安装完毕后，以下路径应当存在：

```
p6107/
├── node_modules/@chainlink/contracts/        # Chainlink 合约
├── lib/forge-std/src/                         # Foundry 测试标准库
├── lib/openzeppelin-contracts/contracts/      # OpenZeppelin 合约
├── frontend/node_modules/                     # 前端依赖
└── foundry.toml                               # Foundry 配置
```

---

## 4. 编译合约

```bash
cd p6107
forge build
```

预期输出：

```
[⠊] Compiling...
[⠰] Compiling 40 files with Solc 0.8.26
[⠒] Solc 0.8.26 finished in 12.34s
Compiler run successful!
```

> 如果报错找不到 `@openzeppelin/contracts/` 或 `@chainlink/contracts/`，请回到步骤 3 确认依赖安装完整。

---

## 5. 运行测试

```bash
cd p6107
forge test
```

预期输出（示例）：

```
Ran 14 tests for test/ChainFateArena.t.sol:ChainFateArenaTest
[PASS] testCommitDiceBet() ...
[PASS] testCommitDiceBetReverts() ...
...
Suite result: ok. 14 passed; 0 failed; 0 skipped; finished in 45.23ms
```

查看详细输出：

```bash
forge test -vv
```

生成覆盖率报告：

```bash
forge coverage --report summary
```

---

## 6. 本地开发环境启动

本地开发需要同时运行三个组件：Anvil 本地区块链、已部署的合约、React 前端。

整体架构：

```
终端 1: anvil                    → 本地 EVM 链 (127.0.0.1:8545)
终端 2: forge script deploy      → 部署合约到本地链
终端 3: npm run frontend:dev     → React 前端 (127.0.0.1:8014)
```

### 6.1 启动 Anvil 本地区块链

打开**第一个终端窗口**：

```bash
cd p6107
anvil
```

启动后你会看到类似输出：

```
                             _   _
                            (_) | |
      __ _   _ __   __   __  _  | |
     / _` | | '_ \  \ \ / / | | | |
    | (_| | | | | |  \ V /  | | | |
     \__,_| |_| |_|   \_/   |_| |_|

    0.2.0 (abc1234 2024-01-01T00:00:00.000000000Z)
    https://github.com/foundry-rs/foundry

Available Accounts
==================

(0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000.000000000000000000 ETH)
(1) 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000.000000000000000000 ETH)
...

Private Keys
==================

(0) 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
...

Wallet
==================
Mnemonic:          test test test test test test test test test test test junk
...

Listening on 127.0.0.1:8545
```

> **重要**：
> - Anvil 的 RPC 地址是 `http://127.0.0.1:8545`
> - Chain ID 是 `31337`
> - 默认提供 10 个测试账户，每个有 10000 ETH
> - **保持这个终端运行**，不要关闭

---

## 7. MetaMask 钱包配置

### 7.1 添加 Anvil 本地网络

1. 点击 MetaMask 扩展图标。
2. 点击左上角的网络选择器 → **"添加网络"** 或 **"Custom Network"**。
3. 填入以下信息：

| 字段 | 值 |
|------|-----|
| Network name | `Anvil Local` |
| Default RPC URL | `http://127.0.0.1:8545` |
| Chain ID | `31337` |
| Currency symbol | `SepoliaETH` |
| Block explorer URL | （留空） |

4. 点击 **"Save"**（保存）。

### 7.2 导入测试账户

为了在本地环境中操作合约，需要导入 Anvil 提供的测试账户私钥。

1. MetaMask → 点击右上角账户图标 → **"Import Account"**。
2. 粘贴 Anvil 启动时显示的私钥（例如 `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`）。
3. 点击 **"Import"**。

导入后该账户将显示约 10000 ETH（Anvil 默认余额）。

> 如果余额显示为 0，请检查 MetaMask 是否已切换到 `Anvil Local` 网络。

---

## 8. 部署合约到本地链

打开**第二个终端窗口**（确保第一个终端的 Anvil 仍在运行）：

```bash
cd p6107
forge script script/DeployChainFateArena.s.sol:DeployChainFateArena \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

### 8.1 部署脚本做了什么

部署脚本会依次执行以下操作：

1. 部署 `MockVRFCoordinator` — 本地 VRF 风格随机数协调器
2. 部署 `ChainFateArena` — 核心游戏平台合约
3. 部署 `MockERC20` — 演示用 FATE Token（名称：Fate Chip，符号：FATE）
4. 创建 1 个 SepoliaETH（原生币）抽奖轮次
5. 创建 1 个 FATE（ERC-20）抽奖轮次
6. 向游戏资金池注入 SepoliaETH 和 FATE 初始资金

### 8.2 记录部署地址

部署完成后，终端会输出类似以下的合约地址：

```
== Logs ==
  MockVRFCoordinator deployed at: 0x5FbDB2315678afecb367f032d93F642f64180aa3
  ChainFateArena deployed at: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
  MockERC20 deployed at: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
```

**将这些地址更新到 `frontend/config.js`**：

```js
// frontend/config.js
window.CHAIN_FATE_CONFIG = {
  arenaAddress: "0x...",       // ChainFateArena 地址
  coordinatorAddress: "0x...", // MockVRFCoordinator 地址
  fateTokenAddress: "0x...",   // MockERC20 地址
  defaultRoundIds: [1, 2]
};
```

> **注意**：由于部署顺序（nonce）依赖 Anvil 初始状态，每次重新启动 Anvil 后部署的地址可能不同，需要重新更新 `config.js`。

---

## 9. 启动前端

打开**第三个终端窗口**：

```bash
cd p6107
npm run frontend:dev
```

预期输出：

```
  VITE v5.4.11  ready in 123 ms

  ➜  Local:   http://127.0.0.1:8014/
  ➜  Network: use --host to expose
```

在浏览器中打开 `http://127.0.0.1:8014/`。

---

## 10. 本地演示流程

合约部署、前端启动后，即可进行完整的本地游戏演示。

### 10.1 连接钱包

1. 打开 `http://127.0.0.1:8014/`
2. 点击页面上的 **"Connect"** 按钮
3. MetaMask 会弹出连接确认，点击确认

### 10.2 FATE Token 授权（如使用 FATE）

如果打算使用 FATE ERC-20 代币下注：

1. 点击 **"Approve FATE"** 按钮
2. MetaMask 弹出交易确认，点击确认
3. 等待交易上链

### 10.3 Oracle Dice（骰子游戏）演示

1. 选择下注币种：`SepoliaETH` 或 `FATE`
2. 输入下注金额 `Wager`（例如 `0.01`）
3. 输入揭示保证金 `Reveal Bond`（例如 `0.002`）
4. 输入 `Roll Under`（合法范围 2-95，例如 `50`）
5. 点击 **"Commit Dice Bet"**
6. MetaMask 确认交易后，前端会生成随机种子并保存到浏览器 localStorage
7. 切换到 **"Mock VRF"** 面板，输入请求 ID（在 Dice 面板可看到），点击 **"Fulfill"**
8. 切换到 **"Reveal Center"** 面板，找到对应记录，点击 **"Reveal"**
9. 合约验证种子、计算骰子点数、自动结算

> **骰子结算规则**：
> - 赢：玩家获得 quoted payout + reveal bond
> - 输：玩家拿回 reveal bond，下注金进入庄家金库
> - 超时未揭示：下注和保证金均被罚没

### 10.4 Epoch Raffle（限时抽奖）演示

1. 部署脚本已经创建了默认轮次（Round 1: SepoliaETH，Round 2: FATE）
2. 输入 `Round Id`（1 或 2）
3. 输入购买票数和揭示保证金
4. 点击 **"Buy Tickets"**
5. MetaMask 确认后，在 **"Round Desk"** 面板点击 **"Draw"** 请求随机数
6. 在 Mock VRF 面板 Fulfill 对应请求
7. 在 **"Reveal Center"** 揭示种子
8. 揭示期结束后，点击 **"Finalize"**
9. 合约自动选出中奖票并发放奖池

### 10.5 Mock VRF 面板说明

Mock VRF 面板仅在本地环境使用：

- `requestId`：随机数请求编号（与 Dice/Raffle 面板中的一致）
- **"Fulfill"**：让本地协调器自动生成随机数并回调合约
- **"Fulfill With Word"**：手动指定随机数（用于复现特定结果）

---

## 11. Chainlink VRF 测试网部署（可选）

本地演示完成后，如需部署到 Sepolia 等真实测试网使用 Chainlink VRF：

### 11.1 前置准备

1. **获取 Sepolia 测试网 ETH**：通过 [Sepolia Faucet](https://sepoliafaucet.com/) 领取
2. **创建 Chainlink VRF v2.5 Subscription**：
   - 访问 [vrf.chain.link](https://vrf.chain.link/)
   - 连接钱包，创建新 Subscription
   - 记录 `Subscription ID`
3. **给 Subscription 充值 LINK 或 SepoliaETH**

### 11.2 部署到 Sepolia

```bash
cd p6107

# 设置环境变量
export PRIVATE_KEY=<你的私钥>
export VRF_SUBSCRIPTION_ID=<你的 Subscription ID>
export SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/<你的 API Key>

# 部署
forge script script/DeployChainlinkVRFChainFateArena.s.sol:DeployChainlinkVRFChainFateArena \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --verify
```

### 11.3 部署后操作

1. 在 Chainlink VRF Subscription 管理页面将 Adapter 地址加入 consumer
2. 给 Arena 合约转入 SepoliaETH 和 FATE 作为 bankroll
3. 更新 `frontend/config.js` 中的合约地址
4. 前端使用 Sepolia 网络时不需要 Mock VRF 面板——Chainlink 会自动异步回调

### 11.4 可选环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `VRF_COORDINATOR` | 链上已配置 | Chainlink VRF Coordinator 地址 |
| `VRF_KEY_HASH` | 链上已配置 | VRF Gas Lane Key Hash |
| `VRF_CALLBACK_GAS_LIMIT` | `500000` | 回调 Gas 上限 |
| `VRF_REQUEST_CONFIRMATIONS` | `3` | 请求确认数 |
| `VRF_NATIVE_PAYMENT` | `0` | 是否使用原生代币支付 |
| `INITIAL_ETH_BANKROLL` | `100000000000000000` | 初始 ETH 资金池 |
| `INITIAL_FATE_BANKROLL` | `10000000000000000000000` | 初始 FATE 资金池 |

---

## 12. 常见问题排查

### 12.1 `forge build` 报错：找不到 OpenZeppelin 合约

```
Error: Source "@openzeppelin/contracts/access/Ownable.sol" not found
```

**解决**：

```bash
# 确认 OpenZeppelin 子模块已安装
ls lib/openzeppelin-contracts/contracts/

# 如果为空，重新安装
forge install OpenZeppelin/openzeppelin-contracts --no-git --shallow
```

### 12.2 `forge build` 报错：找不到 @chainlink/contracts

```
Error: Source "@chainlink/contracts/..." not found
```

**解决**：

```bash
# 确认 npm 依赖已安装
npm install

# 验证
ls node_modules/@chainlink/contracts/
```

### 12.3 `npm --prefix frontend run dev` 报错：Cannot find module

**解决**：

```bash
# 重新安装前端依赖
npm --prefix frontend install
```

### 12.4 Anvil 启动失败：端口被占用

```
Error: Address already in use (os error 48)
```

**解决**：8545 端口被其他进程占用。要么关闭占用进程，要么换一个端口：

```bash
# 查找占用进程
lsof -i :8545

# 或换端口启动
anvil --port 8546
```

如果换了端口，部署和前端配置中的 RPC URL 也需要相应修改。

### 12.5 MetaMask 交易 nonce 错误

Anvil 重启后 MetaMask 的 nonce 缓存可能与链状态不一致。

**解决**：

1. MetaMask → 设置 → 高级 → **"Reset Account"**（重置账户）
2. 这不会丢失资金，只是清空 MetaMask 的交易历史缓存。

### 12.6 前端部署地址不匹配

如果重新部署后前端报 `call revert exception`，说明 `frontend/config.js` 中的地址不是当前部署的合约地址。

**解决**：将最新部署输出的合约地址更新到 `frontend/config.js`。

### 12.7 `forge script` 部署报 nonce too low

Anvil 重启后 nonce 归零，但 Foundry 脚本可能缓存了旧的 nonce。

**解决**：重新运行部署命令即可（Foundry 每次运行脚本都是新的交易）。

### 12.8 macOS 安全提示

如果 `forge`、`anvil` 等命令提示无法验证开发者：

1. 系统偏好设置 → 安全性与隐私 → 通用
2. 点击 **"仍要打开"**
3. 或者在终端执行：

```bash
xattr -d com.apple.quarantine $(which forge)
xattr -d com.apple.quarantine $(which anvil)
```

---

## 13. 验证清单

完成以上所有步骤后，请逐项确认：

- [ ] `foundryup` 安装成功，`forge --version` 正常输出
- [ ] `node --version` >= 18，`npm --version` >= 9
- [ ] MetaMask 扩展已安装并初始化
- [ ] 项目已克隆，`git submodule` 已初始化
- [ ] `npm install` 成功（根目录）
- [ ] `forge install` 完成，`lib/forge-std/` 和 `lib/openzeppelin-contracts/` 非空
- [ ] `npm --prefix frontend install` 成功
- [ ] `forge build` 编译无错误
- [ ] `forge test` 全部通过
- [ ] Anvil 在 `127.0.0.1:8545` 正常运行
- [ ] MetaMask 已添加 Anvil Local 网络（Chain ID: 31337）
- [ ] MetaMask 已导入 Anvil 测试账户
- [ ] `forge script` 部署成功，合约地址已写入 `frontend/config.js`
- [ ] `npm run frontend:dev` 启动，`http://127.0.0.1:8014/` 可访问
- [ ] 前端可连接 MetaMask，可执行 Dice 和 Raffle 完整流程

---

> 如需进一步了解项目架构、安全设计、Gas 优化等细节，请参阅 `docs/` 目录下的其他文档。
