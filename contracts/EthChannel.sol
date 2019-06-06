pragma solidity ^0.5.0;

import "./lib/RLPDecoder.sol";
import "./lib/ECDSA.sol";
import "./lib/SafeMath.sol";
import "./lib/IGame.sol";

/**
 * @notice Payment channel of dice game
 */
contract EthChannel {
    using RLPDecoder for RLPDecoder.RLPItem;
    using RLPDecoder for bytes;
    using ECDSA for bytes32;
    using SafeMath for uint;

    /* States */
    IGame public game;
    // peer state
    struct Peer {
        uint deposit;
        // whether the peer closed channel or not
        bool isCloser;
        bytes32 balanceHash;
        uint nonce;
    }

    enum ChannelStatus {Uninitialized, Open, Closed}
    struct Channel {
        ChannelStatus status;
        // peer address => peer state
        mapping(address => Peer) peer;
        // After opening the channel this value represents the settlement window, the number of blocks that need to be mined between closing the channel uncooperatively and settling the channel
        // After the channel has been uncooperatively closed, this value represents the block number after which settleChannel can be called.
        uint settleBlock;
    }

    // to generate channel id
    uint public channelCounter;
    // the key is keccak256(lexicographic order of peer-addresses)
    mapping(bytes32 => uint) public peers2counter;
    // the key is keccak256(keccak256(lexicographic order of peer-addresses), channelCounter, address of the contract)
    mapping(bytes32 => Channel) public id2channel;
    // lockID => (peerAddress => lockAmount)
    // lockID = keccak256(channelID, peersHash, lockNonce)
    mapping(bytes32 => mapping(address => uint)) public lockMap;
    // settleWindow = the number of blocks that need to be mined between closing the channel uncooperatively and settling the channel
    uint settleWindowMin;
    uint settleWindowMax;

    // decode rlp-encoded data to struct
    struct SettleData {
        address payable peer1;
        uint transferAmount1;
        uint lockAmount1;
        uint lockNonce1;
        address payable peer2;
        uint transferAmount2;
        uint lockAmount2;
        uint lockNonce2;
    }

    /* Constructor */
    constructor (address _game, uint _settleWindowMin, uint _settleWindowMax) public {
        require(_settleWindowMin > 0, "invalid settle window min");
        require(_settleWindowMin < _settleWindowMax, "settle window max should be greater than settle window min");
        game = IGame(_game);
        settleWindowMin = _settleWindowMin;
        settleWindowMax = _settleWindowMax;
    }

    /* Modifiers */
    modifier isOpened (bytes32 channelID) {
        require(id2channel[channelID].status == ChannelStatus.Open, "channel should be opened");
        _;
    }

    modifier isClosed (bytes32 channelID) {
        require(id2channel[channelID].status == ChannelStatus.Closed, "channel should be closed");
        _;
    }

    modifier settleWindowValid (uint settleWindow) {
        require(settleWindow <= settleWindowMax && settleWindow >= settleWindowMin, "invalid settle window");
        _;
    }

    /* Events */
    event OpenChannel(address indexed peer1, address indexed peer2, bytes32 channelID, uint settleWindow, uint peer1DepositValue);

    event DepositChannel(bytes32 indexed channelID, address indexed peer, uint depositValue, uint totalDepositValue);

    event CSettleChannel(bytes32 indexed channelID, address payable peer1, uint balance1, address payable peer2, uint balance2);

    event FCloseChannel(bytes32 indexed channelID, address closer, bytes32 balanceHash, uint nonce);

    event PartnerCommitProof(bytes32 indexed channelID, address commiter, bytes32 balanceHash, uint nonce);

    event FSettleChannel(bytes32 indexed channelID, address peer1, uint balance1, address peer2, uint balance2, bytes32 lockID);

    event Unlock(bytes32 indexed lockID, address peer1, uint balance1, address peer2, uint balance2);

    /* Public Functions */
    /**
     * @notice Open a channel of peer1 and peer2, peer1 deposit at the same time
     * @param peer1 one peer of channel
     * @param peer2 the other peer of channle
     * @param settleWindow set the settleWindow of channel
     */
    function openChannel(address peer1, address peer2, uint256 settleWindow ) public payable settleWindowValid(settleWindow) {
        bytes32 peersHash = getPeersHash(peer1, peer2);
        require(peers2counter[peersHash] == 0, "channel already exists");
        require(msg.value > 0, "should deposit when open channel");
        channelCounter += 1;
        peers2counter[peersHash] = channelCounter;

        bytes32 channelID = getChannelID(peer1, peer2);
        id2channel[channelID].status = ChannelStatus.Open;
        id2channel[channelID].settleBlock = settleWindow;

        Peer storage peer1State = id2channel[channelID].peer[peer1];
        peer1State.deposit = msg.value;
        emit OpenChannel(peer1, peer2, channelID, settleWindow, msg.value);
    }
    /**
     * @notice Can be called by anyone
     * @param id channel id
     * @param peer address of peer you want deposit in
     */
    function depositChannel(bytes32 id, address peer) public payable isOpened(id) {
        require(msg.value > 0, "invalid deposit");
        Peer storage peerState = id2channel[id].peer[peer];
        peerState.deposit = peerState.deposit.safeAdd(msg.value);
        emit DepositChannel(id, peer, msg.value, peerState.deposit);
    }
    /**
     * @notice Cooperative settle channel
     * @param peer1 one peer of channel
     * @param peer2 the other peer of channle
     * @param balance1 balance of peer1
     * @param balance2 balance of peer2
     * @param sig1 signature of peer1
     * @param sig2 signature of peer2
     */
    function cSettleChannel(address payable peer1, uint balance1, address payable peer2, uint balance2, bytes memory sig1, bytes memory sig2) public {
        bytes32 channelID = getChannelID(peer1, peer2);
        Channel storage channel = id2channel[channelID];
        require(channel.status == ChannelStatus.Open, "channel should be opened");
        bytes32 hash = keccak256(abi.encodePacked(channelID, peer1, balance1, peer2, balance2));
        require(hash.recover(sig1) == peer1, "invalid signature of peer1");
        require(hash.recover(sig2) == peer2, "invalid signature of peer2");
        require(channel.peer[peer1].deposit.safeAdd(channel.peer[peer2].deposit) >= balance1.safeAdd(balance2), "insufficient funds");

        delete channel.peer[peer1];
        delete channel.peer[peer2];
        delete id2channel[channelID];
        delete peers2counter[getPeersHash(peer1, peer2)];
        if(balance1 > 0) {
            peer1.transfer(balance1);
        }
        if(balance2 > 0) {
            peer2.transfer(balance2);
        }
        emit CSettleChannel(channelID, peer1, balance1, peer2, balance2);
    }

    /**
     * @notice Force close channel by msg.sender
     * @param partner the other peer of channel
     * @param balanceHash keccak256(transferAmount, lockAmount, lockNonce), received from partner
     * @param nonce strictly monotonic value used to order transfers
     * @param pSig signature of transfer proof, signed by partner
     */
    function fCloseChannel(address partner, bytes32 balanceHash, uint nonce, bytes memory pSig) public {
        bytes32 channelID = getChannelID(msg.sender, partner);
        Channel storage channel = id2channel[channelID];
        require(channel.status == ChannelStatus.Open, "channel should be open");
        if(nonce > 0) {
            verifyBalanceProof(channelID, balanceHash, nonce, pSig, partner);
            Peer storage partnerState = channel.peer[partner];
            partnerState.balanceHash = balanceHash;
            partnerState.nonce = nonce;
        }
        channel.peer[msg.sender].isCloser = true;
        channel.status = ChannelStatus.Closed;
        channel.settleBlock += block.number;
        emit FCloseChannel(channelID, msg.sender, balanceHash, nonce);
    }

    /**
     * @notice Partner commit balance proof, received from channel-closer, after channel closed
     * @param closer who had force closed channel
     * @param balanceHash keccak256(transferAmount, lockAmount, lockNonce), received from closer
     * @param nonce strictly monotonic value used to order transfers
     * @param cSig signature of transfer proof, signed by closers
     * @param pSig signature of partner, to permit someone else to commit proof for partner
     */
    function partnerCommitProof(address partner, address closer, bytes32 balanceHash, uint nonce, bytes memory cSig, bytes memory pSig) public {
        require(nonce > 0, "invalid nonce");
        bytes32 channelID = getChannelID(partner, closer);
        Channel storage channel = id2channel[channelID];
        require(channel.status == ChannelStatus.Closed, "channel should be closed");
        require(channel.settleBlock >= block.number, "commit block expired");
        verifyBalanceProof(channelID, balanceHash, nonce, cSig, closer);
        verifyBalanceProof(channelID, balanceHash, nonce, pSig, partner);
        Peer storage closerState = channel.peer[closer];
        require(closerState.isCloser, "invalid closer");
        require(closerState.nonce < nonce, "invalid nonce");
        closerState.balanceHash = balanceHash;
        closerState.nonce = nonce;
        emit PartnerCommitProof(channelID, msg.sender, balanceHash, nonce);
    }

    /**
     * @notice Settle after force close channel, can be called by anyone
     * @param data rlp encoded data, to decode to struct SettleData
     */
    function fSettleChannel(bytes memory data) public {
        SettleData memory s;
        RLPDecoder.RLPItem[] memory items = data.toRlpItem().toList();
        s.peer1 = address(uint160(items[0].toAddress()));
        s.transferAmount1 = items[1].toUint();
        s.lockAmount1 = items[2].toUint();
        s.lockNonce1 = items[3].toUint();
        s.peer2 = address(uint160(items[4].toAddress()));
        s.transferAmount2 = items[5].toUint();
        s.lockAmount2 = items[6].toUint();
        s.lockNonce2 = items[7].toUint();

        bytes32 channelID = getChannelID(s.peer1, s.peer2);
        Channel storage channel = id2channel[channelID];
        require(channel.status == ChannelStatus.Closed, "channel should be closed");
        require(channel.settleBlock < block.number, "settle window should be over");
        verifyBalanceHash(s.transferAmount1, s.lockAmount1, s.lockNonce1, channel.peer[s.peer1].balanceHash);
        verifyBalanceHash(s.transferAmount2, s.lockAmount2, s.lockNonce2, channel.peer[s.peer2].balanceHash);

        bytes32 lockID;
        (lockID, s.lockAmount1, s.lockAmount2) = resolveLockAmount(channelID, s.peer1, s.lockAmount1, s.lockNonce1, s.peer2, s.lockAmount2, s.lockNonce2);
        // balance of peer1 and peer2 after settled
        uint balance1;
        uint  balance2;
        (balance1, balance2) = resolveSettleAmount(channel.peer[s.peer1].deposit.safeSub(s.lockAmount1), s.transferAmount1, channel.peer[s.peer2].deposit.safeSub(s.lockAmount2), s.transferAmount2);

        delete channel.peer[s.peer1];
        delete channel.peer[s.peer2];
        delete id2channel[channelID];
        delete peers2counter[getPeersHash(s.peer1, s.peer2)];
        if(balance1 > 0) {
            s.peer1.transfer(balance1);
        }
        if(balance2 > 0) {
            s.peer2.transfer(balance2);
        }
        emit FSettleChannel(channelID, s.peer1, balance1, s.peer2, balance2, lockID);
    }

    /**
     * @notice Withdraw locked value if proof committed in game contract
     * @param lockID generated after force settle channel
     * @param peer1 address of one peer
     * @param peer2 address of the other peer
     */
    function unlock(bytes32 lockID, address payable peer1, address payable peer2) public {
        // balance of peer1 and peer2, determined by game result, to distribute lock amount
        uint balance1;
        uint balance2;
        // 0=nobody commit game proof, refund lock value
        // 1=commit game proof succeed, distribute value with game result
        uint status;
        (status, balance1, balance2) = game.getResult(lockID, peer1, peer2);
        if(status == 0) {
            balance1 = lockMap[lockID][peer1];
            balance2 = lockMap[lockID][peer2];
        } else {
            require(balance1.safeAdd(balance2) <= lockMap[lockID][peer1].safeAdd(lockMap[lockID][peer2]), "insufficient funds");
        }

        delete lockMap[lockID][peer1];
        delete lockMap[lockID][peer2];
        if(balance1 > 0) {
            peer1.transfer(balance1);
        }
        if(balance2 > 0) {
            peer2.transfer(balance2);
        }
        emit Unlock(lockID, peer1, balance1, peer2, balance2);
    }

    function getPeersHash(address peer1, address peer2) public pure returns (bytes32) {
        require(peer1 != address(0x0) && peer2 != address(0x0) && peer1 != peer2, "invalid peer address");
        if (peer1 < peer2) {
            return keccak256(abi.encodePacked(peer1, peer2));
        } else {
            return keccak256(abi.encodePacked(peer2, peer1));
        }
    }

    function getChannelID (address peer1, address peer2) public view returns (bytes32) {
        bytes32 peersHash = getPeersHash(peer1, peer2);
        uint256 counter = peers2counter[peersHash];
        return keccak256((abi.encodePacked(peersHash, counter, address(this))));
    }

    /* Internal Functions */
    function verifyBalanceProof(bytes32 id, bytes32 balanceHash, uint nonce, bytes memory sig, address signer) internal pure {
        bytes32 hash = keccak256(abi.encodePacked(id, balanceHash, nonce));
        require(hash.recover(sig) == signer, "invalid balance proof signature");
    }

    function verifyBalanceHash(uint transferAmount, uint lockAmount, uint lockNonce, bytes32 hash) internal pure {
        if (hash == 0x0 && transferAmount == 0 && lockAmount == 0 && lockNonce == 0) {
            return;
        }
        bytes32 balanceHash = keccak256(abi.encodePacked(transferAmount, lockAmount, lockNonce));
        require(balanceHash == hash, "balance hash should be correct");
    }

    function resolveLockAmount(bytes32 channelID, address peer1, uint lockAmount1, uint lockNonce1, address peer2, uint lockAmount2, uint lockNonce2) internal returns(bytes32 _lockID, uint _lockAmount1, uint _lockAmount2) {
        if(lockNonce1 == 0 && lockNonce2 == 0) {
            _lockID = 0x0;
            _lockAmount1 = 0;
            _lockAmount2 = 0;
            return (_lockID, _lockAmount1, _lockAmount2);
        }
        // uint lockNonce = lockNonce1>lockNonce2 ? lockNonce1:lockNonce2;
        uint lockNonce;
        if(lockNonce1 == lockNonce2) {
            (lockNonce, _lockAmount1, _lockAmount2) = (lockNonce1, lockAmount1, lockAmount2);
        } else {
            (lockNonce, _lockAmount1, _lockAmount2) = lockNonce1>lockNonce2 ? (lockNonce1, lockAmount1, uint256(0)):(lockNonce2, uint256(0), lockAmount2);
        }
        Channel storage channel = id2channel[channelID];
        require(channel.peer[peer1].deposit.safeAdd(channel.peer[peer2].deposit) >= _lockAmount1.safeAdd(_lockAmount2), "insufficient funds");
        _lockID = keccak256(abi.encodePacked(channelID, getPeersHash(peer1, peer2), lockNonce));
        lockMap[_lockID][peer1] = _lockAmount1;
        lockMap[_lockID][peer2] = _lockAmount2;
    }
    /**
     * @notice Calculate amount of value settled to each peer
     * @param aBalance1 available balance of peer1
     * @param transferAmount1 amount transferred from peer1 to peer2
     * @param aBalance2 available balance of peer2
     * @param transferAmount2 amount transferred from peer2 to peer1
     * @return balances of peer1 and peer2 after settled
     */
    function resolveSettleAmount(uint aBalance1, uint transferAmount1, uint aBalance2, uint transferAmount2) internal returns(uint sBalance1, uint sBalance2){
        uint margin;
        uint min;
        uint settleAmount;
        (margin, min) = transferAmount1.magicSub(transferAmount2);
        if(min == transferAmount1) {
            settleAmount = aBalance2 > margin ? margin : aBalance2;
            sBalance1 = aBalance1.safeAdd(settleAmount);
            sBalance2 = aBalance2.safeSub(settleAmount);
        } else {
            settleAmount = aBalance1 > margin ? margin : aBalance1;
            sBalance2 = aBalance2.safeAdd(settleAmount);
            sBalance1 = aBalance1.safeSub(settleAmount);
        }
    }
}