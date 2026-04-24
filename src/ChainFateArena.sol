// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IRandomnessCoordinator, IRandomnessConsumer } from "./interfaces/IRandomnessCoordinator.sol";

error InvalidToken();
error InvalidAmount();
error InvalidRange();
error InvalidCommitment();
error InsufficientLiquidity();
error RandomnessPending();
error RandomnessNotReady();
error RevealWindowOpen();
error RevealWindowClosed();
error AlreadySettled();
error AlreadyFinalized();
error RoundStillOpen();
error RoundClosed();
error NoTicketsSold();
error NotEntryOwner();
error OnlyCoordinator();
error InvalidRequest();
error TransferFailed();

/// @title ChainFateArena
/// @notice SC6107 Option 4 project: a verifiable random game platform with dice and raffle games.
contract ChainFateArena is IRandomnessConsumer, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS = 10_000;
    uint8 public constant DICE_SIDES = 100;
    address public constant ETH = address(0);

    enum RequestKind {
        None,
        Dice,
        Raffle
    }

    struct TokenConfig {
        bool enabled;
        uint16 houseEdgeBps;
        uint128 minBet;
        uint128 maxBet;
    }

    struct DiceBet {
        address player;
        address token;
        uint128 wager;
        uint128 revealBond;
        uint256 quotedPayout;
        uint256 requestId;
        uint64 requestTimestamp;
        uint64 revealDeadline;
        uint8 rollUnder;
        uint8 rolled;
        bool randomnessReady;
        bool settled;
        bool won;
        bytes32 seedCommitment;
        uint256 vrfWord;
        bytes32 proofHash;
    }

    struct RaffleRound {
        address token;
        uint64 closesAt;
        uint256 requestId;
        uint64 requestTimestamp;
        uint64 revealDeadline;
        uint32 totalTickets;
        uint32 winningTicket;
        uint128 ticketPrice;
        uint128 pot;
        bool randomnessReady;
        bool finalized;
        address winner;
        bytes32 aggregateSeed;
        uint256 vrfWord;
        bytes32 proofHash;
    }

    struct RaffleEntry {
        address player;
        uint32 firstTicket;
        uint32 ticketCount;
        uint128 revealBond;
        bool revealed;
        bytes32 seedCommitment;
    }

    struct PlayerStats {
        uint32 dicePlayed;
        uint32 diceWon;
        uint32 raffleEntries;
        uint32 raffleWon;
        uint32 seedsRevealed;
        uint32 bondsSlashed;
    }

    struct RequestMeta {
        RequestKind kind;
        uint256 entityId;
    }

    IRandomnessCoordinator public coordinator;
    uint64 public randomnessTimeout = 15 minutes;
    uint64 public diceRevealPeriod = 20 minutes;
    uint64 public raffleRevealPeriod = 30 minutes;

    uint256 public nextDiceBetId = 1;
    uint256 public nextRaffleRoundId = 1;

    mapping(address => TokenConfig) public tokenConfigs;
    mapping(address => uint256) public treasuryBalance;
    mapping(address => uint256) public reservedDicePayouts;
    mapping(address => uint256) public reservedRevealBonds;
    mapping(address => uint256) public reservedRafflePots;
    mapping(address => PlayerStats) public playerStats;

    mapping(uint256 => DiceBet) private diceBets;
    mapping(uint256 => RaffleRound) private raffleRounds;
    mapping(uint256 => RaffleEntry[]) private raffleEntries;
    mapping(uint256 => RequestMeta) public requests;

    event TokenConfigured(
        address indexed token, bool enabled, uint16 houseEdgeBps, uint128 minBet, uint128 maxBet
    );
    event CoordinatorUpdated(address indexed newCoordinator);
    event TimingUpdated(uint64 randomnessTimeout, uint64 diceRevealPeriod, uint64 raffleRevealPeriod);
    event BankrollSeeded(address indexed token, address indexed from, uint256 amount);
    event TreasuryWithdrawn(address indexed token, address indexed to, uint256 amount);

    event DiceCommitted(
        uint256 indexed betId,
        address indexed player,
        address indexed token,
        uint256 wager,
        uint8 rollUnder,
        uint256 requestId,
        bytes32 seedCommitment
    );
    event DiceRandomnessReady(
        uint256 indexed betId, uint256 indexed requestId, uint256 vrfWord, bytes32 proofHash
    );
    event DiceRetryRequested(uint256 indexed betId, uint256 indexed requestId);
    event DiceSettled(uint256 indexed betId, uint8 rolled, bool won, uint256 payout);
    event DiceExpired(uint256 indexed betId, address indexed player, uint256 slashedAmount);

    event RaffleCreated(uint256 indexed roundId, address indexed token, uint256 ticketPrice, uint64 closesAt);
    event RaffleTicketsBought(
        uint256 indexed roundId,
        uint256 indexed entryIndex,
        address indexed player,
        uint32 ticketCount,
        bytes32 seedCommitment
    );
    event RaffleDrawRequested(uint256 indexed roundId, uint256 indexed requestId);
    event RaffleRandomnessReady(
        uint256 indexed roundId, uint256 indexed requestId, uint256 vrfWord, bytes32 proofHash
    );
    event RaffleSeedRevealed(uint256 indexed roundId, uint256 indexed entryIndex, address indexed player);
    event RaffleRetryRequested(uint256 indexed roundId, uint256 indexed requestId);
    event RaffleFinalized(
        uint256 indexed roundId, address indexed winner, uint32 winningTicket, uint256 payout, uint256 fee
    );

    constructor(address initialOwner, address randomnessCoordinator) Ownable(initialOwner) {
        if (randomnessCoordinator == address(0)) revert InvalidRequest();
        coordinator = IRandomnessCoordinator(randomnessCoordinator);
    }

    receive() external payable { }

    modifier onlyCoordinator() {
        if (msg.sender != address(coordinator)) revert OnlyCoordinator();
        _;
    }

    /// @notice Pauses user-facing gameplay actions during an incident.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resumes gameplay actions after an incident has been resolved.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Enables or updates ETH/ERC-20 betting parameters.
    function configureToken(address token, bool enabled, uint16 houseEdgeBps, uint128 minBet, uint128 maxBet)
        external
        onlyOwner
    {
        if (houseEdgeBps > 1_500 || minBet == 0 || maxBet < minBet) revert InvalidAmount();
        tokenConfigs[token] =
            TokenConfig({ enabled: enabled, houseEdgeBps: houseEdgeBps, minBet: minBet, maxBet: maxBet });
        emit TokenConfigured(token, enabled, houseEdgeBps, minBet, maxBet);
    }

    /// @notice Replaces the randomness coordinator or adapter.
    function setCoordinator(address newCoordinator) external onlyOwner {
        if (newCoordinator == address(0)) revert InvalidRequest();
        coordinator = IRandomnessCoordinator(newCoordinator);
        emit CoordinatorUpdated(newCoordinator);
    }

    /// @notice Updates timeout windows used for retries and seed reveal phases.
    function setTimings(uint64 newRandomnessTimeout, uint64 newDiceRevealPeriod, uint64 newRaffleRevealPeriod)
        external
        onlyOwner
    {
        if (newRandomnessTimeout == 0 || newDiceRevealPeriod == 0 || newRaffleRevealPeriod == 0) {
            revert InvalidAmount();
        }
        randomnessTimeout = newRandomnessTimeout;
        diceRevealPeriod = newDiceRevealPeriod;
        raffleRevealPeriod = newRaffleRevealPeriod;
        emit TimingUpdated(newRandomnessTimeout, newDiceRevealPeriod, newRaffleRevealPeriod);
    }

    /// @notice Adds house bankroll liquidity for payouts.
    function seedBankroll(address token, uint256 amount) external payable onlyOwner nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (token == ETH) {
            if (msg.value != amount) revert InvalidAmount();
        } else {
            if (msg.value != 0) revert InvalidAmount();
            _safeTransferFrom(token, msg.sender, address(this), amount);
        }
        emit BankrollSeeded(token, msg.sender, amount);
    }

    /// @notice Withdraws realized house fees and slashed funds.
    function withdrawTreasury(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0) || amount == 0 || treasuryBalance[token] < amount) revert InvalidAmount();
        treasuryBalance[token] -= amount;
        _payout(token, to, amount);
        emit TreasuryWithdrawn(token, to, amount);
    }

    /// @notice Commits to a dice bet and requests VRF-style randomness.
    function commitDiceBet(
        address token,
        uint128 wager,
        uint8 rollUnder,
        bytes32 seedCommitment,
        uint128 revealBond
    ) external payable whenNotPaused nonReentrant returns (uint256 betId) {
        TokenConfig memory config = _requireToken(token);
        if (wager < config.minBet || wager > config.maxBet) revert InvalidAmount();
        if (rollUnder < 2 || rollUnder > 95) revert InvalidRange();
        if (seedCommitment == bytes32(0) || revealBond < wager / 20) revert InvalidCommitment();

        uint256 payout = quoteDicePayout(token, wager, rollUnder);
        _collectPayment(token, wager + revealBond);
        if (availableBankroll(token) < payout + revealBond) revert InsufficientLiquidity();

        uint256 requestId = coordinator.requestRandomness();
        betId = nextDiceBetId++;

        reservedDicePayouts[token] += payout;
        reservedRevealBonds[token] += revealBond;

        diceBets[betId] = DiceBet({
            player: msg.sender,
            token: token,
            wager: wager,
            revealBond: revealBond,
            quotedPayout: payout,
            requestId: requestId,
            requestTimestamp: uint64(block.timestamp),
            revealDeadline: 0,
            rollUnder: rollUnder,
            rolled: 0,
            randomnessReady: false,
            settled: false,
            won: false,
            seedCommitment: seedCommitment,
            vrfWord: 0,
            proofHash: bytes32(0)
        });
        requests[requestId] = RequestMeta({ kind: RequestKind.Dice, entityId: betId });
        playerStats[msg.sender].dicePlayed += 1;

        emit DiceCommitted(betId, msg.sender, token, wager, rollUnder, requestId, seedCommitment);
    }

    /// @notice Requests a fresh random word if the coordinator stalls.
    function retryDiceRandomness(uint256 betId)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 requestId)
    {
        DiceBet storage bet = diceBets[betId];
        if (bet.player == address(0)) revert InvalidRequest();
        if (bet.settled || bet.randomnessReady) revert AlreadySettled();
        if (block.timestamp < bet.requestTimestamp + randomnessTimeout) revert RandomnessPending();

        requestId = coordinator.requestRandomness();
        bet.requestId = requestId;
        bet.requestTimestamp = uint64(block.timestamp);
        requests[requestId] = RequestMeta({ kind: RequestKind.Dice, entityId: betId });
        emit DiceRetryRequested(betId, requestId);
    }

    /// @notice Reveals the pre-committed seed and settles the dice outcome.
    function revealDiceSeed(uint256 betId, bytes32 seed) external nonReentrant {
        DiceBet storage bet = diceBets[betId];
        if (bet.player != msg.sender) revert NotEntryOwner();
        if (!bet.randomnessReady) revert RandomnessNotReady();
        if (bet.settled) revert AlreadySettled();
        if (block.timestamp > bet.revealDeadline) revert RevealWindowClosed();
        if (commitmentFor(msg.sender, seed) != bet.seedCommitment) revert InvalidCommitment();

        uint8 rolled = previewDiceRoll(bet.vrfWord, seed, msg.sender, betId);
        bool won = rolled <= bet.rollUnder;
        uint256 payout = won ? bet.quotedPayout : 0;

        bet.rolled = rolled;
        bet.won = won;
        bet.settled = true;
        reservedDicePayouts[bet.token] -= bet.quotedPayout;
        reservedRevealBonds[bet.token] -= bet.revealBond;
        playerStats[msg.sender].seedsRevealed += 1;

        if (won) {
            playerStats[msg.sender].diceWon += 1;
            _payout(bet.token, msg.sender, payout + bet.revealBond);
        } else {
            treasuryBalance[bet.token] += bet.wager;
            _payout(bet.token, msg.sender, bet.revealBond);
        }

        emit DiceSettled(betId, rolled, won, payout);
    }

    /// @notice Slashes an unrevealed dice bet after the reveal deadline.
    function slashExpiredDice(uint256 betId) external nonReentrant {
        DiceBet storage bet = diceBets[betId];
        if (!bet.randomnessReady) revert RandomnessNotReady();
        if (bet.settled) revert AlreadySettled();
        if (block.timestamp <= bet.revealDeadline) revert RevealWindowOpen();

        bet.settled = true;
        reservedDicePayouts[bet.token] -= bet.quotedPayout;
        reservedRevealBonds[bet.token] -= bet.revealBond;
        treasuryBalance[bet.token] += uint256(bet.wager) + bet.revealBond;
        playerStats[bet.player].bondsSlashed += 1;

        emit DiceExpired(betId, bet.player, uint256(bet.wager) + bet.revealBond);
    }

    /// @notice Opens a time-based raffle round.
    function createRaffleRound(address token, uint128 ticketPrice, uint64 closesAt)
        external
        onlyOwner
        whenNotPaused
        returns (uint256 roundId)
    {
        TokenConfig memory config = _requireToken(token);
        if (ticketPrice < config.minBet || ticketPrice > config.maxBet || closesAt <= block.timestamp) {
            revert InvalidAmount();
        }

        roundId = nextRaffleRoundId++;
        raffleRounds[roundId] = RaffleRound({
            token: token,
            closesAt: closesAt,
            requestId: 0,
            requestTimestamp: 0,
            revealDeadline: 0,
            totalTickets: 0,
            winningTicket: 0,
            ticketPrice: ticketPrice,
            pot: 0,
            randomnessReady: false,
            finalized: false,
            winner: address(0),
            aggregateSeed: bytes32(0),
            vrfWord: 0,
            proofHash: bytes32(0)
        });
        emit RaffleCreated(roundId, token, ticketPrice, closesAt);
    }

    /// @notice Buys raffle tickets and commits to a later seed reveal.
    function buyRaffleTickets(uint256 roundId, uint32 ticketCount, bytes32 seedCommitment, uint128 revealBond)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 entryIndex)
    {
        RaffleRound storage round = raffleRounds[roundId];
        if (round.ticketPrice == 0) revert InvalidRequest();
        if (round.finalized || block.timestamp >= round.closesAt) revert RoundClosed();
        if (ticketCount == 0 || seedCommitment == bytes32(0)) revert InvalidAmount();

        uint256 ticketCost = uint256(round.ticketPrice) * ticketCount;
        if (revealBond < round.ticketPrice / 2) revert InvalidCommitment();
        if (ticketCost > type(uint128).max - round.pot) revert InvalidAmount();

        _collectPayment(round.token, ticketCost + revealBond);
        entryIndex = raffleEntries[roundId].length;
        raffleEntries[roundId].push(
            RaffleEntry({
                player: msg.sender,
                firstTicket: round.totalTickets,
                ticketCount: ticketCount,
                revealBond: revealBond,
                revealed: false,
                seedCommitment: seedCommitment
            })
        );

        round.totalTickets += ticketCount;
        // forge-lint: disable-next-line(unsafe-typecast)
        round.pot += uint128(ticketCost);
        reservedRafflePots[round.token] += ticketCost;
        reservedRevealBonds[round.token] += revealBond;
        playerStats[msg.sender].raffleEntries += 1;

        emit RaffleTicketsBought(roundId, entryIndex, msg.sender, ticketCount, seedCommitment);
    }

    /// @notice Requests randomness after a raffle closes.
    function drawRaffle(uint256 roundId) external whenNotPaused nonReentrant returns (uint256 requestId) {
        RaffleRound storage round = raffleRounds[roundId];
        if (round.ticketPrice == 0) revert InvalidRequest();
        if (block.timestamp < round.closesAt) revert RoundStillOpen();
        if (round.finalized || round.randomnessReady) revert AlreadyFinalized();
        if (round.totalTickets == 0) revert NoTicketsSold();
        if (round.requestId != 0) revert RandomnessPending();

        requestId = coordinator.requestRandomness();
        round.requestId = requestId;
        round.requestTimestamp = uint64(block.timestamp);
        requests[requestId] = RequestMeta({ kind: RequestKind.Raffle, entityId: roundId });
        emit RaffleDrawRequested(roundId, requestId);
    }

    /// @notice Requests fresh raffle randomness if the coordinator stalls.
    function retryRaffleRandomness(uint256 roundId)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 requestId)
    {
        RaffleRound storage round = raffleRounds[roundId];
        if (round.ticketPrice == 0 || round.totalTickets == 0) revert InvalidRequest();
        if (round.finalized || round.randomnessReady) revert AlreadyFinalized();
        if (round.requestId == 0 || block.timestamp < round.requestTimestamp + randomnessTimeout) {
            revert RandomnessPending();
        }

        requestId = coordinator.requestRandomness();
        round.requestId = requestId;
        round.requestTimestamp = uint64(block.timestamp);
        requests[requestId] = RequestMeta({ kind: RequestKind.Raffle, entityId: roundId });
        emit RaffleRetryRequested(roundId, requestId);
    }

    /// @notice Reveals one raffle entry seed and refunds the reveal bond.
    function revealRaffleSeed(uint256 roundId, uint256 entryIndex, bytes32 seed) external nonReentrant {
        RaffleRound storage round = raffleRounds[roundId];
        if (!round.randomnessReady) revert RandomnessNotReady();
        if (round.finalized) revert AlreadyFinalized();
        if (block.timestamp > round.revealDeadline) revert RevealWindowClosed();

        RaffleEntry storage entry = raffleEntries[roundId][entryIndex];
        if (entry.player != msg.sender) revert NotEntryOwner();
        if (entry.revealed) revert AlreadySettled();
        if (commitmentFor(msg.sender, seed) != entry.seedCommitment) revert InvalidCommitment();

        entry.revealed = true;
        round.aggregateSeed = keccak256(abi.encodePacked(round.aggregateSeed, seed, entryIndex, msg.sender));
        reservedRevealBonds[round.token] -= entry.revealBond;
        playerStats[msg.sender].seedsRevealed += 1;
        _payout(round.token, msg.sender, entry.revealBond);

        emit RaffleSeedRevealed(roundId, entryIndex, msg.sender);
    }

    /// @notice Finalizes the raffle after the reveal phase and pays the winner.
    function finalizeRaffle(uint256 roundId) external nonReentrant {
        RaffleRound storage round = raffleRounds[roundId];
        if (!round.randomnessReady) revert RandomnessNotReady();
        if (round.finalized) revert AlreadyFinalized();
        if (block.timestamp <= round.revealDeadline) revert RevealWindowOpen();

        RaffleEntry[] storage entries = raffleEntries[roundId];
        uint256 slashed = 0;
        for (uint256 i = 0; i < entries.length; ++i) {
            if (!entries[i].revealed) {
                entries[i].revealed = true;
                slashed += entries[i].revealBond;
                reservedRevealBonds[round.token] -= entries[i].revealBond;
                playerStats[entries[i].player].bondsSlashed += 1;
            }
        }

        bytes32 entropy =
            keccak256(abi.encodePacked(round.vrfWord, round.aggregateSeed, roundId, round.totalTickets));
        uint32 winningTicket = uint32(uint256(entropy) % round.totalTickets);
        uint256 winningEntryIndex = _findWinningEntry(entries, winningTicket);
        address winner = entries[winningEntryIndex].player;

        TokenConfig memory config = _requireToken(round.token);
        uint256 fee = (uint256(round.pot) * config.houseEdgeBps) / BASIS_POINTS;
        uint256 payout = uint256(round.pot) - fee;

        round.finalized = true;
        round.winningTicket = winningTicket;
        round.winner = winner;
        reservedRafflePots[round.token] -= round.pot;
        treasuryBalance[round.token] += fee + slashed;
        playerStats[winner].raffleWon += 1;
        _payout(round.token, winner, payout);

        emit RaffleFinalized(roundId, winner, winningTicket, payout, fee);
    }

    /// @inheritdoc IRandomnessConsumer
    function rawFulfillRandomness(uint256 requestId, uint256 randomWord, bytes32 proofHash)
        external
        onlyCoordinator
    {
        RequestMeta memory meta = requests[requestId];
        if (meta.kind == RequestKind.None) revert InvalidRequest();
        if (meta.kind == RequestKind.Dice) {
            _storeDiceRandomness(meta.entityId, requestId, randomWord, proofHash);
        } else {
            _storeRaffleRandomness(meta.entityId, requestId, randomWord, proofHash);
        }
    }

    /// @notice Returns gross dice payout including house edge.
    function quoteDicePayout(address token, uint256 wager, uint8 rollUnder) public view returns (uint256) {
        TokenConfig memory config = _requireToken(token);
        if (rollUnder < 2 || rollUnder > 95) revert InvalidRange();
        return
            (wager * (BASIS_POINTS - config.houseEdgeBps) * DICE_SIDES) / (uint256(rollUnder) * BASIS_POINTS);
    }

    /// @notice Builds a commitment used by both games.
    function commitmentFor(address player, bytes32 seed) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(player, seed));
    }

    /// @notice Previews the dice roll for a fulfilled VRF word and revealed seed.
    function previewDiceRoll(uint256 vrfWord, bytes32 seed, address player, uint256 betId)
        public
        pure
        returns (uint8)
    {
        return uint8((uint256(keccak256(abi.encodePacked(vrfWord, seed, player, betId))) % DICE_SIDES) + 1);
    }

    /// @notice Returns a raffle entry.
    function getRaffleEntry(uint256 roundId, uint256 entryIndex) external view returns (RaffleEntry memory) {
        return raffleEntries[roundId][entryIndex];
    }

    /// @notice Returns the full dice bet struct for frontends and tests.
    function getDiceBet(uint256 betId) external view returns (DiceBet memory) {
        return diceBets[betId];
    }

    /// @notice Returns the full raffle round struct for frontends and tests.
    function getRaffleRound(uint256 roundId) external view returns (RaffleRound memory) {
        return raffleRounds[roundId];
    }

    /// @notice Returns the number of entries in a raffle round.
    function getRaffleEntryCount(uint256 roundId) external view returns (uint256) {
        return raffleEntries[roundId].length;
    }

    /// @notice Returns funds not reserved for payouts, bonds, pots, or realized treasury.
    function availableBankroll(address token) public view returns (uint256) {
        uint256 balance = _balanceOf(token);
        uint256 reserved = treasuryBalance[token] + reservedDicePayouts[token] + reservedRevealBonds[token]
            + reservedRafflePots[token];
        return balance > reserved ? balance - reserved : 0;
    }

    function _storeDiceRandomness(uint256 betId, uint256 requestId, uint256 randomWord, bytes32 proofHash)
        internal
    {
        DiceBet storage bet = diceBets[betId];
        if (bet.requestId != requestId || bet.randomnessReady || bet.settled) return;
        bet.randomnessReady = true;
        bet.vrfWord = randomWord;
        bet.proofHash = proofHash;
        bet.revealDeadline = uint64(block.timestamp + diceRevealPeriod);
        delete requests[requestId];
        emit DiceRandomnessReady(betId, requestId, randomWord, proofHash);
    }

    function _storeRaffleRandomness(uint256 roundId, uint256 requestId, uint256 randomWord, bytes32 proofHash)
        internal
    {
        RaffleRound storage round = raffleRounds[roundId];
        if (round.requestId != requestId || round.randomnessReady || round.finalized) return;
        round.randomnessReady = true;
        round.vrfWord = randomWord;
        round.proofHash = proofHash;
        round.revealDeadline = uint64(block.timestamp + raffleRevealPeriod);
        delete requests[requestId];
        emit RaffleRandomnessReady(roundId, requestId, randomWord, proofHash);
    }

    function _findWinningEntry(RaffleEntry[] storage entries, uint32 winningTicket)
        internal
        view
        returns (uint256)
    {
        for (uint256 i = 0; i < entries.length; ++i) {
            uint32 first = entries[i].firstTicket;
            uint32 lastExclusive = first + entries[i].ticketCount;
            if (winningTicket >= first && winningTicket < lastExclusive) {
                return i;
            }
        }
        revert InvalidRequest();
    }

    function _collectPayment(address token, uint256 amount) internal {
        if (token == ETH) {
            if (msg.value != amount) revert InvalidAmount();
        } else {
            if (msg.value != 0) revert InvalidAmount();
            _safeTransferFrom(token, msg.sender, address(this), amount);
        }
    }

    function _payout(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == ETH) {
            (bool success,) = payable(to).call{ value: amount }("");
            if (!success) revert TransferFailed();
        } else {
            _safeTransfer(token, to, amount);
        }
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function _balanceOf(address token) internal view returns (uint256) {
        return token == ETH ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    function _requireToken(address token) internal view returns (TokenConfig memory config) {
        config = tokenConfigs[token];
        if (!config.enabled) revert InvalidToken();
    }
}
