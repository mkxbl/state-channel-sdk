pragma solidity ^0.5.0;

import "../AppInterface.sol";
import "./IRandom.sol";
import "../lib/ECDSA.sol";
import "../lib/SafeMath.sol";

/**
 * @notice Support mainstream gaming: flip-coin, dice, two-dice, etheroll
 */
contract DiceGame is AppInterface {
    using ECDSA for bytes32;
    using SafeMath for uint;

    // max bits of betMask when playing flip-coin, dice, two-dice
    uint256 constant MAX_MASK_MODULO = 36;

    /* States */
    IRandom public randomContract;

    struct Result {
        // 0=nobody commit game proof, refund lock value
        // 1=commit game proof succeed, distribute value with game result
        uint status;
        address initiator;
        address acceptor;
        uint iStake;
        uint aStake;
        uint betMask;
        uint modulo;
    }

    // gameID => game result
    mapping(bytes32 => Result) public resultMap;

    /* Constructor */
    constructor(address _randomContract) public {
        randomContract = IRandom(_randomContract);
    }

    /* Events */
    event CommitProof(bytes32 indexed gameID, address indexed initiator, address indexed acceptor);

    /* External Functions */
    /**
     * @notice Called by payment channel to distribute lock value
     * @param gameID id of game, the same to lockID
     * @param gamer1 address of a gamer
     * @param gamer2 address of the other gamer
     * @return (status, balance of gamer1, balance of gamer2)
     */
    function getResult(bytes32 gameID, address gamer1, address gamer2) external returns(uint, uint, uint) {
        Result storage result = resultMap[gameID];
        if(result.status == 0) {
            return (0, 0, 0);
        }
        // 0=nobody commit random proof, refund lock value
        // 1=initiator did not reveal pre-image, winner is acceptor
        // 2=get random succeed
        uint status;
        // if status == 2, use random
        bytes32 random;
        // if status == 1, use winner
        address winner;
        (status, random, winner) = randomContract.getRandom(gameID, result.initiator, result.acceptor);
        if(status == 0) {
            return (0, 0, 0);
        } else if(status == 2) {
            winner = isInitiatorWin(result.betMask, result.modulo, random) ? result.initiator : result.acceptor;
        }
        return gamer1 == winner ? (1, result.iStake.safeAdd(result.aStake), uint(0)) : (1, uint(0), result.iStake.safeAdd(result.aStake));
    }

    /* Public Functions */
    /**
     * @notice Commit game proof when disputing off-chain
     * @param round game round
     * @param channelID id of channel two gamers in
     * @param initiator address of one peer who trigger game
     * @param acceptor address of the other peer who accept game
     * @param iStake bet stake of initiator, which locked in channel
     * @param aStake bet stake of acceptor, which locked in channel
     * @param betMask outcome initiator bet on, and acceptor bet on the other side automatic
     * @param modulo which kind of game: 1=flip-coin, 6=dice, 36=two-dice, 100=etheroll
     * @param iSig signature of initiator
     * @param aSig signature of acceptor
     */
    function commitProof(uint round, bytes32 channelID, address initiator, address acceptor, uint256 iStake, uint256 aStake, uint256 betMask, uint256 modulo, bytes memory iSig, bytes memory aSig) public {
        bytes32 hash = keccak256(abi.encodePacked(round, channelID, initiator, acceptor, iStake, aStake, betMask, modulo));
        require(hash.recover(iSig) == initiator, "invalid signature of initiator");
        require(hash.recover(aSig) == acceptor, "invalid signature of acceptor");
        bytes32 gameID = keccak256(abi.encodePacked(channelID, getPeersHash(initiator, acceptor), round));
        Result storage result = resultMap[gameID];
        result.status = 1;
        result.initiator = initiator;
        result.acceptor = acceptor;
        result.iStake = iStake;
        result.aStake = aStake;
        result.betMask = betMask;
        result.modulo = modulo;
        emit CommitProof(gameID, initiator, acceptor);
    }

    /* Internal Functions */
    function isInitiatorWin(uint256 betMask, uint256 modulo, bytes32 random) internal returns(bool) {
        uint256 dice = uint256(random) % modulo;
        if (modulo <= MAX_MASK_MODULO) {
            return ((2 ** dice) & uint40(betMask)) != 0 ? true : false;
        } else {
            return dice < betMask ? true : false;
        }
    }

    function getPeersHash(address peer1, address peer2) public pure returns (bytes32) {
        require(peer1 != address(0x0) && peer2 != address(0x0) && peer1 != peer2, "invalid peer address");
        if (peer1 < peer2) {
            return keccak256(abi.encodePacked(peer1, peer2));
        } else {
            return keccak256(abi.encodePacked(peer2, peer1));
        }
    }
}