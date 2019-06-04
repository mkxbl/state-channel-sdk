pragma solidity ^0.5.0;

import "./lib/ECDSA.sol";
import "./lib/SafeMath.sol";
import "./DiceGame.sol";

contract EthChannel {
    using ECDSA for bytes32;
    using SafeMath for uint;

    /* States */
    DiceGame public game;
    // peer state
    struct Peer {
        uint deposit;
        // whether the peer closed channel or not
        bool isCloser;
        bytes32 balanceHash;
        uint nonce;
    }

    struct Channel {
        // 1 = open, 2 = closed
        // 0 = non-existent or settled
        uint state;
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

    uint settleWindowMin;
    uint settleWindowMax;

    /* Constructor */
    constructor (address _game, uint _settleWindowMin, uint _settleWindowMax) public {
        require(_settleWindowMin > 0, "invalid settle window min");
        require(_settleWindowMin < _settleWindowMax, "settle window max should be greater than settle window min");
        game = DiceGame(_game);
        settleWindowMin = _settleWindowMin;
        settleWindowMax = _settleWindowMax;
    }

    /* Modifiers */
    modifier isOpened (bytes32 channelID) {
        require(id2channel[channelID].state == 1, "channel should be opened");
        _;
    }

    modifier isClosed (bytes32 channelID) {
        require(id2channel[channelID].state == 1, "channel should be opened");
        _;
    }

    modifier settleWindowValid (uint settleWindow) {
        require(settleWindow <= settleWindowMax && settleWindow >= settleWindowMin, "invalid settle window");
        _;
    }

    /* Events */
    event OpenChannel(address peer1, address peer2, bytes32 id, uint settleWindow, uint peer1DepositValue);

    event DepositChannel(bytes32 id, address peer, uint depositValue, uint totalDepositValue);

    event CSettleChannel(bytes32 id, address payable peer1, uint balance1, address payable peer2, uint balance2);

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
        id2channel[channelID].state = 1;
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
        require(channel.state == 1, "channel should be opened");
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
        if(balance2 >0) {
            peer2.transfer(balance2);
        }
        emit CSettleChannel(channelID, peer1, balance1, peer2, balance2);
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
}