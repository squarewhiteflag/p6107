import { useEffect, useMemo, useState } from "react";
import {
  BadgeCheck,
  CircleDollarSign,
  Dice5,
  Gift,
  KeyRound,
  Loader2,
  RefreshCw,
  ShieldCheck,
  Ticket,
  Wallet
} from "lucide-react";
import { ethers } from "ethers";
import arenaArtifact from "../../out/ChainFateArena.sol/ChainFateArena.json";
import { TOKEN_OPTIONS, ZERO_ADDRESS, formatNative, tokenAddressFor, tokenDisplayName } from "./tokens.js";

const STORAGE_PREFIX = "chain-fate-reveals";
const ERC20_ABI = [
  "function approve(address spender, uint256 value) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function balanceOf(address account) external view returns (uint256)",
  "function symbol() external view returns (string)"
];
const MOCK_VRF_ABI = [
  "function fulfillRequest(uint256 requestId) external returns (uint256 randomWord, bytes32 proofHash)",
  "function fulfillRequestWithWord(uint256 requestId, uint256 randomWord) external"
];

const cfg = window.CHAIN_FATE_CONFIG || {};

const emptyMetrics = {
  ethAvailable: "-",
  ethTreasury: "-",
  ethReserved: "-",
  fateAvailable: "-",
  fateTreasury: "-",
  fateReserved: "-"
};

export default function App() {
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [account, setAccount] = useState("");
  const [arena, setArena] = useState(null);
  const [coordinator, setCoordinator] = useState(null);
  const [fate, setFate] = useState(null);
  const [metrics, setMetrics] = useState(emptyMetrics);
  const [rounds, setRounds] = useState([]);
  const [pending, setPending] = useState([]);
  const [logs, setLogs] = useState(["Load deployed addresses in frontend/config.js, then connect MetaMask."]);
  const [busy, setBusy] = useState(false);

  const walletLabel = useMemo(() => (account ? shortAddress(account) : "Not connected"), [account]);

  useEffect(() => {
    setPending(readPending());
    if (window.ethereum?.selectedAddress) {
      connectWallet();
    }
    if (window.ethereum) {
      window.ethereum.on("accountsChanged", () => window.location.reload());
    }
  }, []);

  useEffect(() => {
    if (arena) {
      refreshDashboard(arena);
    }
  }, [arena]);

  function pushLog(message) {
    setLogs((items) => [message, ...items].slice(0, 12));
  }

  async function connectWallet() {
    if (!window.ethereum) {
      pushLog("MetaMask was not detected.");
      return;
    }
    if (!cfg.arenaAddress) {
      pushLog("Missing arenaAddress in frontend/config.js.");
      return;
    }

    const nextProvider = new ethers.BrowserProvider(window.ethereum);
    await window.ethereum.request({ method: "eth_requestAccounts" });
    const nextSigner = await nextProvider.getSigner();
    const nextAccount = await nextSigner.getAddress();
    const nextArena = new ethers.Contract(cfg.arenaAddress, arenaArtifact.abi, nextSigner);
    const nextCoordinator = cfg.coordinatorAddress
      ? new ethers.Contract(cfg.coordinatorAddress, MOCK_VRF_ABI, nextSigner)
      : null;
    const nextFate = cfg.fateTokenAddress ? new ethers.Contract(cfg.fateTokenAddress, ERC20_ABI, nextSigner) : null;

    setProvider(nextProvider);
    setSigner(nextSigner);
    setAccount(nextAccount);
    setArena(nextArena);
    setCoordinator(nextCoordinator);
    setFate(nextFate);
    pushLog(`Connected ${shortAddress(nextAccount)}.`);
  }

  async function refreshDashboard(contract = arena) {
    if (!contract) return;
    try {
      const [ethAvailable, ethTreasury, ethDice, ethBond, ethPot] = await Promise.all([
        contract.availableBankroll(ZERO_ADDRESS),
        contract.treasuryBalance(ZERO_ADDRESS),
        contract.reservedDicePayouts(ZERO_ADDRESS),
        contract.reservedRevealBonds(ZERO_ADDRESS),
        contract.reservedRafflePots(ZERO_ADDRESS)
      ]);

      const nextMetrics = {
        ethAvailable: formatSepoliaEth(ethAvailable),
        ethTreasury: formatSepoliaEth(ethTreasury),
        ethReserved: formatSepoliaEth(ethDice + ethBond + ethPot),
        fateAvailable: "-",
        fateTreasury: "-",
        fateReserved: "-"
      };

      if (cfg.fateTokenAddress) {
        const [fateAvailable, fateTreasury, fateDice, fateBond, fatePot] = await Promise.all([
          contract.availableBankroll(cfg.fateTokenAddress),
          contract.treasuryBalance(cfg.fateTokenAddress),
          contract.reservedDicePayouts(cfg.fateTokenAddress),
          contract.reservedRevealBonds(cfg.fateTokenAddress),
          contract.reservedRafflePots(cfg.fateTokenAddress)
        ]);
        nextMetrics.fateAvailable = formatFate(fateAvailable);
        nextMetrics.fateTreasury = formatFate(fateTreasury);
        nextMetrics.fateReserved = formatFate(fateDice + fateBond + fatePot);
      }

      setMetrics(nextMetrics);
      await refreshRounds(contract);
      setPending(readPending());
    } catch (error) {
      pushLog(`Refresh failed: ${readableError(error)}`);
    }
  }

  async function refreshRounds(contract = arena) {
    const ids = new Set(cfg.defaultRoundIds || []);
    try {
      const nextRoundId = Number(await contract.nextRaffleRoundId());
      for (let id = 1; id < nextRoundId; id += 1) ids.add(id);
    } catch {
      // Keep configured ids if the call fails.
    }

    const nextRounds = [];
    for (const id of [...ids].sort((a, b) => a - b)) {
      try {
        const round = await contract.getRaffleRound(id);
        if (round.ticketPrice === 0n) continue;
        nextRounds.push({
          id,
          token: round.token,
          totalTickets: round.totalTickets.toString(),
          pot: round.token === ZERO_ADDRESS ? formatSepoliaEth(round.pot) : formatFate(round.pot),
          requestId: round.requestId.toString(),
          randomnessReady: round.randomnessReady,
          finalized: round.finalized,
          proofHash: round.proofHash
        });
      } catch {
        // Ignore rounds that are not deployed.
      }
    }
    setRounds(nextRounds);
  }

  async function withTx(label, action) {
    if (!arena) {
      pushLog("Connect MetaMask first.");
      return;
    }
    setBusy(true);
    try {
      const tx = await action();
      pushLog(`${label} submitted: ${shortHash(tx.hash)}.`);
      await tx.wait();
      pushLog(`${label} confirmed.`);
      await refreshDashboard();
    } catch (error) {
      pushLog(`${label} failed: ${readableError(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function placeDiceBet(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const tokenMode = form.get("token");
    const token = tokenAddressFor(tokenMode, cfg.fateTokenAddress);
    const wager = parseUnits(form.get("wager"));
    const bond = parseUnits(form.get("bond"));
    const rollUnder = Number(form.get("rollUnder"));
    const seed = ethers.hexlify(ethers.randomBytes(32));
    const commitment = commitmentFor(account, seed);

    await withTx("Dice commit", async () => {
      const overrides = token === ZERO_ADDRESS ? { value: wager + bond } : {};
      const tx = await arena.commitDiceBet(token, wager, rollUnder, commitment, bond, overrides);
      const receipt = await tx.wait();
      const eventLog = receipt.logs
        .map((log) => {
          try {
            return arena.interface.parseLog(log);
          } catch {
            return null;
          }
        })
        .find((log) => log?.name === "DiceCommitted");
      const betId = Number(eventLog?.args?.betId ?? (await arena.nextDiceBetId()) - 1n);
      savePending({ type: "dice", id: betId, seed, tokenMode, createdAt: Date.now() });
      setPending(readPending());
      return { hash: tx.hash, wait: async () => receipt };
    });
  }

  async function buyRaffleTickets(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const roundId = Number(form.get("roundId"));
    const ticketCount = Number(form.get("ticketCount"));
    const bond = parseUnits(form.get("bond"));
    const seed = ethers.hexlify(ethers.randomBytes(32));
    const commitment = commitmentFor(account, seed);

    await withTx("Raffle purchase", async () => {
      const round = await arena.getRaffleRound(roundId);
      const token = round.token;
      const total = round.ticketPrice * BigInt(ticketCount) + bond;
      const overrides = token === ZERO_ADDRESS ? { value: total } : {};
      const tx = await arena.buyRaffleTickets(roundId, ticketCount, commitment, bond, overrides);
      const receipt = await tx.wait();
      const entryCount = await arena.getRaffleEntryCount(roundId);
      savePending({
        type: "raffle",
        roundId,
        entryIndex: Number(entryCount) - 1,
        seed,
        tokenMode: token === ZERO_ADDRESS ? "sepoliaeth" : "fate",
        createdAt: Date.now()
      });
      setPending(readPending());
      return { hash: tx.hash, wait: async () => receipt };
    });
  }

  async function drawRaffle(event) {
    event.preventDefault();
    const roundId = Number(new FormData(event.currentTarget).get("roundId"));
    await withTx("Draw", () => arena.drawRaffle(roundId));
  }

  async function finalizeRaffle(event) {
    event.preventDefault();
    const roundId = Number(new FormData(event.currentTarget).get("roundId"));
    await withTx("Finalize", () => arena.finalizeRaffle(roundId));
  }

  async function retryRandomness(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const kind = form.get("kind");
    const id = Number(form.get("id"));
    await withTx("Retry", () => (kind === "dice" ? arena.retryDiceRandomness(id) : arena.retryRaffleRandomness(id)));
  }

  async function fulfillRequest(event) {
    event.preventDefault();
    if (!coordinator) {
      pushLog("Missing coordinatorAddress in frontend/config.js.");
      return;
    }
    const form = new FormData(event.currentTarget);
    const requestId = BigInt(form.get("requestId"));
    const word = form.get("word");
    await withTx("VRF fulfill", () =>
      word === "" ? coordinator.fulfillRequest(requestId) : coordinator.fulfillRequestWithWord(requestId, BigInt(word))
    );
  }

  async function approveFate() {
    if (!fate || !arena) {
      pushLog("Missing FATE token address.");
      return;
    }
    await withTx("FATE approval", () => fate.approve(cfg.arenaAddress, ethers.MaxUint256));
  }

  async function revealPending(item) {
    await withTx("Reveal", async () => {
      const tx =
        item.type === "dice"
          ? await arena.revealDiceSeed(item.id, item.seed)
          : await arena.revealRaffleSeed(item.roundId, item.entryIndex, item.seed);
      const receipt = await tx.wait();
      removePending(item.localId);
      setPending(readPending());
      return { hash: tx.hash, wait: async () => receipt };
    });
  }

  return (
    <main className="app-shell">
      <div className="texture" aria-hidden="true" />
      <header className="topbar">
        <div>
          <p className="eyebrow">SC6107 Option 4</p>
          <h1>Chain Fate Arena</h1>
        </div>
        <div className="wallet-strip">
          <button className="button primary" type="button" onClick={connectWallet}>
            <Wallet size={17} /> Connect
          </button>
          <button className="button quiet" type="button" onClick={approveFate} disabled={!fate || busy}>
            <BadgeCheck size={17} /> Approve FATE
          </button>
          <div className="wallet-pill">
            <span>Wallet</span>
            <strong>{walletLabel}</strong>
          </div>
        </div>
      </header>

      <section className="status-grid" aria-label="Protocol status">
        <Metric icon={<CircleDollarSign />} label="SepoliaETH Available" value={metrics.ethAvailable} invert />
        <Metric label="SepoliaETH Treasury" value={metrics.ethTreasury} />
        <Metric label="SepoliaETH Reserved" value={metrics.ethReserved} />
        <Metric icon={<CircleDollarSign />} label="FATE Available" value={metrics.fateAvailable} invert />
        <Metric label="FATE Treasury" value={metrics.fateTreasury} />
        <Metric label="FATE Reserved" value={metrics.fateReserved} />
      </section>

      <section className="workbench">
        <GamePanel eyebrow="Game One" title="Oracle Dice" icon={<Dice5 />}>
          <form className="form-grid" onSubmit={placeDiceBet}>
            <Field label="Token" as="select" name="token" options={TOKEN_OPTIONS} />
            <Field label="Wager" name="wager" type="number" min="0" step="0.01" defaultValue="0.5" />
            <Field label="Reveal Bond" name="bond" type="number" min="0" step="0.01" defaultValue="0.05" />
            <Field label="Roll Under" name="rollUnder" type="number" min="2" max="95" defaultValue="50" />
            <button className="button primary span-2" type="submit" disabled={!arena || busy}>
              {busy ? <Loader2 className="spin" size={17} /> : <Dice5 size={17} />} Commit Dice Bet
            </button>
          </form>
        </GamePanel>

        <GamePanel eyebrow="Game Two" title="Epoch Raffle" icon={<Ticket />}>
          <form className="form-grid" onSubmit={buyRaffleTickets}>
            <Field label="Round Id" name="roundId" type="number" min="1" defaultValue="1" />
            <Field label="Tickets" name="ticketCount" type="number" min="1" defaultValue="1" />
            <Field label="Reveal Bond" name="bond" type="number" min="0" step="0.01" defaultValue="0.1" />
            <button className="button primary span-2" type="submit" disabled={!arena || busy}>
              <Gift size={17} /> Buy Tickets
            </button>
          </form>
        </GamePanel>
      </section>

      <section className="operator-grid">
        <article className="panel">
          <PanelHead eyebrow="Round Desk" title="Draw and finalize" icon={<RefreshCw />} />
          <form className="inline-form" onSubmit={drawRaffle}>
            <input name="roundId" type="number" min="1" defaultValue="1" required />
            <button className="button quiet" type="submit" disabled={!arena || busy}>Draw</button>
          </form>
          <form className="inline-form" onSubmit={finalizeRaffle}>
            <input name="roundId" type="number" min="1" defaultValue="1" required />
            <button className="button quiet" type="submit" disabled={!arena || busy}>Finalize</button>
          </form>
          <form className="inline-form triple" onSubmit={retryRandomness}>
            <select name="kind">
              <option value="dice">Dice</option>
              <option value="raffle">Raffle</option>
            </select>
            <input name="id" type="number" min="1" placeholder="Bet or round id" required />
            <button className="button quiet" type="submit" disabled={!arena || busy}>Retry</button>
          </form>
        </article>

        <article className="panel dark">
          <PanelHead eyebrow="Mock VRF" title="Fulfill request" icon={<ShieldCheck />} />
          <form className="inline-form triple" onSubmit={fulfillRequest}>
            <input name="requestId" type="text" inputMode="numeric" placeholder="Request id" required />
            <input name="word" type="number" min="0" placeholder="Optional word" />
            <button className="button light" type="submit" disabled={!coordinator || busy}>Fulfill</button>
          </form>
        </article>
      </section>

      <section className="lower-grid">
        <article className="panel">
          <PanelHead eyebrow="Reveal Center" title="Committed seeds" icon={<KeyRound />} />
          <div className="pending-list">
            {pending.length ? (
              pending.map((item) => (
                <div className="pending-item" key={item.localId}>
                  <div>
                    <strong>{item.type === "dice" ? `Dice bet ${item.id}` : `Raffle ${item.roundId}/${item.entryIndex}`}</strong>
                    <code>{item.seed}</code>
                  </div>
                  <button className="button quiet" type="button" onClick={() => revealPending(item)} disabled={!arena || busy}>
                    Reveal
                  </button>
                </div>
              ))
            ) : (
              <div className="empty">No local reveal seeds yet.</div>
            )}
          </div>
        </article>

        <article className="panel">
          <PanelHead eyebrow="Raffle Board" title="Rounds" icon={<Ticket />} />
          <div className="round-list">
            {rounds.length ? (
              rounds.map((round) => (
                <div className="round-item" key={round.id}>
                  <strong>Round {round.id} - {tokenDisplayName(round.token, cfg.fateTokenAddress)}</strong>
                  <div className="mini-label">tickets {round.totalTickets} - pot {round.pot}</div>
                  <div className="mini-label">request {round.requestId} - ready {String(round.randomnessReady)} - finalized {String(round.finalized)}</div>
                  <code>proof {round.proofHash}</code>
                </div>
              ))
            ) : (
              <div className="empty">No configured rounds found.</div>
            )}
          </div>
        </article>
      </section>

      <section className="log-panel">
        <PanelHead eyebrow="Status" title="Transaction log" icon={<RefreshCw />} />
        <div className="status-log">
          {logs.map((line, index) => (
            <div className="log-item" key={`${line}-${index}`}>{line}</div>
          ))}
        </div>
      </section>
    </main>
  );
}

function Metric({ icon, label, value, invert = false }) {
  return (
    <article className={`metric ${invert ? "invert" : ""}`}>
      <div className="metric-head">
        <span>{label}</span>
        {icon}
      </div>
      <strong>{value}</strong>
    </article>
  );
}

function GamePanel({ eyebrow, title, icon, children }) {
  return (
    <article className="panel">
      <PanelHead eyebrow={eyebrow} title={title} icon={icon} />
      {children}
    </article>
  );
}

function PanelHead({ eyebrow, title, icon }) {
  return (
    <div className="panel-head">
      <div>
        <p className="eyebrow">{eyebrow}</p>
        <h2>{title}</h2>
      </div>
      {icon}
    </div>
  );
}

function Field({ label, as, options, ...props }) {
  return (
    <label>
      {label}
      {as === "select" ? (
        <select {...props}>
          {options.map((option) => (
            <option value={option} key={option}>{tokenDisplayName(option)}</option>
          ))}
        </select>
      ) : (
        <input {...props} required />
      )}
    </label>
  );
}

function parseUnits(value) {
  return ethers.parseEther(String(value || "0"));
}

function formatSepoliaEth(value) {
  return formatNative(trimNumber(ethers.formatEther(value)));
}

function formatFate(value) {
  return `${trimNumber(ethers.formatEther(value))} FATE`;
}

function trimNumber(value) {
  const [whole, fraction = ""] = value.split(".");
  const trimmed = fraction.slice(0, 4).replace(/0+$/, "");
  return trimmed ? `${whole}.${trimmed}` : whole;
}

function shortAddress(address) {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function shortHash(hash) {
  return `${hash.slice(0, 10)}...${hash.slice(-6)}`;
}

function commitmentFor(player, seed) {
  return ethers.keccak256(ethers.solidityPacked(["address", "bytes32"], [player, seed]));
}

function storageKey() {
  return `${STORAGE_PREFIX}:${cfg.arenaAddress || "local"}`;
}

function readPending() {
  try {
    return JSON.parse(localStorage.getItem(storageKey()) || "[]");
  } catch {
    return [];
  }
}

function savePending(item) {
  const items = readPending();
  items.push({ ...item, localId: `${item.type}:${item.id ?? item.roundId}:${item.entryIndex ?? "x"}:${Date.now()}` });
  localStorage.setItem(storageKey(), JSON.stringify(items));
}

function removePending(localId) {
  const items = readPending().filter((item) => item.localId !== localId);
  localStorage.setItem(storageKey(), JSON.stringify(items));
}

function readableError(error) {
  return error?.shortMessage || error?.reason || error?.message || "unknown error";
}
